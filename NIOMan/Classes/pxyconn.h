/*-
 */

#ifndef PXYCONN_H
#define PXYCONN_H

#if defined(__FreeBSD__) || defined(__DragonFly__)
#include <netinet/in.h>
#endif

#include "proxy.h"
#include "opts.h"
#include "filter.h"
#include "attrib.h"
#include "pxythrmgr.h"
#include "log.h"

#include <sys/types.h>
#include <sys/socket.h>

#include <event2/buffer.h>
#include <event2/bufferevent.h>

#define WANT_CONNECT_LOG(ctx)	((ctx)->global->connectlog||!(ctx)->global->detach||(ctx)->global->statslog)
#define WANT_CONTENT_LOG(ctx)	((ctx)->global->contentlog&&((ctx)->proto!=PROTO_PASSTHROUGH))

#define SSLPROXY_KEY		"SSLproxy:"
#define SSLPROXY_KEY_LEN	strlen(SSLPROXY_KEY)

//#ifndef WITHOUT_USERAUTH
//#define USERAUTH_MSG		"You must authenticate to access the Internet at %s\r\n"
//#endif /* !WITHOUT_USERAUTH */

#define PROTOERROR_MSG		"Connection is terminated due to protocol error\r\n"
#define PROTOERROR_MSG_LEN	strlen(PROTOERROR_MSG)

typedef struct pxy_conn_child_ctx pxy_conn_child_ctx_t;

typedef void (*init_conn_func_t)(evutil_socket_t,  short, void *);
typedef int (*connect_func_t)(pxy_conn_ctx_t *);

typedef void (*callback_func_t)(struct bufferevent *, void *);
typedef void (*eventcb_func_t)(struct bufferevent *, short, void *);

typedef void (*bev_free_func_t)(struct bufferevent *, pxy_conn_ctx_t *);

typedef void (*proto_free_func_t)(pxy_conn_ctx_t *);
typedef int (*proto_validate_func_t)(pxy_conn_ctx_t *, char *, size_t);
//#ifndef WITHOUT_USERAUTH
//typedef void (*proto_classify_user_func_t)(pxy_conn_ctx_t *);
//#endif /* !WITHOUT_USERAUTH */

typedef void (*child_connect_func_t)(pxy_conn_child_ctx_t *);
typedef void (*child_proto_free_func_t)(pxy_conn_child_ctx_t *);

typedef filter_action_t * (*proto_filter_func_t)(pxy_conn_ctx_t *, filter_list_t *);

/*
 * Proxy connection context state, describes a proxy connection
 * with source and destination socket bufferevents, SSL context and
 * other session state.  One of these exists per handled proxy
 * connection.
 */

/* single socket bufferevent descriptor */
typedef struct pxy_conn_desc {
	struct bufferevent *bev;
	SSL *ssl;
	unsigned int closed : 1;
	bev_free_func_t zfree;
    struct evbuffer* first_packet_buf; // 首个包
} pxy_conn_desc_t;

enum conn_type {
	CONN_TYPE_PARENT = 0,
	CONN_TYPE_CHILD,
};

typedef enum protocol {
	PROTO_ERROR = -1,
	PROTO_PASSTHROUGH = 0,
	PROTO_HTTP,
	PROTO_HTTPS,
	PROTO_POP3,
	PROTO_POP3S,
	PROTO_SMTP,
	PROTO_SMTPS,
	PROTO_AUTOSSL,
	PROTO_TCP,
	PROTO_SSL,
} protocol_t;

typedef struct ssl_ctx ssl_ctx_t;

typedef struct proto_ctx proto_ctx_t;
typedef struct proto_child_ctx proto_child_ctx_t;

struct ssl_ctx {
	/* log strings related to SSL */
	char *ssl_names;
	char *origcrtfpr;
	char *usedcrtfpr;

	/* ssl */
	unsigned int sni_peek_retries : 6;       /* max 64 SNI parse retries */
	unsigned int immutable_cert : 1;  /* 1 if the cert cannot be changed */
	unsigned int generated_cert : 1;     /* 1 if we generated a new cert */
	unsigned int have_sslerr : 1;           /* 1 if we have an ssl error */
	// Set after reconnecting srvdst to enforce the SSL options in matching struct filtering rule
	unsigned int reconnected : 1;     /* 1 if we have reconnected srvdst */

