/*-
 连接配置:conn_opts_t
 传输配置(转发、过滤):opts_t
 代理规则:proxyspec_t
 全局配置:global
 */

#ifndef OPTS_H
#define OPTS_H

#include "proc.h"
//#include "nat.h"
#include "ssl.h"
#include "cert.h"
#include "attrib.h"

//#ifndef WITHOUT_USERAUTH
//#include <sys/types.h>
//#include <sys/socket.h>
//#include <sqlite3.h>
//#endif /* !WITHOUT_USERAUTH */

//#define DEBUG_OPTS 
//#define DEBUG_PROXY
/*
 * Print helper for logging code.
 */
#define STRORDASH(x)	(((x)&&*(x))?(x):"-")
#define STRORNONE(x)	(((x)&&*(x))?(x):"")
#define NLORNONE(x)		(((x)&&*(x))?"\n":"")

#define FILTER_ACTION_NONE   0x00000000U
#define FILTER_ACTION_MATCH  0x00000200U
#define FILTER_ACTION_DIVERT 0x00000400U
#define FILTER_ACTION_SPLIT  0x00000800U
#define FILTER_ACTION_PASS   0x00001000U
#define FILTER_ACTION_BLOCK  0x00002000U

#define FILTER_LOG_CONNECT   0x00004000U
#define FILTER_LOG_MASTER    0x00008000U
#define FILTER_LOG_CERT      0x00010000U
#define FILTER_LOG_CONTENT   0x00020000U
#define FILTER_LOG_PCAP      0x00040000U
#define FILTER_LOG_MIRROR    0x00080000U

#define FILTER_LOG_NOCONNECT 0x00100000U
#define FILTER_LOG_NOMASTER  0x00200000U
#define FILTER_LOG_NOCERT    0x00400000U
#define FILTER_LOG_NOCONTENT 0x00800000U
#define FILTER_LOG_NOPCAP    0x01000000U
#define FILTER_LOG_NOMIRROR  0x02000000U

#define FILTER_PRECEDENCE    0x000000FFU

