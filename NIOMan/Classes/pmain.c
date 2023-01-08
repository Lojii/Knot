/*-
 */

/* silence daemon(3) deprecation warning on Mac OS X */
#if __APPLE__
#define daemon xdaemon
#endif /* __APPLE__ */

#include "pmain.h"

#include "opts.h"
#include "filter.h"
#include "proxy.h"
#include "privsep.h"
#include "ssl.h"
#include "proc.h"
#include "cachemgr.h"
#include "sys.h"
#include "log.h"
#include "build.h"
#include "defaults.h"
#include "utils/util.h"

#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>
#include <signal.h>
#include <string.h>
//#include <sys/random.h>
#ifndef __BSD__
#include <getopt.h>
#endif /* !__BSD__ */

#include <openssl/ssl.h>
#include <openssl/x509.h>
#include <event2/event.h>

#if __APPLE__
#undef daemon
extern int daemon(int, int);
#endif /* __APPLE__ */

//#include <iostream>
#include <string.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netdb.h>//结构体addrinfo, in_addr
#include <netinet/in.h>
#include <arpa/inet.h>

//
///*
///
// * Print version information to stderr.
// */
int maintest(void){
    printf("-----------");
    return 0;
}
/*
 * Callback to load a cert/chain/key combo from a single PEM file for -t.
 * A return value of -1 indicates a fatal error to the file walker.
 */
static int
main_load_leafcert(const char *filename, void *arg)
{
	global_t *global = arg;
	cert_t *cert;
	char **names;

	cert = opts_load_cert_chain_key(filename);
	if (!cert)
		return -1;

	if (OPTS_DEBUG(global)) {
		log_dbg_printf("Targets for '%s':", filename);
	}
	names = ssl_x509_names(cert->crt);
	for (char **p = names; *p; p++) {
		/* be deliberately vulnerable to NULL prefix attacks */
		char *sep;
		if ((sep = strchr(*p, '!'))) {
			*sep = '\0';
		}
		if (OPTS_DEBUG(global)) {
			log_dbg_printf(" '%s'", *p);
		}
		cachemgr_tgcrt_set(*p, cert);
		free(*p);
	}
	if (OPTS_DEBUG(global)) {
		log_dbg_printf("\n");
	}
	free(names);
	cert_free(cert);
	return 0;
}

// 检查opts里的证书配置是否正确
static int WUNRES
main_check_opts(opts_t *opts, conn_opts_t *conn_opts, const char *argv0, const char *name)
{
	if (conn_opts->cacrt && !conn_opts->cakey) {
		fprintf(stderr, "%s: no CA key specified (-k) in %s.\n", argv0, name);
		return -1;
	}
	if (conn_opts->cakey && !conn_opts->cacrt) {
		fprintf(stderr, "%s: no CA cert specified (-c) in %s.\n", argv0, name);
		return -1;
	}
	if (conn_opts->cakey && conn_opts->cacrt &&
		(X509_check_private_key(conn_opts->cacrt, conn_opts->cakey) != 1)) {
		fprintf(stderr, "%s: CA cert does not match key in %s.\n", argv0, name);
		ERR_print_errors_fp(stderr);
		return -1;
	}
	if (!conn_opts->cakey &&
	    !opts->global->leafcertdir &&
	    !opts->global->defaultleafcert) {
		fprintf(stderr, "%s: at least one of -c/-k, -t or -A must be specified in %s.\n", argv0, name);
		return -1;
	}
	return 0;
}

/*
 * Handle out of memory conditions in early stages of main().
 * Print error message and exit with failure status code.
 * Does not return.
 */
static void NONNULL(1) NORET
oom_die(const char *argv0)
{
	fprintf(stderr, "%s: out of memory\n", argv0);
	exit(EXIT_FAILURE);
}

proxy_ctx_t *global_proxy;

// 启动参数，保留
char *crt_path;
char *key_path;
char *logs_path;
char *rule_path;

int need_reopen = 0; // 0:不需要重启  1:需要重启
char *reopen_task_id;   // 重启任务id
int reopen_listener_count;  // 重启监听
char *reopen_listener_list[10];
long long unsigned int reopen_conn_count; // 起始连接数

/*
 * Main entry point.
 */