	/* server name indicated by client in SNI TLS extension */
	char *sni;

	X509 *origcrt;

	char *srvdst_ssl_version;
	char *srvdst_ssl_cipher;
};

struct proto_ctx {
	protocol_t proto;

	connect_func_t connectcb;
	init_conn_func_t init_conn;

	callback_func_t bev_readcb;
	callback_func_t bev_writecb;
	eventcb_func_t bev_eventcb;

	proto_free_func_t proto_free;
	proto_validate_func_t validatecb;
	unsigned int is_valid : 1;        /* 0 until passed proto validation */

//#ifndef WITHOUT_USERAUTH
//	// We should not (re-)engage passthrough mode for certain protocols,
//	// hence the need for this callback
//	proto_classify_user_func_t classify_usercb;
//#endif /* !WITHOUT_USERAUTH */

	// For protocol specific fields, if any
	void *arg;
};

struct proto_child_ctx {
	protocol_t proto;

	child_connect_func_t connectcb;

	callback_func_t bev_readcb;
	callback_func_t bev_writecb;
	eventcb_func_t bev_eventcb;

	child_proto_free_func_t proto_free;

	// For protocol specific fields, if any
	void *arg;
};

#ifdef HAVE_LOCAL_PROCINFO
/* local process data - filled in iff pid != -1 */
typedef struct pxy_conn_lproc_desc {
	struct sockaddr_storage srcaddr;
	socklen_t srcaddrlen;

	pid_t pid;
	uid_t uid;
	gid_t gid;

	/* derived log strings */
	char *exec_path;
	char *user;
	char *group;
} pxy_conn_lproc_desc_t;
#endif /* HAVE_LOCAL_PROCINFO */

/* parent connection state consisting of three connection descriptors,connection-wide state and the specs and options */
//父连接状态由三个连接描述符、连接范围的状态以及规范和选项组成
struct pxy_conn_ctx { // 单个代理连接管理结构
	enum conn_type type;
    int attached;  // 初始为0，加入线程后为1
    int dnsed;  // 初始为0，dns解析后为1
    char *task_id; // 当前任务id  20220313133000
	long long unsigned int id; // 当前任务序号，自增，唯一
    /* 这些参数应该放在 http的结构体里
     char *req_body_path; // 20220313133000/0.req
     char *rsp_body_path; // 20220313133000/0.rsp
     char *crt_path; //
     char *req_head;
     char *rsp_head;
     char *uri;
     ...
     */
    /* log strings from socket */
    char *srchost_str;  //  来源host
    char *srcport_str;  //  来源port
    char *dsthost_str;  //  目的地host
    char *dstport_str;  //  目的地port
    protocol_t proto;   // http\https\...
    
    // 最后一次读写时间，用于检查是否过期
    time_t atime;
    // 开始时间
    time_t ctime;
    
    // 需要记录的字段
    // 时间过程 下面时间精确到毫秒
    double time_s;       // 开始时间 proxy_conn_ctx_new
    double dns_time_s;   // *dns开始时间 http:pre_bev_proto_match  https:protossl_fd_readcb   https的dns在排队结束之后
    /*
     DNS时间
     */
    double dns_time_e;   // dns结束时间 http:prototcp_init_conn   https:protossl_sni_resolve_cb
    double connect_s;    // *开始连接到dst pxy_conn_connect
    /*
     建立连接时间
     */
    double connect_e;    // 成功连接到dst http:prototcp_bev_eventcb_connected_dst   https:protossl_bev_eventcb_connected_dst  https包括了ssl握手时间
    double send_s;       // *开始发送数据 protohttp_bev_readcb_src
    /*
     发送时间
     */
    double send_e;       // *数据发送完毕 prototcp_bev_eventcb_eof_src
    /*
     等待响应时间
     */
    double receive_s;    // *开始接收数据 protohttp_bev_readcb_dst
    /*
     接收响应时间
     */
    double receive_e;    // *接受完毕 prototcp_bev_eventcb_eof_dst
    double time_c;        // 双向关闭时间
    // 资源
//    char *crt_path; // 网站证书路径
    // 额外信息
    void *extra_info; // conn_http_info 或者其他
    //
    long long unsigned int in_bytes; // 接收数据量
    long long unsigned int out_bytes;// 发送数据量