typedef struct global global_t;
// 连接配置
typedef struct conn_opts {
	unsigned int sslcomp : 1;
#ifdef HAVE_SSLV2
	unsigned int no_ssl2 : 1;
#endif /* HAVE_SSLV2 */
#ifdef HAVE_SSLV3
	unsigned int no_ssl3 : 1;
#endif /* HAVE_SSLV3 */
#ifdef HAVE_TLSV10
	unsigned int no_tls10 : 1;
#endif /* HAVE_TLSV10 */
#ifdef HAVE_TLSV11
	unsigned int no_tls11 : 1;
#endif /* HAVE_TLSV11 */
#ifdef HAVE_TLSV12
	unsigned int no_tls12 : 1;
#endif /* HAVE_TLSV12 */
#ifdef HAVE_TLSV13
	unsigned int no_tls13 : 1;
#endif /* HAVE_TLSV13 */
	unsigned int passthrough : 1; // 穿透，如果没有或者证书校验失败，则直接穿透 , 0:不穿透
	unsigned int deny_ocsp : 1;   // 阻止ocsp
	char *ciphers;
	char *ciphersuites;
	CONST_SSL_METHOD *(*sslmethod)(void);
#if (OPENSSL_VERSION_NUMBER >= 0x10100000L && !defined(LIBRESSL_VERSION_NUMBER)) || (defined(LIBRESSL_VERSION_NUMBER) && LIBRESSL_VERSION_NUMBER >= 0x20702000L)
	int sslversion;
	int minsslversion;
	int maxsslversion;
#endif /* OPENSSL_VERSION_NUMBER >= 0x10100000L */
	X509 *cacrt;
	EVP_PKEY *cakey;
	STACK_OF(X509) *chain;
	X509 *clientcrt;
	EVP_PKEY *clientkey;
#ifndef OPENSSL_NO_DH
	DH *dh;
#endif /* !OPENSSL_NO_DH */
#ifndef OPENSSL_NO_ECDH
	char *ecdhcurve;
#endif /* !OPENSSL_NO_ECDH */
	char *leafcrlurl;
	unsigned int remove_http_accept_encoding: 1;
	unsigned int remove_http_referer: 1;
	unsigned int verify_peer: 1;
	unsigned int allow_wrong_host: 1;
	unsigned int validate_proto : 1;
	// Used with struct filtering rules only
	unsigned int reconnect_ssl : 1;
	unsigned int max_http_header_size;
} conn_opts_t;
// 传输配置：转发、过滤
typedef struct opts {
	// Set to 1 to divert to lp, set to 0 for split mode
	// Defaults to 1
	unsigned int divert : 1; // 如果为0，则不转发

	// Used to store macros and filter rules and to create the filter
	// Freed during startup after the filter is created and debug printed
    // 用于存储宏和筛选规则，并创建筛选器
    // 在过滤器创建和调试打印之后，在启动过程中释放
	struct macro *macro;
	struct filter_rule *filter_rules;

	struct filter *filter;
	global_t *global;
} opts_t;
// 代理规则
typedef struct proxyspec {
	unsigned int ssl : 1;
	unsigned int http : 1;
	unsigned int upgrade: 1;
	unsigned int pop3 : 1;
	unsigned int smtp : 1;
	unsigned int dns : 1;		/* set if spec needs DNS lookups */
	struct sockaddr_storage listen_addr;
	socklen_t listen_addrlen;
	/* connect_addr and connect_addrlen are set: static mode;
	 * natlookup is set: NAT mode; natsocket /may/ be set too;
	 * sni_port is set, in which case we use SNI lookups */
	struct sockaddr_storage connect_addr;
	socklen_t connect_addrlen;
	unsigned short sni_port;
	char *natengine;
//	nat_lookup_cb_t natlookup;//  TODO:移这两个参数，看看哪里会报错
//	nat_socket_cb_t natsocket;
	struct proxyspec *next;

	struct sockaddr_storage divert_addr;
	socklen_t divert_addrlen;

	struct sockaddr_storage return_addr;
	socklen_t return_addrlen;

	// Each proxyspec has its own opts
	opts_t *opts;
	conn_opts_t *conn_opts;
} proxyspec_t;//  代理规则

// Temporary options
// conn_opts strings used while cloning into proxyspec or struct filter rule opts
typedef struct tmp_opts {
	char *cacrt_str;
	char *cakey_str;
	char *chain_str;
	char *clientcrt_str;
	char *clientkey_str;
	char *leafcrlurl_str;
	char *dh_str;
	// Global split mode set by the -n option
	// Overrides the divert options of all proxyspecs
	// Not equivalent to the conf file Divert option
	unsigned int split : 1;
	// Prevents Include option in include files
	unsigned int include : 1;
#ifdef DEBUG_PROXY
	unsigned int line_num;
#endif /* DEBUG_PROXY */
} tmp_opts_t;

struct global {
    
    char *task_id;
    long long unsigned int init_conn_num;
    long long unsigned int init_in_bytes;
    long long unsigned int init_out_bytes;
    
	unsigned int debug : 1;
	unsigned int detach : 1;
	unsigned int contentlog_isdir : 1;
	unsigned int contentlog_isspec : 1;
	unsigned int pcaplog_isdir : 1;
	unsigned int pcaplog_isspec : 1;
#ifdef HAVE_LOCAL_PROCINFO
	unsigned int lprocinfo : 1;
#endif /* HAVE_LOCAL_PROCINFO */
	unsigned int certgen_writeall : 1;
	char *certgendir;
	char *leafcertdir;
	char *dropuser;
	char *dropgroup;
	char *jaildir;
	char *pidfile;
	char *conffile;
	char *connectlog;
	char *contentlog;
	char *contentlog_basedir; /* static part of logspec for privsep srv */
	char *masterkeylog;
	char *pcaplog;
	char *pcaplog_basedir; /* static part of pcap logspec for privsep srv */
	unsigned int conn_idle_timeout;
	unsigned int expired_conn_check_period;
	unsigned int stats_period;
	unsigned int statslog: 1;
	unsigned int log_stats: 1;