int
man_run(int listenerCount, char *listenerList[], char *crtPath, char *keyPath, char *logsPath, char *rulePath, char *taskId)
{
    if (global_proxy != NULL) {
        printf("正在运行，请勿重复运行\n");
        return 0;
    }
	const char *argv0;
    argv0 = "监听配置";
    
	global_t *global;
	int pidfd = -1;
	int test_config = 0;
	int rv = EXIT_FAILURE;

	global = global_new();
    global->task_id = taskId;
    global->init_conn_num = maxConnNum(taskId) + 1;
    global->init_in_bytes = initInBytes(taskId);
    global->init_out_bytes = initOutBytes(taskId);
    printf("--> 起始计数:%lld In:%lld Out:%lld\n",global->init_conn_num, global->init_in_bytes, global->init_out_bytes);
    
	tmp_opts_t *global_tmp_opts = malloc(sizeof(tmp_opts_t));
	memset(global_tmp_opts, 0, sizeof(tmp_opts_t));
    
//    if (global_load_conffile(global, argv0, rulePath, NULL, global_tmp_opts) == -1){
//        printf("conf load error !");
//    }
    if (opts_set_cacrt(global->conn_opts, argv0, crtPath, global_tmp_opts) == -1){
        printf("crt load error !");
    }
    if (opts_set_cakey(global->conn_opts, argv0, keyPath, global_tmp_opts) == -1) {
        printf("key load error !");
    }
    if (global_set_contentlogdir(global, argv0, logsPath) == -1){  // 每一个连接一个日志文件
        printf("logs dir error !");
    }
//    if (global_set_connectlog(global, argv0, logPath) == -1){ // 没一个连接，一行描述
//        printf("log file error !");
//    }
//    if (global_set_certgendir_writeall(global, argv0, crtDir) == -1){ // 网站证书以及伪造证书目录
//        printf("crt file error !");
//    }
//    opts_set_deny_ocsp(global->conn_opts);
    opts_set_passthrough(global->conn_opts);
    opts_unset_divert(global->opts);
    
    global_tmp_opts->split = 1;

//	argc -= optind;
//	argv += optind;
    if (listener_set(&listenerCount, &listenerList, global, global_tmp_opts) == -1) {
        printf("set listener error !");
        exit(EXIT_FAILURE);
    }
//    return 0;
//	if (proxyspec_parse(&argc, &argv, NULL, global, argv0, global_tmp_opts) == -1)
//		exit(EXIT_FAILURE);

	if (!global->spec) { // proxyspec_parse 方法里会指定，链表结构
		fprintf(stderr, "%s: no proxyspec specified.\n", argv0);
		exit(EXIT_FAILURE);
	}
	if (global_has_ssl_spec(global)) {
		if (ssl_init() == -1) {
			fprintf(stderr, "%s: failed to initialize OpenSSL.\n",
			                argv0);
			exit(EXIT_FAILURE);
		}
		// Do not call main_check_opts() for global options: global->opts and global->conn_opts because global options do not have to have SSL options, but proxyspecs do have to,and global options are copied into proxyspecs and then into struct filter rules anyway
        // 不要为全局选项调用main_check_opts(): global->opts和global->conn_opts，因为全局选项不需要有SSL选项，但代理规格必须，和全局选项复制到代理规格，然后进入结构过滤规则
		for (proxyspec_t *spec = global->spec; spec; spec = spec->next) {
			if (spec->ssl || spec->upgrade) {
				// Either the proxyspec itself or all of the filtering rules copied into or defined in the proxyspec must have a complete SSL/TLS configuration
                // 无论是proxyspec本身，还是复制到或定义在proxyspec中的所有过滤规则，都必须具有完整的SSL/TLS配置
				if (main_check_opts(spec->opts, spec->conn_opts, argv0, "ProxySpec") == -1) {
					if (!spec->opts->filter_rules)
						exit(EXIT_FAILURE);

					filter_rule_t *rule = spec->opts->filter_rules;
					while (rule) {
						if (!rule->action.conn_opts || (main_check_opts(spec->opts, rule->action.conn_opts, argv0, "FilterRule") == -1)) {
							fprintf(stderr, "%s: no or incomplete SSL/TLS configuration in ProxySpec and/or FilterRule.\n", argv0);
							exit(EXIT_FAILURE);
						}
						rule = rule->next;
					}
				}
			}
		}
	}
//#ifdef __APPLE__
//	if (global->dropuser && !!strcmp(global->dropuser, "root") &&
//	    nat_used("pf")) {
//		fprintf(stderr, "%s: cannot use 'pf' proxyspec with -u due to Apple bug\n", argv0);
//		exit(EXIT_FAILURE);
//	}
//#endif /* __APPLE__ */

	/* prevent multiple instances running 防止多个实例运行 */
	if (!test_config && global->pidfile) { // 如果有配置pid文件
		pidfd = sys_pidf_open(global->pidfile);
		if (pidfd == -1) {
			fprintf(stderr, "%s: cannot open PID file '%s' - process already running?\n", argv0, global->pidfile);
			exit(EXIT_FAILURE);
		}
	}

	/* dynamic defaults 设置默认值 */
	if (!global->conn_opts->ciphers) {
		global->conn_opts->ciphers = strdup(DFLT_CIPHERS);
		if (!global->conn_opts->ciphers)
			oom_die(argv0);
	}
	if (!global->conn_opts->ciphersuites) {
		global->conn_opts->ciphersuites = strdup(DFLT_CIPHERSUITES);
		if (!global->conn_opts->ciphersuites)
			oom_die(argv0);
	}
	for (proxyspec_t *spec = global->spec; spec; spec = spec->next) {
		if (!spec->conn_opts->ciphers) {
			spec->conn_opts->ciphers = strdup(DFLT_CIPHERS);
			if (!spec->conn_opts->ciphers)
				oom_die(argv0);
		}
		if (!spec->conn_opts->ciphersuites) {
			spec->conn_opts->ciphersuites = strdup(DFLT_CIPHERSUITES);
			if (!spec->conn_opts->ciphersuites)
				oom_die(argv0);
		}

		filter_rule_t *rule = spec->opts->filter_rules;
		while (rule) {
			if (rule->action.conn_opts) {
				if (!rule->action.conn_opts->ciphers) {
					rule->action.conn_opts->ciphers = strdup(DFLT_CIPHERS);
					if (!rule->action.conn_opts->ciphers)
						oom_die(argv0);
				}
				if (!rule->action.conn_opts->ciphersuites) {
					rule->action.conn_opts->ciphersuites = strdup(DFLT_CIPHERSUITES);
					if (!rule->action.conn_opts->ciphersuites)
						oom_die(argv0);
				}
			}
			rule = rule->next;
		}
	}
	
	/* Warn about options that require per-connection privileged operations to be executed through privsep, but only if dropuser is set and is not root, because privsep will fastpath in that situation, skipping the latency-incurring overhead.
       警告那些需要通过privsep执行每个连接特权操作的选项，但只有在设置了dropuser且不是root用户的情况下，因为在这种情况下，privsep将快速执行，跳过导致延迟的开销。
     */
	int privsep_warn = 0;
	
	if (privsep_warn) {
		log_dbg_printf("| Privileged operations require communication "
		               "between parent and child process\n"
		               "| and will negatively impact latency and "
		               "performance on each connection.\n");
	}

	/* debug log, part 1 */
//	if (OPTS_DEBUG(global)) {
//		main_version();
//	}

	/* 生成 leaf key */
	if (global_has_ssl_spec(global) && global_has_cakey_spec(global) && !global->leafkey) {
		global->leafkey = ssl_key_genrsa(global->leafkey_rsabits);
		if (!global->leafkey) {
			fprintf(stderr, "%s: error generating RSA key:\n",
			                argv0);
			ERR_print_errors_fp(stderr);
			exit(EXIT_FAILURE);
		}
		if (OPTS_DEBUG(global)) {
			log_dbg_printf("Generated %i bit RSA key for leaf "
			               "certs.\n", global->leafkey_rsabits);
		}
	}
    // 将key写入文件保存
	if (global->leafkey && global->certgendir) {
		char *keyid, *keyfn;
		int prv;
		FILE *keyf;

		keyid = ssl_key_identifier(global->leafkey, 0);
		if (!keyid) {
			fprintf(stderr, "%s: error generating key id\n", argv0);
			exit(EXIT_FAILURE);
		}

		prv = asprintf(&keyfn, "%s/%s.key", global->certgendir, keyid);
		if (prv == -1) {
			fprintf(stderr, "%s: %s (%i)\n", argv0,
			                strerror(errno), errno);
			exit(EXIT_FAILURE);
		}

		if (!(keyf = fopen(keyfn, "w"))) {
			fprintf(stderr, "%s: Failed to open '%s' for writing: "
			                "%s (%i)\n", argv0, keyfn,
			                strerror(errno), errno);
			exit(EXIT_FAILURE);
		}
		if (!PEM_write_PrivateKey(keyf, global->leafkey, NULL, 0, 0,
		                                           NULL, NULL)) {
			fprintf(stderr, "%s: Failed to write key to '%s': "
			                "%s (%i)\n", argv0, keyfn,
			                strerror(errno), errno);
			exit(EXIT_FAILURE);
		}
		fclose(keyf);
	}

	for (proxyspec_t *spec = global->spec; spec; spec = spec->next) {
		if (spec->opts->filter_rules) {
			spec->opts->filter = filter_set(spec->opts->filter_rules, argv0, global_tmp_opts); // 将规则转换成结构体
			if (!spec->opts->filter)
				oom_die(argv0);
		}
	}

	// We don't need the tmp opts used to clone global opts into proxyspecs and struct filtering rules anymore
    // 我们不再需要tmp选项用于克隆全局选项到代理规范和结构过滤规则
	tmp_opts_free(global_tmp_opts);

	/* debug log, part 2 */
	if (!OPTS_DEBUG(global)) {
		char *s = conn_opts_str(global->conn_opts);
		if (!s)
			oom_die(argv0);

		log_dbg_printf("Global %s\n", s);
		free(s);

		log_dbg_printf("proxyspecs:\n");
		for (proxyspec_t *spec = global->spec; spec; spec = spec->next) {
			char *specstr = proxyspec_str(spec);
			if (!specstr)
				oom_die(argv0);

			log_dbg_printf("- %s\n", specstr);
			free(specstr);
		}
//#ifndef OPENSSL_NO_ENGINE
//		if (global->openssl_engine) {
//			log_dbg_printf("Loaded OpenSSL engine %s\n",
//			               global->openssl_engine);
//		}
//#endif /* !OPENSSL_NO_ENGINE */
		if (global->conn_opts->cacrt) {
			char *subj = ssl_x509_subject(global->conn_opts->cacrt);
			log_dbg_printf("Loaded Global CA: '%s'\n", subj);
			free(subj);
//#ifdef DEBUG_CERTIFICATE
			log_dbg_print_free(ssl_x509_to_str(global->conn_opts->cacrt));
			log_dbg_print_free(ssl_x509_to_pem(global->conn_opts->cacrt));
//#endif /* DEBUG_CERTIFICATE */
		} else {
			log_dbg_printf("No Global CA loaded.\n");
		}
		for (proxyspec_t *spec = global->spec; spec; spec = spec->next) {
			if (spec->conn_opts->cacrt) {
				char *subj = ssl_x509_subject(spec->conn_opts->cacrt);
				log_dbg_printf("Loaded ProxySpec CA: '%s'\n", subj);
				free(subj);
//#ifdef DEBUG_CERTIFICATE
				log_dbg_print_free(ssl_x509_to_str(spec->conn_opts->cacrt));
				log_dbg_print_free(ssl_x509_to_pem(spec->conn_opts->cacrt));
//#endif /* DEBUG_CERTIFICATE */
			} else {
				log_dbg_printf("No ProxySpec CA loaded.\n");
			}

			filter_rule_t *rule = spec->opts->filter_rules;
			while (rule) {
				if (rule->action.conn_opts) {
					if (rule->action.conn_opts->cacrt) {
						char *subj = ssl_x509_subject(rule->action.conn_opts->cacrt);
						log_dbg_printf("Loaded FilterRule CA: '%s'\n", subj);
						free(subj);
//#ifdef DEBUG_CERTIFICATE
						log_dbg_print_free(ssl_x509_to_str(rule->action.conn_opts->cacrt));
						log_dbg_print_free(ssl_x509_to_pem(rule->action.conn_opts->cacrt));
//#endif /* DEBUG_CERTIFICATE */
					} else {
						log_dbg_printf("No FilterRule CA loaded.\n");
					}
				}
				rule = rule->next;
			}
		}
		log_dbg_printf("SSL/TLS leaf certificates taken from:\n");
		if (global->leafcertdir) {
			log_dbg_printf("- Matching PEM file in %s\n",
			               global->leafcertdir);
		}
		if (global->defaultleafcert) {
			log_dbg_printf("- Default leaf key\n");
		// @todo Debug print the cakey and passthrough opts for proxspecs too?
		} else if (global->conn_opts->cakey) {
			log_dbg_printf("- Global generated on the fly\n");
		} else if (global->conn_opts->passthrough) {
			log_dbg_printf("- Global passthrough without decryption\n");
		} else {
			log_dbg_printf("- Global connection drop\n");
		}
	}

	// Free macros and filtering rules in linked lists, not needed anymore
	// We use filter in conn handling, not macros and filter_rules
    // 释放不需要了的资源
	for (proxyspec_t *spec = global->spec; spec; spec = spec->next) {
		filter_macro_free(spec->opts);
		filter_rules_free(spec->opts);
	}
	filter_macro_free(global->opts);
	filter_rules_free(global->opts);

	/*
	 * Initialize as much as possible before daemon() in order to be able to provide direct feedback to the user when failing.
     * 在daemon()之前尽可能地初始化，以便能够在失败时向用户提供直接反馈。
	 */
    // 缓存初始化,缓存可以在libevent和OpenSSL之前或之后初始化。
	if (cachemgr_preinit() == -1) {
		fprintf(stderr, "%s: failed to preinit cachemgr.\n", argv0);
		exit(EXIT_FAILURE);
	}
    // 日志初始化，打开所有日志文件，但不要启动任何线程，因为我们可能会在预先初始化后使用fork()。
	if (log_preinit(global) == -1) {
		fprintf(stderr, "%s: failed to preinit logging.\n", argv0);
		exit(EXIT_FAILURE);
	}
//	if (nat_preinit() == -1) {
//		fprintf(stderr, "%s: failed to preinit NAT lookup.\n", argv0);
//		exit(EXIT_FAILURE);
//	}

	/* 在删除privs之前，cachemgr_preinit()之后加载证书*/
	if (global->leafcertdir) {
		if (sys_dir_eachfile(global->leafcertdir,
		                     main_load_leafcert, global) == -1) {
			fprintf(stderr, "%s: failed to load certs from %s\n",
			                argv0, global->leafcertdir);
			exit(EXIT_FAILURE);
		}
	}

	if (test_config) {
		rv = EXIT_SUCCESS;
		goto out_test_config;
	}

	if (global->pidfile && (sys_pidf_write(pidfd) == -1)) { // 将process ID写入描述符为pidfd的process ID文件里。
		log_err_level_printf(LOG_CRIT, "Failed to write PID to PID file '%s': %s (%i)"
		               "\n", global->pidfile, strerror(errno), errno);
		return -1;
	}

	descriptor_table_size = getdtablesize(); //  获取描述符表的大小

	/* Fork into parent monitor process and (potentially unprivileged) child process doing the actual work.
       We request 6 privsep client sockets: five logger threads, and the child process main thread, which will become the main proxy thread.
       First slot is main thread, remaining slots are passed down to log subsystem.
       Fork到父监视进程子进程，执行实际的工作。我们请求6个privsep client sockets:5个日志线程和1个子进程的主线程，这将成为主代理线程。第一个槽位是主线程，其余槽位向下传递到日志子系统。
     */
    // !!!! 这6个子线程，第一个是监听主线程，后面5个日志记录线程，依次是masterkey_log、connect_log、content_file_log、content_pcap_log、cert_clisock
	int clisock[6];
	if (privsep_fork(global, clisock, sizeof(clisock)/sizeof(clisock[0]), &rv) != 0) {
		/* parent has exited the monitor loop after waiting for child, or an error occurred
           父线程需要等待子线程退出监听循环或者发送错误后才能退出
         */
		if (global->pidfile) {
			sys_pidf_close(pidfd, global->pidfile);
		}
		goto out_parent;
	}
	/* child */

	/* close pidfile in child */
	if (global->pidfile)
		close(pidfd);

    saveTask(taskId, global->init_conn_num, global->init_out_bytes, global->init_in_bytes, current_time(), 0);
	/* Initialize proxy before dropping privs */
    global_proxy = proxy_new(global, clisock[0]);
	
	if (ssl_reinit() == -1) { // fork之后重新初始化openssl
		fprintf(stderr, "%s: failed to reinit SSL\n", argv0);
		goto out_sslreinit_failed;
	}

	/* Post-privdrop/chroot/detach initialization, thread spawning */
	if (log_init(global, global_proxy, &clisock[1]) == -1) {
		fprintf(stderr, "%s: failed to init log facility: %s\n",
		                argv0, strerror(errno));
		goto out_log_failed;
	}
	if (cachemgr_init() == -1) {
		log_err_level_printf(LOG_CRIT, "Failed to init cache manager.\n");
		goto out_cachemgr_failed;
	}
    fprintf(stderr, "%s: 开启事件循环 \n",argv0);
	int proxy_rv = proxy_run(global_proxy);
    fprintf(stderr, "%s: 结束事件循环 \n",argv0);
	if (proxy_rv == 0) {
		rv = EXIT_SUCCESS;
	} else if (proxy_rv > 0) {
		/*
		 * We terminated because of receiving a signal.  For our normal termination signals as documented in the man page, we want to return with EXIT_SUCCESS.  For other signals, which should be considered abnormal terminations, we want to return an exit status of 128 + signal number.
           我们因收到信号而终止。对于手册页中记录的正常终止信号，我们希望返回EXIT_SUCCESS。对于其他应该被认为是异常终止的信号，我们希望返回一个128 +信号号的退出状态
         */
		if (proxy_rv == SIGTERM || proxy_rv == SIGINT) {
			rv = EXIT_SUCCESS;
		} else {
			rv = 128 + proxy_rv;
		}
	}

	log_finest_main_va("EXIT closing privsep clisock=%d", clisock[0]);
	privsep_client_close(clisock[0]);
	proxy_free(global_proxy);
    global_proxy = NULL;
//	nat_fini();
out_nat_failed:
	cachemgr_fini();
out_cachemgr_failed:
	log_fini();
out_sslreinit_failed:
out_log_failed:
out_parent:
out_test_config:
	global_free(global);
	ssl_fini();
    // 重启
    if (need_reopen == 1) {
        need_reopen = 0;
        printf("重启 \n");
        return man_run(reopen_listener_count, reopen_listener_list, crtPath, keyPath, logsPath, rulePath, taskId);
    }else{
        reopen_listener_count = 0;
        reopen_conn_count = 0;
    }
	return rv;
}