	pxy_conn_ctx_t *conn;                 /* parent's conn ctx is itself */
	/* per-connection state */
    struct pxy_conn_desc pre; // 客户端与man连接的bufferevent，用于协议判断与dns解析，之后可以赋值给src
	struct pxy_conn_desc src; // 客户端与sslsplit连接的bufferevent描述符
	struct pxy_conn_desc dst; // sslsplit与后端服务器连接的bufferevent描述符

	/* store fd and fd event while connected is 0 */
	evutil_socket_t fd;

	// 协议对应的事件处理方法
	proto_ctx_t *protoctx;
	// ssl相关参数
	ssl_ctx_t *sslctx;
	/* content 日志相关 */
	log_content_ctx_t logctx;

	/* 状态 */
	unsigned int connected : 1;       /* 0 until both ends are connected */
	unsigned int enomem : 1;                       /* 1 if out of memory 内存不足 */
	unsigned int term : 1;                     /* 0 until term requested */
	unsigned int term_requestor : 1;          /* 1 client, 0 server side */

	unsigned int srvdst_xferred : 1;     /* 1 if srvdst xferred to child */
	struct pxy_conn_desc srvdst; // 临时，会赋值给dst
    // 用于主动事件触发
	struct event *ev;

	/* original source and destination address, and family */
	struct sockaddr_storage srcaddr;
	socklen_t srcaddrlen;
	struct sockaddr_storage dstaddr;
	socklen_t dstaddrlen;
	int af;

	// Thread that the conn is attached to
	pxy_thr_ctx_t *thr;

	pxy_thrmgr_ctx_t *thrmgr;
	// Init to proxyspec conn_opts, but may be replaced with filter rule conn_opts
	// so, we don't free this conn_opts while freeing pxy_conn_ctx
	conn_opts_t *conn_opts;
	proxyspec_t *spec;
	global_t *global;

	evutil_socket_t dst_fd;
	evutil_socket_t srvdst_fd;


	// fd of event listener for children, explicitly closed on error (not for stats only)
	evutil_socket_t child_fd;
	struct evconnlistener *child_evcl;

	// SSLproxy specific info: ip:port addr child is listening on, orig client addr, and orig server addr
	// SSLproxy header is never sent to the Internet, always removed by child conns
	char *sslproxy_header;
	size_t sslproxy_header_len;
	unsigned int sent_sslproxy_header : 1; /* 1 to prevent inserting SSLproxy header twice */

#ifdef DEBUG_PROXY
	// Listening programs may create multiple child connections, such as Squid http proxy
	// Number of child conns, active or closed, always goes up never down, also used as child id, used in debugging only
	unsigned int child_count;
#endif /* DEBUG_PROXY */
	// List of child conns
	pxy_conn_child_ctx_t *children;

	// For statistics only
	evutil_socket_t child_src_fd;
	evutil_socket_t child_dst_fd;

	
	
	// Per-thread conn list, used to determine idle and expired conns, and to close them
	pxy_conn_ctx_t *next;
	pxy_conn_ctx_t *prev;

	// Expired conns are link-listed using this pointer, a temporary list used in conn thr timercb only
	pxy_conn_ctx_t *next_expired;

	unsigned int sent_protoerror_msg : 1;   /* 1 until error msg is sent */

	unsigned int divert : 1;                         /* 1 to divert conn */
	unsigned int pass : 1;                     /* 1 to pass conn through */

	// Enable logging of conn for specific logger types
	// Global logging options should be configured for these to write logs
	// Default to all logging if no filter rules defined in proxyspec
	// Otherwise, logging is disabled, so filter rules should enable/disable each log action specifically
	unsigned int log_connect : 1;
	unsigned int log_master : 1;
	unsigned int log_cert : 1;
	unsigned int log_content : 1;
	unsigned int log_pcap : 1;

