/*-
 */

#include "pxythrmgr.h"

#include "sys.h"
#include "log.h"
#include "pxyconn.h"

#include <string.h>
#include <event2/bufferevent.h>

/*
 * Proxy thread manager: manages the connection handling worker threads
 * and the per-thread resources (i.e. event bases).  The load is shared
 * across num_cpu * 2 connection handling threads, using the number of
 * currently assigned connections as the sole metric.
 */

/*
 * Create new thread manager but do not start any threads yet.
 * This gets called before forking to background.
   创建新的线程管理器，但尚未启动任何线程。这个在fork到后台之前被调用。
 */
pxy_thrmgr_ctx_t *
pxy_thrmgr_new(global_t *global)
{
	pxy_thrmgr_ctx_t *ctx;

	if (!(ctx = malloc(sizeof(pxy_thrmgr_ctx_t))))
		return NULL;
	memset(ctx, 0, sizeof(pxy_thrmgr_ctx_t));

	ctx->global = global;
	ctx->num_thr = /*2 * */sys_get_cpu_cores();
    ctx->conn_count = global->init_conn_num;
    ctx->all_in_bytes = global->init_in_bytes;
    ctx->all_out_bytes = global->init_out_bytes;
	return ctx;
}

/*
 * Start the thread manager and associated threads.
 * This must be called after forking.
 *
 * Returns -1 on failure, 0 on success.
 */
int
pxy_thrmgr_run(pxy_thrmgr_ctx_t *ctx)
{
	int i = -1, dns = 0;

	dns = global_has_dns_spec(ctx->global);

	if (!(ctx->thr = malloc(ctx->num_thr * sizeof(pxy_thr_ctx_t*)))) {
		log_dbg_printf("Failed to allocate memory\n");
		goto leave;
	}
	memset(ctx->thr, 0, ctx->num_thr * sizeof(pxy_thr_ctx_t*));

	for (i = 0; i < ctx->num_thr; i++) {
		if (!(ctx->thr[i] = malloc(sizeof(pxy_thr_ctx_t)))) {
			log_dbg_printf("Failed to allocate memory\n");
			goto leave;
		}
		memset(ctx->thr[i], 0, sizeof(pxy_thr_ctx_t));
		ctx->thr[i]->evbase = event_base_new();
		if (!ctx->thr[i]->evbase) {
			log_dbg_printf("Failed to create evbase %d\n", i);
			goto leave;
		}
//		if (dns) {
			/* only create dns base if we actually need it later */
			ctx->thr[i]->dnsbase = evdns_base_new(ctx->thr[i]->evbase, 0);
            // 必须设置，因为iOS无法读取系统的dns解析地址
            evdns_base_nameserver_ip_add(ctx->thr[i]->dnsbase, "8.8.8.8");
            evdns_base_nameserver_ip_add(ctx->thr[i]->dnsbase, "114.114.114.114");
			if (!ctx->thr[i]->dnsbase) {
				log_dbg_printf("Failed to create dnsbase %d\n", i);
				goto leave;
			}
//		}
        /*
         struct evdns_base *evbase = evdns_base_new(ctx->thr[i]->evbase, 1);
         evdns_base_nameserver_ip_add(evbase, "8.8.8.8");
         ctx->thr[i]->dnsbase = evbase;
         */
		ctx->thr[i]->load = 0;
		ctx->thr[i]->running = 0;
		ctx->thr[i]->conns = NULL;
		ctx->thr[i]->id = i;
		ctx->thr[i]->timeout_count = 0;
		ctx->thr[i]->thrmgr = ctx;

//#ifndef WITHOUT_USERAUTH
//		if ((ctx->global->conn_opts->user_auth || global_has_userauth_spec(ctx->global)) &&
//				sqlite3_prepare_v2(ctx->global->userdb, "SELECT user,ether,atime,desc FROM users WHERE ip = ?1", 100, &ctx->thr[i]->get_user, NULL)) {
//			log_err_level_printf(LOG_CRIT, "Error preparing get_user sql stmt: %s\n", sqlite3_errmsg(ctx->global->userdb));
//			goto leave;
//		}
//#endif /* !WITHOUT_USERAUTH */
	}

	log_dbg_printf("Initialized %d connection handling threads\n", ctx->num_thr);

	for (i = 0; i < ctx->num_thr; i++) {
		if (pthread_create(&ctx->thr[i]->thr, NULL, pxy_thr, ctx->thr[i]))
			goto leave_thr;
		while (!ctx->thr[i]->running) {
			sched_yield();
		}
	}

	log_dbg_printf("Started %d connection handling threads\n", ctx->num_thr);
	return 0;

leave_thr:
	i--;
	while (i >= 0) {
		pthread_cancel(ctx->thr[i]->thr);
		pthread_join(ctx->thr[i]->thr, NULL);
		i--;
	}
	i = ctx->num_thr - 1;

leave:
	while (i >= 0) {
		if (ctx->thr[i]) {
			if (ctx->thr[i]->dnsbase) {
				evdns_base_free(ctx->thr[i]->dnsbase, 0);
			}
			if (ctx->thr[i]->evbase) {
				event_base_free(ctx->thr[i]->evbase);
			}
//#ifndef WITHOUT_USERAUTH
//			if (ctx->global->userdb) {
//				// sqlite3.h: "Invoking sqlite3_finalize() on a NULL pointer is a harmless no-op."
//				sqlite3_finalize(ctx->thr[i]->get_user);
//			}
//#endif /* !WITHOUT_USERAUTH */
			free(ctx->thr[i]);
		}
		i--;
	}
	if (ctx->thr) {
		free(ctx->thr);
		ctx->thr = NULL;
	}
	return -1;
}