int man_stop(void){
    if (global_proxy == NULL) {
        printf("man 未运行 ！\n");
    }else{
        proxy_loopbreak(global_proxy, 0);
    }
    return 0;
}

int man_reopen(int listenerCount, char *listenerList[]){
    need_reopen = 1;
    reopen_listener_count = listenerCount;
    for (int i = 0; i < listenerCount ; i++) {
        reopen_listener_list[i] = listenerList[i];
    }
    man_stop();
    return 0;
}

int fortest(char *hostname){
    printf("---------- host:%s ----------\n",hostname);
    struct addrinfo hints;
    struct addrinfo *res, *tmp;
    char host[256];

    memset(&hints, 0, sizeof(struct addrinfo));
    hints.ai_family = AF_INET;

    int ret = getaddrinfo(hostname, NULL, &hints, &res);
    if (ret != 0) {
        fprintf(stderr, "getaddrinfo: %s\n", gai_strerror(ret));
        return 0;
    }
    for (tmp = res; tmp != NULL; tmp = tmp->ai_next) {
        getnameinfo(tmp->ai_addr, tmp->ai_addrlen, host, sizeof(host), NULL, 0, NI_NUMERICHOST);
        puts(host);
    }
    freeaddrinfo(res);
    return 0;
}

int testGetaddrinfo(void){
    // 解析IP地址返回IP地址，如果带上端口号，则会失败
    fortest("www.cnblogs.com");
    fortest("101.35.212.35");
    fortest("www.baidu.com");
    fortest("192.168.199.1");
    fortest("localhost");
    fortest("127.0.0.1:80");
    return 0;
}

/* vim: set noet ft=c: */