	// The precedence of filtering rule applied precedence can only go up not down
	unsigned int filter_precedence;

	// Deferred filter action from an earlier filter application
	unsigned int deferred_action;

#ifdef HAVE_LOCAL_PROCINFO
	/* local process information */
	pxy_conn_lproc_desc_t lproc;
#endif /* HAVE_LOCAL_PROCINFO */
};

/* child connection state consisting of two connection descriptors,
 * connection-wide state */
struct pxy_conn_child_ctx {
	enum conn_type type;

#ifdef DEBUG_PROXY
	// Unique id, set to the children count of parent conn, used in debugging only
	unsigned int id;
#endif /* DEBUG_PROXY */

	// Parent conn
	pxy_conn_ctx_t *conn;

	/* per-connection state */
	struct pxy_conn_desc src;
	struct pxy_conn_desc dst;

	/* store fd and fd event while connected is 0 */
	evutil_socket_t fd;

	proto_child_ctx_t *protoctx;

	/* status flags */
	unsigned int connected : 1;       /* 0 until both ends are connected */
	unsigned int term : 1;                     /* 0 until term requested */
	// srvdst_xferred flag is important not to access the srvdst.bev of parent after the first child is freed
	unsigned int srvdst_xferred : 1;  /* 1 if srvdst xferred from parent */

	// For statistics only
	evutil_socket_t dst_fd;

	// Child conns remove the SSLproxy header inserted by parent
	int removed_sslproxy_header;   /* 1 after SSLproxy header is removed */

	// Children of the conn are link-listed using this pointer
	pxy_conn_child_ctx_t *next;
	pxy_conn_child_ctx_t *prev;
};

#ifdef HAVE_LOCAL_PROCINFO
int pxy_prepare_logging_local_procinfo(pxy_conn_ctx_t *) NONNULL(1);
#endif /* HAVE_LOCAL_PROCINFO */

void pxy_log_connect_src(pxy_conn_ctx_t *) NONNULL(1);
void pxy_log_connect_srvdst(pxy_conn_ctx_t *) NONNULL(1);

void pxy_log_connect_nonhttp(pxy_conn_ctx_t *) NONNULL(1);
void pxy_log_dbg_evbuf_info(pxy_conn_ctx_t *, pxy_conn_desc_t *, pxy_conn_desc_t *) NONNULL(1,2,3);

unsigned char *pxy_malloc_packet(size_t, pxy_conn_ctx_t *) MALLOC NONNULL(2) WUNRES;

int pxy_try_prepend_sslproxy_header(pxy_conn_ctx_t *ctx, struct evbuffer *, struct evbuffer *) NONNULL(1,2,3);
void pxy_try_remove_sslproxy_header(pxy_conn_child_ctx_t *, unsigned char *, size_t *) NONNULL(1,2,3);

void pxy_try_set_watermark(struct bufferevent *, pxy_conn_ctx_t *, struct bufferevent *) NONNULL(1,2,3);
void pxy_try_unset_watermark(struct bufferevent *, pxy_conn_ctx_t *, pxy_conn_desc_t *) NONNULL(1,2,3);

int pxy_try_close_conn_end(pxy_conn_desc_t *, pxy_conn_ctx_t *) NONNULL(1,2);

void pxy_try_disconnect(pxy_conn_ctx_t *, pxy_conn_desc_t *, pxy_conn_desc_t *, int) NONNULL(1,2,3);
void pxy_try_disconnect_child(pxy_conn_child_ctx_t *, pxy_conn_desc_t *, pxy_conn_desc_t *) NONNULL(1,2,3);

int pxy_try_consume_last_input(struct bufferevent *, pxy_conn_ctx_t *) NONNULL(1,2);
int pxy_try_consume_last_input_child(struct bufferevent *, pxy_conn_child_ctx_t *) NONNULL(1,2);
void pxy_discard_inbuf(struct bufferevent *) NONNULL(1);