	conn_opts_t *conn_opts;
	proxyspec_t *spec;
	opts_t *opts;

	// @todo Modify cert cache to move the key field to opts struct
	// Otherwise, cache HIT fetches certs forged using different leaf cert keys, which fails loading src server keys
    // We must use the same key while forging and reusing certs
	EVP_PKEY *leafkey;
	cert_t *defaultleafcert;
	int leafkey_rsabits;

#ifndef OPENSSL_NO_ENGINE
	// @todo Use different openssl engines for each proxyspec, so move to opts?
	char *openssl_engine;
#endif /* !OPENSSL_NO_ENGINE */
};
// oom  = out of menmory
int oom_return(const char *) WUNRES;
void *oom_return_null(const char *) WUNRES;
int oom_return_na(void) WUNRES;
void *oom_return_na_null(void) WUNRES;

cert_t *opts_load_cert_chain_key(const char *) NONNULL(1);

void opts_unset_divert(opts_t *) NONNULL(1);

void proxyspec_free(proxyspec_t *);
proxyspec_t *proxyspec_new(global_t *, const char *, tmp_opts_t *) MALLOC;
int proxyspec_set_proto(proxyspec_t *, const char *) NONNULL(1,2) WUNRES;
int proxyspec_parse(int *, char **[], const char *, global_t *, const char *, tmp_opts_t *) WUNRES;
int listener_set(int *count, char **list[], global_t *global, tmp_opts_t *tmp_opts) WUNRES;

char *conn_opts_str(conn_opts_t *);
char *proxyspec_str(proxyspec_t *) NONNULL(1) MALLOC;

conn_opts_t *conn_opts_new(void) MALLOC;
opts_t *opts_new(void) MALLOC;
void opts_free(opts_t *) NONNULL(1);
void conn_opts_free(conn_opts_t *);
tmp_opts_t *tmp_opts_copy(tmp_opts_t *) NONNULL(1) MALLOC;
conn_opts_t *conn_opts_copy(conn_opts_t *, const char *, tmp_opts_t *) WUNRES;
int opts_set_cacrt(conn_opts_t *, const char *, const char *, tmp_opts_t *) NONNULL(1,2,3) WUNRES;
int opts_set_cakey(conn_opts_t *, const char *, const char *, tmp_opts_t *) NONNULL(1,2,3) WUNRES;
int opts_set_chain(conn_opts_t *, const char *, const char *, tmp_opts_t *) NONNULL(1,2,3) WUNRES;
int opts_set_leafcrlurl(conn_opts_t *, const char *, const char *, tmp_opts_t *) NONNULL(1,2,3) WUNRES;
void opts_set_deny_ocsp(conn_opts_t *) NONNULL(1);
void opts_set_passthrough(conn_opts_t *) NONNULL(1);
int opts_set_clientcrt(conn_opts_t *, const char *, const char *, tmp_opts_t *) NONNULL(1,2,3) WUNRES;
int opts_set_clientkey(conn_opts_t *, const char *, const char *, tmp_opts_t *) NONNULL(1,2,3) WUNRES;
#ifndef OPENSSL_NO_DH
int opts_set_dh(conn_opts_t *, const char *, const char *, tmp_opts_t *) NONNULL(1,2,3) WUNRES;
#endif /* !OPENSSL_NO_DH */
#ifndef OPENSSL_NO_ECDH
int opts_set_ecdhcurve(conn_opts_t *, const char *, const char *) NONNULL(1,2,3) WUNRES;
#endif /* !OPENSSL_NO_ECDH */
void opts_unset_sslcomp(conn_opts_t *) NONNULL(1);
int opts_force_proto(conn_opts_t *, const char *, const char *) NONNULL(1,2,3) WUNRES;
int opts_disable_enable_proto(conn_opts_t *, const char *, const char *, int) NONNULL(1,2,3) WUNRES;
int opts_set_ciphers(conn_opts_t *, const char *, const char *) NONNULL(1,2,3) WUNRES;
int opts_set_ciphersuites(conn_opts_t *, const char *, const char *) NONNULL(1,2,3) WUNRES;