/*
 * Destroy the event manager and stop all threads.
 */
void
pxy_thrmgr_free(pxy_thrmgr_ctx_t *ctx)
{
	if (ctx->thr) {
		for (int i = 0; i < ctx->num_thr; i++) {
			event_base_loopbreak(ctx->thr[i]->evbase);
			sched_yield();
		}
		for (int i = 0; i < ctx->num_thr; i++) {
			pthread_join(ctx->thr[i]->thr, NULL);
		}
		for (int i = 0; i < ctx->num_thr; i++) {
			if (ctx->thr[i]->dnsbase) {
				evdns_base_free(ctx->thr[i]->dnsbase, 0);
			}
			if (ctx->thr[i]->evbase) {
				event_base_free(ctx->thr[i]->evbase);
			}
//#ifndef WITHOUT_USERAUTH
//			if (ctx->global->userdb) {
//				// sqlite3.h: "Invoking sqlite3_finalize() on a NULL pointer is a harmless no-op."
//				sqlite3_finalize(ctx->thr[i]->get_user);
//			}
//#endif /* !WITHOUT_USERAUTH */
			free(ctx->thr[i]);
		}
		free(ctx->thr);
	}
	free(ctx);
}

/*
 * Assign a new connection to a thread.  Chooses the thread with the fewest currently active connections, returns the appropriate event bases.
 给线程分配一个新连接。选择当前活动连接最少的线程，返回相应的事件基础。
 * No need to be so accurate about balancing thread loads,so does not use mutexes, thread or thrmgr level.
 不需要如此精确地平衡线程负载，所以不使用互斥体，线程或thrmgr级别。
 * @todo Check if read accesses to thr load can cause any multithreading issues.
 * Returns the index of the chosen thread.
 * This function cannot fail.
 */
void
pxy_thrmgr_assign_thr(pxy_conn_ctx_t *ctx)
{
	log_finest("ENTER");

	pxy_thrmgr_ctx_t *tmctx = ctx->thrmgr;
	size_t minload = tmctx->thr[0]->load;

#ifdef DEBUG_THREAD
	log_dbg_printf("===> Proxy connection handler thread status:\nthr[0]: %zu\n", minload);
#endif /* DEBUG_THREAD */

	int thrid = 0;
	for (int i = 1; i < tmctx->num_thr; i++) {
		size_t thrload = tmctx->thr[i]->load;
		if (minload > thrload) {
			minload = thrload;
			thrid = i;
		}

#ifdef DEBUG_THREAD
		log_dbg_printf("thr[%d]: %zu\n", i, thrload);
#endif /* DEBUG_THREAD */
	}

	ctx->thr = tmctx->thr[thrid];

#ifdef DEBUG_THREAD
	log_dbg_printf("thrid: %d\n", thrid);
#endif /* DEBUG_THREAD */
}

/* vim: set noet ft=c: */