int pxy_conn_init(pxy_conn_ctx_t *) NONNULL(1);
void pxy_conn_ctx_free(pxy_conn_ctx_t *, int) NONNULL(1);
void pxy_conn_free(pxy_conn_ctx_t *, int) NONNULL(1);
void pxy_conn_term(pxy_conn_ctx_t *, int) NONNULL(1);
void pxy_conn_term_child(pxy_conn_child_ctx_t *) NONNULL(1);
void pxy_conn_free_children(pxy_conn_ctx_t *) NONNULL(1);

int pxy_setup_child_listener(pxy_conn_ctx_t *) NONNULL(1);

int pxy_bev_readcb_preexec_logging_and_stats(struct bufferevent *, pxy_conn_ctx_t *) NONNULL(1,2);

void pxy_bev_readcb(struct bufferevent *, void *);
void pxy_bev_writecb(struct bufferevent *, void *);
void pxy_bev_eventcb(struct bufferevent *, short, void *);

int pxy_prepare_logging(pxy_conn_ctx_t *ctx);

int pxy_bev_readcb_preexec_logging_and_stats_child(struct bufferevent *, pxy_conn_child_ctx_t *) NONNULL(1,2);
void pxy_bev_eventcb_postexec_stats_child(short, pxy_conn_child_ctx_t *) NONNULL(2);

void pxy_bev_readcb_child(struct bufferevent *, void *);
void pxy_bev_writecb_child(struct bufferevent *, void *);
void pxy_bev_eventcb_child(struct bufferevent *, short, void *);

void pxy_conn_connect(pxy_conn_ctx_t *) NONNULL(1);
//#ifndef WITHOUT_USERAUTH
//int pxy_is_listuser(userlist_t *, const char *
//#ifdef DEBUG_PROXY
//	, pxy_conn_ctx_t *, const char *
//#endif /* DEBUG_PROXY */
//	) NONNULL(2);
//void pxy_classify_user(pxy_conn_ctx_t *) NONNULL(1);
//void pxy_userauth(pxy_conn_ctx_t *) NONNULL(1);
//#endif /* !WITHOUT_USERAUTH */
int pxy_conn_apply_deferred_block_action(pxy_conn_ctx_t *) NONNULL(1) WUNRES;
int pxy_conn_apply_filter(pxy_conn_ctx_t *, unsigned int) NONNULL(1);
unsigned int pxy_conn_translate_filter_action(pxy_conn_ctx_t *, filter_action_t *);
filter_action_t *pxy_conn_set_filter_action(filter_action_t *, filter_action_t *
#ifdef DEBUG_PROXY
	, pxy_conn_ctx_t *, char *, char *
#endif /* DEBUG_PROXY */
	) WUNRES;
filter_action_t *pxy_conn_filter_port(pxy_conn_ctx_t *, filter_site_t *) NONNULL(1,2);
filter_action_t * pxy_conn_filter(pxy_conn_ctx_t *, proto_filter_func_t) NONNULL(1) WUNRES;
void pxy_conn_setup(evutil_socket_t, struct sockaddr *, int,
                    pxy_thrmgr_ctx_t *, proxyspec_t *, global_t *,
					evutil_socket_t)
                    NONNULL(2,4,5,6);

void saveToDB(char* schemes,
              char* task_id,
              long long unsigned int  conn_id,
              char *srchost_str,  //  来源host
              char *srcport_str,  //  来源port
              char *dsthost_str,  //  目的地host
              char *dstport_str,  //
              
              long long unsigned int in_bytes, // 接收数据量
              long long unsigned int out_bytes,
              
              double dns_time_s, // 开始dns
              double connect_s,  // 开始连接
              double send_s,     // 开发发送
              double send_e,     // 发送完毕
              double receive_s,  // 开始接收
              double receive_e,  // 接收完毕
              char* method,
              char* uri,
              char* host,
              char* req_line,
              char* req_content_type,
              char* req_encode,
              char* req_body_size,
              char* req_target,
              char* rsp_line,
              char* rsp_state,
              char* rsp_message,
              char* rsp_content_type,
              char* rsp_encode,
              char* rsp_body_size
              );

#endif /* !PXYCONN_H */

/* vim: set noet ft=c: */