int set_conn_opts_option(conn_opts_t *, const char *, const char *, char *, unsigned int, tmp_opts_t *);
int load_proxyspec_struct(global_t *, const char *, char **, unsigned int *, FILE *, tmp_opts_t *) WUNRES;

#define OPTS_DEBUG(global) unlikely((global)->debug)

global_t * global_new(void) MALLOC;
void tmp_opts_free(tmp_opts_t *) NONNULL(1);
void global_free(global_t *) NONNULL(1);
int global_has_ssl_spec(global_t *) NONNULL(1) WUNRES;
int global_has_dns_spec(global_t *) NONNULL(1) WUNRES;
int global_has_userauth_spec(global_t *) NONNULL(1) WUNRES;
int global_has_cakey_spec(global_t *) NONNULL(1) WUNRES;
int global_set_user(global_t *, const char *, const char *) NONNULL(1,2,3) WUNRES;
int global_set_group(global_t *, const char *, const char *) NONNULL(1,2,3) WUNRES;
int global_set_jaildir(global_t *, const char *, const char *) NONNULL(1,2,3) WUNRES;
int global_set_pidfile(global_t *, const char *, const char *) NONNULL(1,2,3) WUNRES;
int global_set_connectlog(global_t *, const char *, const char *) NONNULL(1,2,3) WUNRES;
int global_set_contentlog(global_t *, const char *, const char *) NONNULL(1,2,3) WUNRES;
int global_set_contentlogdir(global_t *, const char *, const char *) NONNULL(1,2,3) WUNRES;
int global_set_contentlogpathspec(global_t *, const char *, const char *) NONNULL(1,2,3) WUNRES;
#ifdef HAVE_LOCAL_PROCINFO
void global_set_lprocinfo(global_t *) NONNULL(1);
#endif /* HAVE_LOCAL_PROCINFO */
int global_set_masterkeylog(global_t *, const char *, const char *) NONNULL(1,2,3) WUNRES;
int global_set_pcaplog(global_t *, const char *, const char *) NONNULL(1,2,3) WUNRES;
int global_set_pcaplogdir(global_t *, const char *, const char *) NONNULL(1,2,3) WUNRES;
int global_set_pcaplogpathspec(global_t *, const char *, const char *) NONNULL(1,2,3) WUNRES;
void global_set_daemon(global_t *) NONNULL(1);
void global_set_debug(global_t *) NONNULL(1);
int global_set_debug_level(const char *) NONNULL(1) WUNRES;
void global_set_statslog(global_t *) NONNULL(1);

int is_yesno(const char *) WUNRES;
int check_value_yesno(const char *, const char *, unsigned int) WUNRES;
int get_name_value(char *, char **, const char, unsigned int) WUNRES;
int global_set_option(global_t *, const char *, const char *, char **, tmp_opts_t *) NONNULL(1,2,3,5) WUNRES;
int global_set_leafkey(global_t *, const char *, const char *) NONNULL(1,2,3) WUNRES;
int global_set_leafcertdir(global_t *, const char *, const char *) NONNULL(1,2,3) WUNRES;
int global_set_defaultleafcert(global_t *, const char *, const char *) NONNULL(1,2,3) WUNRES;
int global_set_certgendir_writeall(global_t *, const char *, const char *) NONNULL(1,2,3) WUNRES;
int global_set_certgendir_writegencerts(global_t *, const char *, const char *) NONNULL(1,2,3) WUNRES;
int global_set_openssl_engine(global_t *, const char *, const char *) NONNULL(1,2,3) WUNRES;
int global_load_conffile(global_t *, const char *, const char *, char **, tmp_opts_t *) NONNULL(1,2,4) WUNRES;
#endif /* !OPTS_H */

/* vim: set noet ft=c: */
