/*-
 */

#include "pxyconn.h"

#include "prototcp.h"
#include "protossl.h"
#include "protohttp.h"
#include "protopop3.h"
#include "protosmtp.h"
#include "protoautossl.h"
#include "protopassthrough.h"
#include "pmain.h"

#include "privsep.h"
#include "sys.h"
#include "log.h"
#include "attrib.h"
#include "proc.h"
#include "util.h"

#include <string.h>
#include <arpa/inet.h>
#include <sys/param.h>
#include <assert.h>

#include <event2/listener.h>

#ifdef __linux__
#include <glob.h>
#endif /* __linux__ */

//#include <net/if_arp.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#if (__linux__ && HAVE_SYSCTL) || !__linux__
#include <sys/sysctl.h>
#endif
//#include <net/route.h>
//#include <netinet/if_ether.h>
#ifdef __OpenBSD__
#include <net/if_dl.h>
#endif /* __OpenBSD__ */

/*
 * Maximum size of data to buffer per connection direction before
 * temporarily stopping to read data from the other end.
 */
#define OUTBUF_LIMIT	(128*1024)

// getdtablecount() returns int, hence we don't use size_t here
int descriptor_table_size = 0;

// @attention The order of names should match the order in protocol enum
char *protocol_names[] = {
	// ERROR = -1
	"PASSTHROUGH", // = 0
	"HTTP",
	"HTTPS",
	"POP3",
	"POP3S",
	"SMTP",
	"SMTPS",
	"AUTOSSL",
	"TCP",
	"SSL",
};

static protocol_t NONNULL(1)
pxy_setup_proto_child(pxy_conn_child_ctx_t *ctx)
{
	ctx->protoctx = malloc(sizeof(proto_child_ctx_t));
	if (!ctx->protoctx) {
		return PROTO_ERROR;
	}
	memset(ctx->protoctx, 0, sizeof(proto_child_ctx_t));

	// Default to tcp
	prototcp_setup_child(ctx);

	protocol_t proto;
	if (ctx->conn->spec->upgrade) {
		proto = protoautossl_setup_child(ctx);
	} else if (ctx->conn->spec->http) {
		if (ctx->conn->spec->ssl) {
			proto = protohttps_setup_child(ctx);
		} else {
			proto = protohttp_setup_child(ctx);
		}
	} else if (ctx->conn->spec->pop3) {
		if (ctx->conn->spec->ssl) {
			proto = (protossl_setup_child(ctx) != PROTO_ERROR) ? PROTO_POP3S : PROTO_ERROR;
		} else {
			proto = PROTO_POP3;
		}
	} else if (ctx->conn->spec->smtp) {
		if (ctx->conn->spec->ssl) {
			proto = (protossl_setup_child(ctx) != PROTO_ERROR) ? PROTO_SMTPS : PROTO_ERROR;
		} else {
			proto = PROTO_SMTP;
		}
	} else if (ctx->conn->spec->ssl) {
		proto = protossl_setup_child(ctx);
	} else {
		proto = PROTO_TCP;
	}

	if (proto == PROTO_ERROR) {
		free(ctx->protoctx);
	}
	return proto;
}

static pxy_conn_child_ctx_t * MALLOC NONNULL(2)
pxy_conn_ctx_new_child(evutil_socket_t fd, pxy_conn_ctx_t *ctx)
{
	assert(ctx != NULL);

	log_finest_va("ENTER, fd=%d", fd);

	pxy_conn_child_ctx_t *child_ctx = malloc(sizeof(pxy_conn_child_ctx_t));
	if (!child_ctx) {
		return NULL;
	}
	memset(child_ctx, 0, sizeof(pxy_conn_child_ctx_t));

	child_ctx->type = CONN_TYPE_CHILD;
#ifdef DEBUG_PROXY
	child_ctx->id = ctx->child_count++;
#endif /* DEBUG_PROXY */
	child_ctx->conn = ctx;
	child_ctx->fd = fd;

	if (pxy_setup_proto_child(child_ctx) == PROTO_ERROR) {
		free(child_ctx);
		return NULL;
	}
	return child_ctx;
}

static void NONNULL(1)
pxy_conn_ctx_free_child(pxy_conn_child_ctx_t *ctx)
{
	log_finest("ENTER");

	// If the proto doesn't have special args, proto_free() callback is NULL
	if (ctx->protoctx->proto_free) {
		ctx->protoctx->proto_free(ctx);
	}
	free(ctx->protoctx);
	free(ctx);
}

// This function cannot fail.
static void NONNULL(1)
pxy_conn_attach_child(pxy_conn_child_ctx_t *ctx)
{
	log_finest("Adding child conn");

	// @attention Child connections use the parent's event bases, otherwise we would get multithreading issues
	// Always keep thr load and conns list in sync
	ctx->conn->thr->load++;
	ctx->conn->thr->max_load = max(ctx->conn->thr->max_load, ctx->conn->thr->load);

	// Prepend child to the children list of parent
	ctx->next = ctx->conn->children;
	ctx->conn->children = ctx;
	if (ctx->next)
		ctx->next->prev = ctx;
}

// This function cannot fail.
static void NONNULL(1)
pxy_conn_detach_child(pxy_conn_child_ctx_t *ctx)
{
	assert(ctx->conn != NULL);
	assert(ctx->conn->children != NULL);

	log_finest("Removing child conn");

	ctx->conn->thr->load--;

	if (ctx->prev) {
		ctx->prev->next = ctx->next;
	} else {
		ctx->conn->children = ctx->next;
	}
	if (ctx->next)
		ctx->next->prev = ctx->prev;

#ifdef DEBUG_PROXY
	if (ctx->conn->children) {
		if (ctx->id == ctx->conn->children->id) {
			// This should never happen
			log_fine("Found child in conn children, first");
			assert(0);
		} else {
			pxy_conn_child_ctx_t *current = ctx->conn->children->next;
			pxy_conn_child_ctx_t *previous = ctx->conn->children;
			while (current != NULL && previous != NULL) {
				if (ctx->id == current->id) {
					// This should never happen
					log_fine("Found child in conn children");
					assert(0);
				}
				previous = current;
				current = current->next;
			}
			log_finest("Cannot find child in conn children");
		}
	} else {
		log_finest("Cannot find child in conn children, empty");
	}
#endif /* DEBUG_PROXY */
}

static void
pxy_conn_free_child(pxy_conn_child_ctx_t *ctx)
{
	assert(ctx->conn != NULL);

	log_finest("ENTER");

	// We always assign NULL to bevs after freeing them
	if (ctx->src.bev) {
		ctx->src.zfree(ctx->src.bev, ctx->conn);
		ctx->src.bev = NULL;
	} else if (!ctx->src.closed) {
		log_fine("!src.closed, evutil_closesocket on NULL src.bev");

		// @attention early in the conn setup, src fd may be open, although src.bev is NULL
		evutil_closesocket(ctx->fd);
	}

	if (ctx->dst.bev) {
		ctx->dst.zfree(ctx->dst.bev, ctx->conn);
		ctx->dst.bev = NULL;
	}

	// Save conn and srvdst_xferred before freeing ctx
	pxy_conn_ctx_t *conn = ctx->conn;
	unsigned int srvdst_xferred = ctx->srvdst_xferred;

	pxy_conn_detach_child(ctx);
	pxy_conn_ctx_free_child(ctx);

	// If there is no child left, free child_evcl asap by calling pxy_conn_free_children()
	if (!conn->children) {
		pxy_conn_free_children(conn);
	}

	// If this is the first child, NULL srvdst.bev, so we don't try to access it from this point on
	if (srvdst_xferred) {
		conn->srvdst.bev = NULL;
	}
}

void
pxy_conn_term_child(pxy_conn_child_ctx_t *ctx)
{
	log_finest("ENTER");
	ctx->term = 1;
}

void
pxy_conn_free_children(pxy_conn_ctx_t *ctx)
{
	log_finest("ENTER");

	// @attention Free the child ctxs asap, we need their fds
	while (ctx->children) {
		pxy_conn_free_child(ctx->children);
	}

	// @attention Parent may be closing before there was any child at all nor was child_evcl ever created
	if (ctx->child_evcl) {
		log_finer_va("Freeing child_evcl, children fd=%d", ctx->children ? ctx->children->fd : -1);

		// @attention child_evcl was created with LEV_OPT_CLOSE_ON_FREE, so do not close ctx->child_fd
		evconnlistener_free(ctx->child_evcl);
		ctx->child_evcl = NULL;
	}
}

/*
 * Does full clean-up of conn ctx.
 * This is the conn handling thr version of a similar function
 * proxy_conn_ctx_free(), which runs on thrmgr and does minimal
 * clean-up.
 */
void
pxy_conn_ctx_free(pxy_conn_ctx_t *ctx, int by_requestor)
{
	log_finest("ENTER");

	if (WANT_CONTENT_LOG(ctx)) {
		// Always try to close log files, even if content, pcap, or mirror logging is disabled by filter rules
		// The log files may have been initialized and opened
		// so, do not pass down the log_content, log_pcap, and log_mirror fields of ctx
		if (log_content_close(&ctx->logctx, by_requestor) == -1) {
			log_err_level_printf(LOG_WARNING, "Content log close failed\n");
		}
	}

//#ifndef WITHOUT_USERAUTH
//	if (ctx->conn_opts->user_auth && ctx->srchost_str && ctx->user && ctx->ether) {
//		// Update userdb atime if idle time is more than 50% of user timeout, which is expected to reduce update frequency
//		unsigned int idletime = ctx->idletime + (time(NULL) - ctx->ctime);
//		if (idletime > (ctx->conn_opts->user_timeout / 2)) {
//			userdbkeys_t keys;
//			// Zero out for NULL termination
//			memset(&keys, 0, sizeof(userdbkeys_t));
//			// Leave room for NULL to make sure the strings are always NULL terminated
//			strncpy(keys.ip, ctx->srchost_str, sizeof(keys.ip) - 1);
//			strncpy(keys.user, ctx->user, sizeof(keys.user) - 1);
//			strncpy(keys.ether, ctx->ether, sizeof(keys.ether) - 1);
//
//			if (privsep_client_update_atime(ctx->clisock, &keys) == -1) {
//				log_finest_va("Error updating user atime: %s", sqlite3_errmsg(ctx->global->userdb));
//			} else {
//				log_finest("Successfully updated user atime");
//			}
//		} else {
//			log_finest_va("Will not update user atime, idletime=%u", idletime);
//		}
//	}
//#endif /* !WITHOUT_USERAUTH */

	pxy_thr_detach(ctx);

	if (ctx->srchost_str) {
		free(ctx->srchost_str);
	}
	if (ctx->srcport_str) {
		free(ctx->srcport_str);
	}
	if (ctx->dsthost_str) {
		free(ctx->dsthost_str);
	}
	if (ctx->dstport_str) {
		free(ctx->dstport_str);
	}
#ifdef HAVE_LOCAL_PROCINFO
	if (ctx->lproc.exec_path) {
		free(ctx->lproc.exec_path);
	}
	if (ctx->lproc.user) {
		free(ctx->lproc.user);
	}
	if (ctx->lproc.group) {
		free(ctx->lproc.group);
	}
#endif /* HAVE_LOCAL_PROCINFO */
	if (ctx->ev) {
		event_free(ctx->ev);
	}
	if (ctx->sslproxy_header) {
		free(ctx->sslproxy_header);
	}
	// If the proto doesn't have special args, proto_free() callback is NULL
	if (ctx->protoctx->proto_free) {
		ctx->protoctx->proto_free(ctx);
	}
	free(ctx->protoctx);

//#ifndef WITHOUT_USERAUTH
//	if (ctx->user) {
//		free(ctx->user);
//	}
//	if (ctx->ether) {
//		free(ctx->ether);
//	}
//	if (ctx->desc) {
//		free(ctx->desc);
//	}
//#endif /* !WITHOUT_USERAUTH */
	free(ctx);
}

void
pxy_conn_free(pxy_conn_ctx_t *ctx, int by_requestor)
{
	log_finest("ENTER");
    ctx->time_c = current_time();
    conn_http_info_t *http_info = ctx->extra_info;
    // TODO:将请求写入数据库
    char *schemes = "HTTP";
    if (ctx->proto == PROTO_HTTPS) {
        schemes = "HTTPS";
    }
    saveToDB(schemes,
             ctx->task_id ? ctx->task_id : "",
             ctx->id,
             ctx->srchost_str ? ctx->srchost_str : "",
             ctx->srcport_str ? ctx->srcport_str : "",
             ctx->dsthost_str ? ctx->dsthost_str : "",
             ctx->dstport_str ? ctx->dstport_str : "",

             ctx->in_bytes,
             ctx->out_bytes,

             ctx->dns_time_s,
             ctx->connect_s,
             ctx->send_s,
             ctx->send_e,
             ctx->receive_s,
             ctx->receive_e,
             http_info->method ? http_info->method : "",
             http_info->uri ? http_info->uri : "",
             http_info->host ? http_info->host : "",
             http_info->req_line ? http_info->req_line : "",
             http_info->req_content_type ? http_info->req_content_type : "",
             http_info->req_encode ? http_info->req_encode : "",
             http_info->req_body_size ? http_info->req_body_size : "",
             http_info->req_target ? http_info->req_target : "",
             http_info->rsp_line ? http_info->rsp_line : "",
             http_info->rsp_state ? http_info->rsp_state : "",
             http_info->rsp_message ? http_info->rsp_message : "",
             http_info->rsp_content_type ? http_info->rsp_content_type : "",
             http_info->rsp_encode ? http_info->rsp_encode : "",
             http_info->rsp_body_size ? http_info->rsp_body_size : "");
    updateTask(ctx->task_id ? ctx->task_id : "", ctx->thrmgr->conn_count, ctx->thrmgr->all_out_bytes, ctx->thrmgr->all_in_bytes, 0, 0, http_info->req_line ? http_info->req_line : "");
    
	// We always assign NULL to bevs after freeing them
	if (ctx->src.bev) {
        if(ctx->src.zfree){
            ctx->src.zfree(ctx->src.bev, ctx);
        }
		ctx->src.bev = NULL;
	} else if (!ctx->src.closed) {
		log_fine("evutil_closesocket on NULL src.bev");
		// @attention early in the conn setup, src fd may be open, although src.bev is NULL
		evutil_closesocket(ctx->fd);
	}

	if (ctx->srvdst.bev) {
		// In split mode, srvdst is used as dst, so it should be freed as dst below
		// If srvdst has been xferred to the first child conn, the child should free it, not the parent
		if (ctx->divert && !ctx->srvdst_xferred) {
			ctx->srvdst.zfree(ctx->srvdst.bev, ctx);
		} else /*if (!ctx->divert || ctx->srvdst_xferred)*/ {
			// We reuse srvdst as dst or child dst, so srvdst == dst or child_dst.
			// But if we don't NULL the callbacks of srvdst in split mode,
			// we randomly but rarely get a second eof event for srvdst during conn termination (especially on arm64),
			// which crashes us with signal 11 or 10, because the first eof event for dst frees the ctx.
			// Note that we don't free anything here, but just disable callbacks and events.
			// This does not seem to happen with srvdst_xferred, but just to be safe we do the same for it too.
			// This seems to be an issue with libevent.
			// @todo Why does libevent raise the same event again for an already disabled and freed conn end?
			// Note again that srvdst == dst or child_dst here.

			struct bufferevent *ubev = bufferevent_get_underlying(ctx->srvdst.bev);

			bufferevent_setcb(ctx->srvdst.bev, NULL, NULL, NULL, NULL);
			bufferevent_disable(ctx->srvdst.bev, EV_READ|EV_WRITE);

			if (ubev) {
				bufferevent_setcb(ubev, NULL, NULL, NULL, NULL);
				bufferevent_disable(ubev, EV_READ|EV_WRITE);
			}
		}
		ctx->srvdst.bev = NULL;
	}

	if (ctx->dst.bev) {
		ctx->dst.zfree(ctx->dst.bev, ctx);
		ctx->dst.bev = NULL;
	}

	pxy_conn_free_children(ctx);
	pxy_conn_ctx_free(ctx, by_requestor);
}

void
pxy_conn_term(pxy_conn_ctx_t *ctx, int by_requestor)
{
	log_finest("ENTER");
	ctx->term = 1;
	ctx->term_requestor = by_requestor;
}

void
pxy_log_connect_nonhttp(pxy_conn_ctx_t *ctx)
{
	if (!ctx->log_connect)
		return;

	char *msg;
#ifdef HAVE_LOCAL_PROCINFO
	char *lpi = NULL;
#endif /* HAVE_LOCAL_PROCINFO */
	int rv;

#ifdef HAVE_LOCAL_PROCINFO
	if (ctx->global->lprocinfo) {
		rv = asprintf(&lpi, "lproc:%i:%s:%s:%s",
		              ctx->lproc.pid,
		              STRORDASH(ctx->lproc.user),
		              STRORDASH(ctx->lproc.group),
		              STRORDASH(ctx->lproc.exec_path));
		if ((rv < 0) || !lpi) {
			ctx->enomem = 1;
			goto out;
		}
	} else {
		lpi = "";
	}
#endif /* HAVE_LOCAL_PROCINFO */

	/*
	 * The following ifdef's within asprintf arguments list generates
	 * warnings with -Wembedded-directive on some compilers.
	 * Not fixing the code in order to avoid more code duplication.
	 */

	if (!ctx->src.ssl) {
		rv = asprintf(&msg, "CONN: %s %s %s %s %s"
#ifdef HAVE_LOCAL_PROCINFO
		              " %s"
#endif /* HAVE_LOCAL_PROCINFO */
//#ifndef WITHOUT_USERAUTH
//		              " user:%s"
//#endif /* !WITHOUT_USERAUTH */
		              "\n",
		              ctx->proto == PROTO_AUTOSSL ? "autossl" : (ctx->proto == PROTO_PASSTHROUGH ? "passthrough" : (ctx->proto == PROTO_POP3 ? "pop3" : (ctx->proto == PROTO_SMTP ? "smtp" : "tcp"))),
		              STRORDASH(ctx->srchost_str),
		              STRORDASH(ctx->srcport_str),
		              STRORDASH(ctx->dsthost_str),
		              STRORDASH(ctx->dstport_str)
#ifdef HAVE_LOCAL_PROCINFO
		              , lpi
#endif /* HAVE_LOCAL_PROCINFO */
//#ifndef WITHOUT_USERAUTH
//		              , STRORDASH(ctx->user)
//#endif /* !WITHOUT_USERAUTH */
		              );
	} else {
		rv = asprintf(&msg, "CONN: %s %s %s %s %s "
		              "sni:%s names:%s "
		              "sproto:%s:%s dproto:%s:%s "
		              "origcrt:%s usedcrt:%s"
#ifdef HAVE_LOCAL_PROCINFO
		              " %s"
#endif /* HAVE_LOCAL_PROCINFO */
//#ifndef WITHOUT_USERAUTH
//		              " user:%s"
//#endif /* !WITHOUT_USERAUTH */
		              "\n",
		              ctx->proto == PROTO_AUTOSSL ? "autossl" : (ctx->proto == PROTO_POP3S ? "pop3s" : (ctx->proto == PROTO_SMTPS ? "smtps" : "ssl")),
		              STRORDASH(ctx->srchost_str),
		              STRORDASH(ctx->srcport_str),
		              STRORDASH(ctx->dsthost_str),
		              STRORDASH(ctx->dstport_str),
		              STRORDASH(ctx->sslctx->sni),
		              STRORDASH(ctx->sslctx->ssl_names),
		              SSL_get_version(ctx->src.ssl),
		              SSL_get_cipher(ctx->src.ssl),
		              STRORDASH(ctx->sslctx->srvdst_ssl_version),
		              STRORDASH(ctx->sslctx->srvdst_ssl_cipher),
		              STRORDASH(ctx->sslctx->origcrtfpr),
		              STRORDASH(ctx->sslctx->usedcrtfpr)
#ifdef HAVE_LOCAL_PROCINFO
		              , lpi
#endif /* HAVE_LOCAL_PROCINFO */
//#ifndef WITHOUT_USERAUTH
//		              , STRORDASH(ctx->user)
//#endif /* !WITHOUT_USERAUTH */
		              );
	}
	if ((rv < 0) || !msg) {
		ctx->enomem = 1;
		goto out;
	}
	if (!ctx->global->detach) {
		log_err_printf("%s", msg);
	} else if (ctx->global->statslog) {
		if (log_conn(msg) == -1) {
			log_err_level_printf(LOG_WARNING, "Conn logging failed\n");
		}
	}
	if (ctx->global->connectlog) {
		if (log_connect_print_free(msg) == -1) {
			free(msg);
			log_err_level_printf(LOG_WARNING, "Connection logging failed\n");
		}
	} else {
		free(msg);
	}
out:
#ifdef HAVE_LOCAL_PROCINFO
	if (lpi && ctx->global->lprocinfo) {
		free(lpi);
	}
#endif /* HAVE_LOCAL_PROCINFO */
	return;
}

static int NONNULL(1)
pxy_log_content_inbuf(pxy_conn_ctx_t *ctx, struct evbuffer *inbuf, int req)
{
	if (!ctx->log_content && !ctx->log_pcap) {
		return 0;
	}

	size_t sz = evbuffer_get_length(inbuf);
	unsigned char *buf = malloc(sz);
	if (!buf) {
		ctx->enomem = 1;
		return -1;
	}
	if (evbuffer_copyout(inbuf, buf, sz) == -1) {
		free(buf);
		return -1;
	}
	logbuf_t *lb = logbuf_new_alloc(sz, NULL);
	if (!lb) {
		free(buf);
		ctx->enomem = 1;
		return -1;
	}
	memcpy(lb->buf, buf, lb->sz);
	free(buf);
	if (log_content_submit(&ctx->logctx, lb, req, ctx->log_content, ctx->log_pcap) == -1) {
		logbuf_free(lb);
		log_err_level_printf(LOG_WARNING, "Content log submission failed\n");
		return -1;
	}
	return 0;
}

#ifdef HAVE_LOCAL_PROCINFO
int
pxy_prepare_logging_local_procinfo(pxy_conn_ctx_t *ctx)
{
	if (ctx->global->lprocinfo) {
		/* fetch process info */
		if (proc_pid_for_addr(&ctx->lproc.pid,
				(struct sockaddr*)&ctx->lproc.srcaddr,
				ctx->lproc.srcaddrlen) == 0 &&
			ctx->lproc.pid != -1 &&
			proc_get_info(ctx->lproc.pid,
						  &ctx->lproc.exec_path,
						  &ctx->lproc.uid,
						  &ctx->lproc.gid) == 0) {
			/* fetch user/group names */
			ctx->lproc.user = sys_user_str(
							ctx->lproc.uid);
			ctx->lproc.group = sys_group_str(
							ctx->lproc.gid);
			if (!ctx->lproc.user ||
				!ctx->lproc.group) {
				ctx->enomem = 1;
				pxy_conn_term(ctx, 1);
				return -1;
			}
		}
	}
	return 0;
}
#endif /* HAVE_LOCAL_PROCINFO */

int
pxy_prepare_logging(pxy_conn_ctx_t *ctx)
{
//    printf("--- pxy_prepare_logging \n");
	/* prepare logging, part 2 */
#ifdef HAVE_LOCAL_PROCINFO
	if (WANT_CONNECT_LOG(ctx) || WANT_CONTENT_LOG(ctx)) {
		if (pxy_prepare_logging_local_procinfo(ctx) == -1) {
			return -1;
		}
	}
#endif /* HAVE_LOCAL_PROCINFO */
	if (WANT_CONTENT_LOG(ctx)) {
        //
//        ctx->task_id
//        ctx->id
		if (log_content_open(&ctx->logctx, ctx->global,
							 (struct sockaddr *)&ctx->srcaddr,
							 ctx->srcaddrlen,
							 (struct sockaddr *)&ctx->dstaddr,
							 ctx->dstaddrlen,
							 STRORDASH(ctx->srchost_str), STRORDASH(ctx->srcport_str),
							 STRORDASH(ctx->dsthost_str), STRORDASH(ctx->dstport_str),
							 NULL, NULL, NULL,
							 ctx->log_content, ctx->log_pcap
                            , ctx->task_id, ctx->id
		) == -1) {
			if (errno == ENOMEM)
				ctx->enomem = 1;
			pxy_conn_term(ctx, 1);
			return -1;
		}
	}
	return 0;
}

static void NONNULL(1,2)
pxy_log_dbg_connect_type(pxy_conn_ctx_t *ctx, pxy_conn_desc_t *this)
{
	if (OPTS_DEBUG(ctx->global)) {
		if (this->ssl) {
			char *keystr;
			/* for SSL, we get two connect events */
			log_dbg_printf("%s connected to [%s]:%s %s %s\n",
						   protocol_names[ctx->proto],
						   STRORDASH(ctx->dsthost_str), STRORDASH(ctx->dstport_str),
						   SSL_get_version(this->ssl), SSL_get_cipher(this->ssl));
			keystr = ssl_ssl_masterkey_to_str(this->ssl);
			if (keystr) {
				log_dbg_print_free(keystr);
			}
		} else {
			/* for TCP, we get only a dst connect event,
			 * since src was already connected from the
			 * beginning; mirror SSL debug output anyway
			 * in order not to confuse anyone who might be
			 * looking closely at the output */
			log_dbg_printf("%s connected to [%s]:%s\n",
						   protocol_names[ctx->proto],
						   STRORDASH(ctx->dsthost_str), STRORDASH(ctx->dstport_str));
			log_dbg_printf("%s connected from [%s]:%s\n",
						   protocol_names[ctx->proto],
						   STRORDASH(ctx->srchost_str), STRORDASH(ctx->srcport_str));
		}
	}
}

void
pxy_log_connect_src(pxy_conn_ctx_t *ctx)
{
	/* log connection if we don't analyze any headers */
	if (!ctx->spec->http && WANT_CONNECT_LOG(ctx)) {
		pxy_log_connect_nonhttp(ctx);
	}

	if (ctx->src.ssl && ctx->log_cert && ctx->global->certgendir) {
		/* write SSL certificates to gendir */
		protossl_srccert_write(ctx);
	}

	if (protossl_log_masterkey(ctx, &ctx->src) == -1) {
		return;
	}

	pxy_log_dbg_connect_type(ctx, &ctx->src);
}

void
pxy_log_connect_srvdst(pxy_conn_ctx_t *ctx)
{
	// @attention srvdst.bev may be NULL, if its writecb fires first
	if (ctx->srvdst.bev) {
		/* log connection if we don't analyze any headers */
		if (!ctx->srvdst.ssl && !ctx->spec->http && WANT_CONNECT_LOG(ctx)) {
			pxy_log_connect_nonhttp(ctx);
		}

		if (protossl_log_masterkey(ctx, &ctx->srvdst) == -1) {
			return;
		}

		pxy_log_dbg_connect_type(ctx, &ctx->srvdst);
	}
}

static void
pxy_log_dbg_disconnect(pxy_conn_ctx_t *ctx)
{
	/* we only get a single disconnect event here for both connections */
	if (OPTS_DEBUG(ctx->global)) {
		log_dbg_printf("%s disconnected to [%s]:%s, fd=%d\n",
					   protocol_names[ctx->proto],
					   STRORDASH(ctx->dsthost_str), STRORDASH(ctx->dstport_str), ctx->fd);
		log_dbg_printf("%s disconnected from [%s]:%s, fd=%d\n",
					   protocol_names[ctx->proto],
					   STRORDASH(ctx->srchost_str), STRORDASH(ctx->srcport_str), ctx->fd);
	}
}

static void
pxy_log_dbg_disconnect_child(pxy_conn_child_ctx_t *ctx)
{
	/* we only get a single disconnect event here for both connections */
	if (OPTS_DEBUG(ctx->conn->global)) {
		log_dbg_printf("Child %s disconnected to [%s]:%s, child fd=%d, fd=%d\n",
					   protocol_names[ctx->conn->proto],
					   STRORDASH(ctx->conn->dsthost_str), STRORDASH(ctx->conn->dstport_str), ctx->fd, ctx->conn->fd);
		log_dbg_printf("Child %s disconnected from [%s]:%s, child fd=%d, fd=%d\n",
					   protocol_names[ctx->conn->proto],
					   STRORDASH(ctx->conn->srchost_str), STRORDASH(ctx->conn->srcport_str), ctx->fd, ctx->conn->fd);
	}
}

#ifdef DEBUG_PROXY
void
pxy_log_dbg_evbuf_info(pxy_conn_ctx_t *ctx, pxy_conn_desc_t *this, pxy_conn_desc_t *other)
{
	// This function is used by child conns too, they pass ctx->conn instead of ctx
	if (OPTS_DEBUG(ctx->global)) {
		log_dbg_printf("evbuffer size at EOF: i:%zu o:%zu i:%zu o:%zu\n",
						evbuffer_get_length(bufferevent_get_input(this->bev)),
						evbuffer_get_length(bufferevent_get_output(this->bev)),
						other->closed ? 0 : evbuffer_get_length(bufferevent_get_input(other->bev)),
						other->closed ? 0 : evbuffer_get_length(bufferevent_get_output(other->bev)));
	}
}
#endif /* DEBUG_PROXY */

unsigned char *
pxy_malloc_packet(size_t sz, pxy_conn_ctx_t *ctx)
{
	unsigned char *packet = malloc(sz);
	if (!packet) {
		ctx->enomem = 1;
		return NULL;
	}
	return packet;
}

#ifdef DEBUG_PROXY
char *bev_names[] = {
	"src",
	"dst",
	"srvdst",
	"NULL",
	"UNKWN"
};

static char *
pxy_get_event_name(struct bufferevent *bev, pxy_conn_ctx_t *ctx)
{
	if (bev == ctx->src.bev) {
		return bev_names[0];
	} else if (bev == ctx->dst.bev) {
		return bev_names[1];
	} else if (bev == ctx->srvdst.bev) {
		return bev_names[2];
	} else if (bev == NULL) {
		log_fine("event_name=NULL");
		return bev_names[3];
	} else {
		log_fine("event_name=UNKWN");
		return bev_names[4];
	}
}
#endif /* DEBUG_PROXY */

void
pxy_try_set_watermark(struct bufferevent *bev, pxy_conn_ctx_t *ctx, struct bufferevent *other)
{
	if (evbuffer_get_length(bufferevent_get_output(other)) >= OUTBUF_LIMIT) {
		log_fine_va("%s", pxy_get_event_name(bev, ctx));

		/* temporarily disable data source;
		 * set an appropriate watermark. */
		bufferevent_setwatermark(other, EV_WRITE, OUTBUF_LIMIT/2, OUTBUF_LIMIT);
		bufferevent_disable(bev, EV_READ);
		ctx->thr->set_watermarks++;
	}
}

void
pxy_try_unset_watermark(struct bufferevent *bev, pxy_conn_ctx_t *ctx, pxy_conn_desc_t *other)
{
	if (other->bev && !(bufferevent_get_enabled(other->bev) & EV_READ)) {
		log_fine_va("%s", pxy_get_event_name(bev, ctx));

		/* data source temporarily disabled;
		 * re-enable and reset watermark to 0. */
		bufferevent_setwatermark(bev, EV_WRITE, 0, 0);
		bufferevent_enable(other->bev, EV_READ);
		ctx->thr->unset_watermarks++;
	}
}

void
pxy_discard_inbuf(struct bufferevent *bev)
{
	struct evbuffer *inbuf = bufferevent_get_input(bev);
	size_t inbuf_size = evbuffer_get_length(inbuf);

	log_dbg_printf("Warning: Drained %zu bytes (conn closed)\n", inbuf_size);
	evbuffer_drain(inbuf, inbuf_size);
}

#ifdef DEBUG_PROXY
static void
pxy_insert_sslproxy_header(pxy_conn_ctx_t *ctx, unsigned char *packet, size_t *packet_size)
{
	log_finer("ENTER");

	// @attention Cannot use string manipulation functions; we are dealing with binary arrays here, not NULL-terminated strings
	memmove(packet + ctx->sslproxy_header_len + 2, packet, *packet_size);
	memcpy(packet, ctx->sslproxy_header, ctx->sslproxy_header_len);
	memcpy(packet + ctx->sslproxy_header_len, "\r\n", 2);
	*packet_size += ctx->sslproxy_header_len + 2;
	ctx->sent_sslproxy_header = 1;
}
#endif /* DEBUG_PROXY */

int
pxy_try_prepend_sslproxy_header(pxy_conn_ctx_t *ctx, struct evbuffer *inbuf, struct evbuffer *outbuf)
{
	log_finer("ENTER");

	if (ctx->divert && !ctx->sent_sslproxy_header) { // 先申请一块内存，大小为inbuf数据量+2+头长度，然后将inbuf里面的复制移到内存中，再在该内存里写入数据，然后发出去
#ifdef DEBUG_PROXY
		size_t packet_size = evbuffer_get_length(inbuf);
		// +2 for \r\n
		unsigned char *packet = pxy_malloc_packet(packet_size + ctx->sslproxy_header_len + 2, ctx);
		if (!packet) {
			return -1;
		}

		evbuffer_remove(inbuf, packet, packet_size);

		log_finest_va("ORIG packet, size=%zu:\n%.*s", packet_size, (int)packet_size, packet);

		pxy_insert_sslproxy_header(ctx, packet, &packet_size);
		evbuffer_add(outbuf, packet, packet_size);

		log_finest_va("NEW packet, size=%zu:\n%.*s", packet_size, (int)packet_size, packet);

		free(packet);
	}
	else {
		evbuffer_add_buffer(outbuf, inbuf);
	}
#else /* DEBUG_PROXY */
		evbuffer_add_printf(outbuf, "%s\r\n", ctx->sslproxy_header);
		ctx->sent_sslproxy_header = 1;
	}
	evbuffer_add_buffer(outbuf, inbuf);
#endif /* !DEBUG_PROXY */
	return 0;
}

void
pxy_try_remove_sslproxy_header(pxy_conn_child_ctx_t *ctx, unsigned char *packet, size_t *packet_size)
{
	// @attention Cannot use string manipulation functions; we are dealing with binary arrays here, not NULL-terminated strings
	unsigned char *pos = memmem(packet, *packet_size, ctx->conn->sslproxy_header, ctx->conn->sslproxy_header_len);
	if (pos) {
		log_finer("REMOVE");
		memmove(pos, pos + ctx->conn->sslproxy_header_len + 2, *packet_size - (pos - packet) - (ctx->conn->sslproxy_header_len + 2));
		*packet_size -= ctx->conn->sslproxy_header_len + 2;
		ctx->removed_sslproxy_header = 1;
	}
}

#if defined(__APPLE__) || defined(__FreeBSD__)
#define getdtablecount() 0

/*
 * Copied from:
 * opensmtpd-201801101641p1/openbsd-compat/imsg.c
 * 
 * Copyright (c) 2003, 2004 Henning Brauer <henning@openbsd.org>
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 */
static int
available_fds(unsigned int n)
{
	unsigned int i;
	int ret, fds[256];

	if (n > (sizeof(fds)/sizeof(fds[0])))
		return -1;

	ret = 0;
	for (i = 0; i < n; i++) {
		fds[i] = -1;
		if ((fds[i] = socket(AF_INET, SOCK_DGRAM, 0)) < 0) {
			ret = -1;
			break;
		}
	}

	for (i = 0; i < n && fds[i] >= 0; i++)
		close(fds[i]);

	return ret;
}
#endif /* __APPLE__ || __FreeBSD__ */

#ifdef __linux__
/*
 * Copied from:
 * https://github.com/tmux/tmux/blob/master/compat/getdtablecount.c
 * 
 * Copyright (c) 2017 Nicholas Marriott <nicholas.marriott@gmail.com>
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF MIND, USE, DATA OR PROFITS, WHETHER
 * IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING
 * OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 */
int
getdtablecount()
{
	char path[PATH_MAX];
	glob_t g;
	int n = 0;

	if (snprintf(path, sizeof path, "/proc/%ld/fd/*", (long)getpid()) < 0) {
		log_err_level_printf(LOG_CRIT, "snprintf overflow\n");
		return 0;
	}
	if (glob(path, 0, NULL, &g) == 0)
		n = g.gl_pathc;
	globfree(&g);
	return n;
}
#endif /* __linux__ */

/*
 * Check if we are out of file descriptors to close the conn, or else libevent will crash us
 * @attention We cannot guess the number of children in a connection at conn setup time. So, FD_RESERVE is just a ball park figure.
 * But what if a connection passes the check below, but eventually tries to create more children than FD_RESERVE allows for? This will crash us the same.
 * Beware, this applies to all current conns, not just the last connection setup.
 * For example, 20x conns pass the check below before creating any children, at which point we reach the last FD_RESERVE fds,
 * then they all start creating children, which crashes us again.
 * So, no matter how large an FD_RESERVE we choose, there will always be a risk of running out of fds, if we check the number of fds during parent conn setup only.
 * If we are left with less than FD_RESERVE fds, we should not create more children than FD_RESERVE allows for either.
 * Therefore, we check if we are out of fds in pxy_listener_acceptcb_child() and close the conn there too.
 * @attention These checks are expected to slow us further down, but it is critical to avoid a crash in case we run out of fds.
 */
static int
check_fd_usage(
#ifdef DEBUG_PROXY
	pxy_conn_ctx_t *ctx
#endif /* DEBUG_PROXY */
	)
{
	int dtable_count = getdtablecount();

	log_finer_va("descriptor_table_size=%d, dtablecount=%d, reserve=%d", descriptor_table_size, dtable_count, FD_RESERVE);

	if (dtable_count + FD_RESERVE >= descriptor_table_size) {
		goto out;
	}

#if defined(__APPLE__) || defined(__FreeBSD__)
	if (available_fds(FD_RESERVE) == -1) {
		goto out;
	}
#endif /* __APPLE__ || __FreeBSD__ */

	return 0;
out:
	errno = EMFILE;
	log_err_level_printf(LOG_CRIT, "Out of file descriptors\n");
	return -1;
}

/*
 * Callback for accept events on the socket listener bufferevent.
 */
static void
pxy_listener_acceptcb_child(UNUSED struct evconnlistener *listener, evutil_socket_t fd,
							UNUSED struct sockaddr *peeraddr, UNUSED int peeraddrlen, void *arg)
{
	pxy_conn_ctx_t *ctx = arg;

	ctx->atime = time(NULL);

#ifdef DEBUG_PROXY
	log_finest_va("ENTER, fd=%d, ctx->child_fd=%d", fd, ctx->child_fd);

	char *host, *port;
	if (sys_sockaddr_str(peeraddr, peeraddrlen, &host, &port) == 0) {
		log_finest_va("peer addr=[%s]:%s, fd=%d", host, port, fd);
		free(host);
		free(port);
	}
#endif /* DEBUG_PROXY */

	if (!ctx->dstaddrlen) {
		log_err_level_printf(LOG_CRIT, "Child no target address; aborting connection\n");
		evutil_closesocket(fd);
		pxy_conn_term(ctx, 1);
		goto out;
	}

	if (check_fd_usage(
#ifdef DEBUG_PROXY
			ctx
#endif /* DEBUG_PROXY */
			) == -1) {
		evutil_closesocket(fd);
		pxy_conn_term(ctx, 1);
		goto out;
	}

	pxy_conn_child_ctx_t *child_ctx = pxy_conn_ctx_new_child(fd, ctx);
	if (!child_ctx) {
		log_err_level_printf(LOG_CRIT, "Error allocating memory\n");
		evutil_closesocket(fd);
		pxy_conn_term(ctx, 1);
		goto out;
	}

	pxy_conn_attach_child(child_ctx);

	// @attention Do not enable src events here yet, they will be enabled after dst connects
	if (prototcp_setup_src_child(child_ctx) == -1) {
		goto out;
	}

	// @attention fd (child_ctx->fd) is different from child event listener fd (ctx->child_fd)
	ctx->thr->max_fd = max(ctx->thr->max_fd, child_ctx->fd);
	ctx->child_src_fd = child_ctx->fd;
	
	/* create server-side socket and eventbuffer */
	// Children rely on the findings of parent
	child_ctx->protoctx->connectcb(child_ctx);

	if (ctx->term || ctx->enomem) {
		goto out;
	}

	if (OPTS_DEBUG(ctx->global)) {
		log_dbg_printf("Child connecting to [%s]:%s\n", STRORDASH(ctx->dsthost_str), STRORDASH(ctx->dstport_str));
	}

	/* initiate connection, except for the first child conn which uses the parent's srvdst as dst */
	if (child_ctx->dst.bev != ctx->srvdst.bev) {
		if (bufferevent_socket_connect(child_ctx->dst.bev, (struct sockaddr *)&ctx->dstaddr, ctx->dstaddrlen) == -1) {
			pxy_conn_term(ctx, 1);
			goto out;
		}
	}
	
	child_ctx->dst_fd = bufferevent_getfd(child_ctx->dst.bev);
	ctx->child_dst_fd = child_ctx->dst_fd;
	ctx->thr->max_fd = max(ctx->thr->max_fd, child_ctx->dst_fd);
	// Do not return here, but continue and check term/enomem flags below
out:
	// @attention Do not use child_ctx->conn here, child_ctx may be uninitialized
	// @attention Call pxy_conn_free() directly, not pxy_conn_term() here
	// This is our last chance to close and free the conn
	if (ctx->term || ctx->enomem) {
		pxy_conn_free(ctx, ctx->term ? ctx->term_requestor : 1);
	}
}

static int WUNRES NONNULL(1)
pxy_opensock_child(pxy_conn_ctx_t *ctx)
{
	evutil_socket_t fd = socket(ctx->spec->return_addr.ss_family, SOCK_STREAM, IPPROTO_TCP);
	if (fd == -1) {
		log_err_level_printf(LOG_CRIT, "Error from socket(): %s (%i)\n", strerror(errno), errno);
		log_fine_va("Error from socket(): %s (%i)", strerror(errno), errno);
		evutil_closesocket(fd);
		return -1;
	}

	if (evutil_make_socket_nonblocking(fd) == -1) {
		log_err_level_printf(LOG_CRIT, "Error making socket nonblocking: %s (%i)\n", strerror(errno), errno);
		log_fine_va("Error making socket nonblocking: %s (%i)", strerror(errno), errno);
		evutil_closesocket(fd);
		return -1;
	}

	int on = 1;
	if (setsockopt(fd, SOL_SOCKET, SO_KEEPALIVE, (void*)&on, sizeof(on)) == -1) {
		log_err_level_printf(LOG_CRIT, "Error from setsockopt(SO_KEEPALIVE): %s (%i)\n", strerror(errno), errno);
		log_fine_va("Error from setsockopt(SO_KEEPALIVE): %s (%i)", strerror(errno), errno);
		evutil_closesocket(fd);
		return -1;
	}

	if (evutil_make_listen_socket_reuseable(fd) == -1) {
		log_err_level_printf(LOG_CRIT, "Error from setsockopt(SO_REUSABLE): %s (%i)\n", strerror(errno), errno);
		log_fine_va("Error from setsockopt(SO_REUSABLE): %s (%i)", strerror(errno), errno);
		evutil_closesocket(fd);
		return -1;
	}

	if (bind(fd, (struct sockaddr *)&ctx->spec->return_addr, ctx->spec->return_addrlen) == -1) {
		log_err_level_printf(LOG_CRIT, "Error from bind(): %s (%i)\n", strerror(errno), errno);
		log_fine_va("Error from bind(): %s (%i)", strerror(errno), errno);
		evutil_closesocket(fd);
		return -1;
	}
	return fd;
}

int
pxy_setup_child_listener(pxy_conn_ctx_t *ctx)
{
	if (!ctx->divert) {
		// split mode
		return 0;
	}

	// @attention Defer child setup and evcl creation until after parent init is complete, otherwise (1) causes multithreading issues (proxy_listener_acceptcb isrunning on a different thread from the conn, and we only have thrmgr mutex), and (2) we need to clean up less upon errors.
	// Child evcls use the evbase of the parent thread, otherwise we would get multithreading issues.
	// We don't need a privsep call to open a socket for child listener,because listener port of child conns are assigned by the system, hence are from non-privileged range above 1024
	ctx->child_fd = pxy_opensock_child(ctx);
	if (ctx->child_fd < 0) {
		log_err_level_printf(LOG_CRIT, "Error opening child socket: %s (%i)\n", strerror(errno), errno);
		log_fine_va("Error opening child socket: %s (%i)", strerror(errno), errno);
		pxy_conn_term(ctx, 1);
		return -1;
	}
	ctx->thr->max_fd = max(ctx->thr->max_fd, ctx->child_fd);

	// @attention Do not pass NULL as user-supplied pointer
	struct evconnlistener *child_evcl = evconnlistener_new(ctx->thr->evbase, pxy_listener_acceptcb_child, ctx, LEV_OPT_CLOSE_ON_FREE, 1024, ctx->child_fd);
	if (!child_evcl) {
		log_err_level_printf(LOG_CRIT, "Error creating child evconnlistener: %s\n", strerror(errno));
		log_fine_va("Error creating child evconnlistener: %s", strerror(errno));

		// @attention Close child fd separately, because child evcl does not exist yet, hence fd would not be closed by calling pxy_conn_free()
		evutil_closesocket(ctx->child_fd);
		pxy_conn_term(ctx, 1);
		return -1;
	}
	ctx->child_evcl = child_evcl;

	evconnlistener_set_error_cb(child_evcl, proxy_listener_errorcb);

	log_finer_va("Finished setting up child listener, child_fd=%d", ctx->child_fd);

	struct sockaddr_in child_listener_addr;
	socklen_t child_listener_len = sizeof(child_listener_addr);

	if (getsockname(ctx->child_fd, (struct sockaddr *)&child_listener_addr, &child_listener_len) < 0) {
		log_err_level_printf(LOG_CRIT, "Error in getsockname: %s\n", strerror(errno));
		// @attention Do not close the child fd here, because child evcl exists now, hence pxy_conn_free() will close it while freeing child_evcl
		pxy_conn_term(ctx, 1);
		return -1;
	}

	// @todo Children are assumed to be listening on an IPv4 address, should we support IPv6 children?
	char addr[INET_ADDRSTRLEN];
	if (!inet_ntop(AF_INET, &child_listener_addr.sin_addr, addr, INET_ADDRSTRLEN)) {
		pxy_conn_term(ctx, 1);
		return -1;
	}

	// Port may be 4 or 5 chars long
	unsigned int port = ntohs(child_listener_addr.sin_port);
	size_t port_len = port < 10000 ? 4 : 5;

//#ifndef WITHOUT_USERAUTH
//	int user_len = 0;
//	if (ctx->conn_opts->user_auth && ctx->user) {
//		// +1 for comma
//		user_len = strlen(ctx->user) + 1;
//	}
//#endif /* !WITHOUT_USERAUTH */

	// SSLproxy: [127.0.0.1]:34649,[192.168.3.24]:47286,[74.125.206.108]:465,s,soner
	// SSLproxy:        +   + [ + addr         + ] + : + p        + , + [ + srchost_str              + ] + : + srcport_str              + , + [ + dsthost_str              + ] + : + dstport_str              + , + s + , + user
	// SSLPROXY_KEY_LEN + 1 + 1 + strlen(addr) + 1 + 1 + port_len + 1 + 1 + strlen(ctx->srchost_str) + 1 + 1 + strlen(ctx->srcport_str) + 1 + 1 + strlen(ctx->dsthost_str) + 1 + 1 + strlen(ctx->dstport_str) + 1 + 1 + user_len
	ctx->sslproxy_header_len = SSLPROXY_KEY_LEN + strlen(addr) + port_len + strlen(ctx->srchost_str) + strlen(ctx->srcport_str) + strlen(ctx->dsthost_str) + strlen(ctx->dstport_str) + 14
//#ifndef WITHOUT_USERAUTH
//			+ user_len
//#endif /* !WITHOUT_USERAUTH */
			;

	// +1 for NULL
	ctx->sslproxy_header = malloc(ctx->sslproxy_header_len + 1);
	if (!ctx->sslproxy_header) {
		pxy_conn_term(ctx, 1);
		return -1;
	}

	// printf(3): "snprintf() will write at most size-1 of the characters (the size'th character then gets the terminating NULL)"
	// So, +1 for NULL
	if (snprintf(ctx->sslproxy_header, ctx->sslproxy_header_len + 1, "%s [%s]:%u,[%s]:%s,[%s]:%s,%s"
//#ifndef WITHOUT_USERAUTH
//			"%s%s"
//#endif /* !WITHOUT_USERAUTH */
			,
			SSLPROXY_KEY, addr, port, STRORNONE(ctx->srchost_str), STRORNONE(ctx->srcport_str),
			STRORNONE(ctx->dsthost_str), STRORNONE(ctx->dstport_str), ctx->spec->ssl ? "s":"p"
//#ifndef WITHOUT_USERAUTH
//			, user_len ? "," : "", user_len ? ctx->user : ""
//#endif /* !WITHOUT_USERAUTH */
			) < 0) {
		// ctx->sslproxy_header is freed by pxy_conn_ctx_free()
		pxy_conn_term(ctx, 1);
		return -1;
	}
	log_finer_va("sslproxy_header= %s", ctx->sslproxy_header);
	return 0;
}

int
pxy_try_close_conn_end(pxy_conn_desc_t *conn_end, pxy_conn_ctx_t *ctx)
{
	/* if the other end is still open and doesn't have data
	 * to send, close it, otherwise its writecb will close
	 * it after writing what's left in the output buffer */
	if (evbuffer_get_length(bufferevent_get_output(conn_end->bev)) == 0) {
		log_finest("evbuffer_get_length(outbuf) == 0, terminate conn");
		conn_end->zfree(conn_end->bev, ctx);
		conn_end->bev = NULL;
		conn_end->closed = 1;
		return 1;
	}
	return 0;
}

void
pxy_try_disconnect(pxy_conn_ctx_t *ctx, pxy_conn_desc_t *this, pxy_conn_desc_t *other, int is_requestor)
{
	this->closed = 1;
	this->zfree(this->bev, ctx);
	this->bev = NULL;
	if (other->closed) {
		log_finest("other->closed, terminate conn");
		// Uses only ctx to log disconnect, never any of the bevs
		pxy_log_dbg_disconnect(ctx);
		pxy_conn_term(ctx, is_requestor);
	}
}

void
pxy_try_disconnect_child(pxy_conn_child_ctx_t *ctx, pxy_conn_desc_t *this, pxy_conn_desc_t *other)
{
	this->closed = 1;
	this->zfree(this->bev, ctx->conn);
	this->bev = NULL;
	if (other->closed) {
		log_finest("other->closed, terminate conn");
		// Uses only ctx to log disconnect, never any of the bevs
		pxy_log_dbg_disconnect_child(ctx);
		pxy_conn_term_child(ctx);
	}
}

int
pxy_try_consume_last_input(struct bufferevent *bev, pxy_conn_ctx_t *ctx)
{
	/* if there is data pending in the closed connection,
	 * handle it here, otherwise it will be lost. */
	if (evbuffer_get_length(bufferevent_get_input(bev))) {
		log_fine("evbuffer_get_length(inbuf) > 0, terminate conn");

		if (pxy_bev_readcb_preexec_logging_and_stats(bev, ctx) == -1) {
			return -1;
		}
		ctx->protoctx->bev_readcb(bev, ctx);
	}
	return 0;
}

int
pxy_try_consume_last_input_child(struct bufferevent *bev, pxy_conn_child_ctx_t *ctx)
{
	/* if there is data pending in the closed connection,
	 * handle it here, otherwise it will be lost. */
	if (evbuffer_get_length(bufferevent_get_input(bev))) {
		log_fine("evbuffer_get_length(inbuf) > 0, terminate conn");

		if (pxy_bev_readcb_preexec_logging_and_stats_child(bev, ctx) == -1) {
			return -1;
		}
		ctx->protoctx->bev_readcb(bev, ctx);
	}
	return 0;
}

static int NONNULL(1)
pxy_set_dstaddr(pxy_conn_ctx_t *ctx)
{
	if (sys_sockaddr_str((struct sockaddr *)&ctx->dstaddr, ctx->dstaddrlen, &ctx->dsthost_str, &ctx->dstport_str) != 0) {
		// sys_sockaddr_str() may fail due to either malloc() or getnameinfo()
		ctx->enomem = 1;
		pxy_conn_term(ctx, 1);
		return -1;
	}
	return 0;
}

int
pxy_bev_readcb_preexec_logging_and_stats(struct bufferevent *bev, pxy_conn_ctx_t *ctx)
{
	if (bev == ctx->src.bev || bev == ctx->dst.bev) {
		struct evbuffer *inbuf = bufferevent_get_input(bev);
		size_t inbuf_size = evbuffer_get_length(inbuf);

		if (bev == ctx->src.bev) {
            ctx->thrmgr->all_out_bytes += inbuf_size;
			ctx->thr->intif_in_bytes += inbuf_size;
            ctx->out_bytes += inbuf_size;
		} else {
            ctx->thrmgr->all_in_bytes += inbuf_size;
			ctx->thr->intif_out_bytes += inbuf_size;
            ctx->in_bytes += inbuf_size;
		}

		if (WANT_CONTENT_LOG(ctx->conn)) {
			// HTTP content logging at this point may record certain header lines twice, if we have not seen all headers yet
			return pxy_log_content_inbuf(ctx, inbuf, (bev == ctx->src.bev));
		}
	}
	return 0;
}

/*
 * Callback for read events on the up- and downstream connection bufferevents.
 * Called when there is data ready in the input evbuffer.
 */
void
pxy_bev_readcb(struct bufferevent *bev, void *arg)
{
	pxy_conn_ctx_t *ctx = arg;

	if (pxy_bev_readcb_preexec_logging_and_stats(bev, ctx) == -1) {
		goto out;
	}

	if (!ctx->connected) {
		log_err_level(LOG_CRIT, "readcb called when not connected - aborting");
		log_exceptcb();
		return;
	}

	ctx->atime = time(NULL);
	ctx->protoctx->bev_readcb(bev, ctx);

out:
	if (ctx->term || ctx->enomem) {
		pxy_conn_free(ctx, ctx->term ? ctx->term_requestor : (bev == ctx->src.bev));
	}
}

int
pxy_bev_readcb_preexec_logging_and_stats_child(struct bufferevent *bev, pxy_conn_child_ctx_t *ctx)
{
	struct evbuffer *inbuf = bufferevent_get_input(bev);
	size_t inbuf_size = evbuffer_get_length(inbuf);

	if (bev == ctx->src.bev) {
		ctx->conn->thr->extif_out_bytes += inbuf_size;
	} else {
		ctx->conn->thr->extif_in_bytes += inbuf_size;
	}

	if (WANT_CONTENT_LOG(ctx->conn)) {
		return pxy_log_content_inbuf(ctx->conn, inbuf, (bev == ctx->src.bev));
	}
	return 0;
}

void
pxy_bev_readcb_child(struct bufferevent *bev, void *arg)
{
	pxy_conn_child_ctx_t *ctx = arg;

	if (pxy_bev_readcb_preexec_logging_and_stats_child(bev, ctx) == -1) {
		goto out;
	}

	if (!ctx->connected) {
		log_err_level(LOG_CRIT, "readcb called when not connected - aborting");
		log_exceptcb();
		return;
	}

	ctx->conn->atime = time(NULL);
	ctx->protoctx->bev_readcb(bev, ctx);

out:
	if (ctx->conn->term || ctx->conn->enomem) {
		pxy_conn_free(ctx->conn, ctx->conn->term ? ctx->conn->term_requestor : (bev == ctx->src.bev));
		return;
	}

	if (ctx->term) {
		pxy_conn_free_child(ctx);
	}
}

/*
 * Callback for write events on the up- and downstream connection bufferevents.
 * Called when either all data from the output evbuffer has been written,
 * or if the outbuf is only half full again after having been full.
 */
void
pxy_bev_writecb(struct bufferevent *bev, void *arg)
{
	pxy_conn_ctx_t *ctx = arg;

	ctx->atime = time(NULL);
	ctx->protoctx->bev_writecb(bev, ctx);

	if (ctx->term || ctx->enomem) {
		pxy_conn_free(ctx, ctx->term ? ctx->term_requestor : (bev == ctx->src.bev));
	}
}

void
pxy_bev_writecb_child(struct bufferevent *bev, void *arg)
{
	pxy_conn_child_ctx_t *ctx = arg;

	ctx->conn->atime = time(NULL);
	ctx->protoctx->bev_writecb(bev, ctx);

	if (ctx->conn->term || ctx->conn->enomem) {
		pxy_conn_free(ctx->conn, ctx->conn->term ? ctx->conn->term_requestor : (bev == ctx->src.bev));
		return;
	}

	if (ctx->term) {
		pxy_conn_free_child(ctx);
	}
}

static int NONNULL(1,3)
pxy_bev_eventcb_postexec_logging_and_stats(struct bufferevent *bev, short events, pxy_conn_ctx_t *ctx)
{
	if (ctx->term || ctx->enomem) {
		return -1;
	}

	if (events & BEV_EVENT_CONNECTED) {
		// Passthrough proto does its own connect logging
		if (ctx->proto != PROTO_PASSTHROUGH) {
			if (bev == ctx->src.bev) {
				// @todo When do we reach here? If proto is autossl? Otherwise, src is connected in acceptcb.
				pxy_log_connect_src(ctx);
			} else if (ctx->connected) {
				if (pxy_prepare_logging(ctx) == -1) {
					return -1;
				}
				// Doesn't log connect if proto is http, http proto does its own connect logging
				pxy_log_connect_srvdst(ctx);
			}
		}

		if (bev == ctx->srvdst.bev) {
			ctx->thr->max_load = max(ctx->thr->max_load, ctx->thr->load);
			ctx->thr->max_fd = max(ctx->thr->max_fd, ctx->fd);

			// src and other fd stats are collected in acceptcb functions
			ctx->srvdst_fd = bufferevent_getfd(ctx->srvdst.bev);
			ctx->thr->max_fd = max(ctx->thr->max_fd, ctx->srvdst_fd);

			// Passthrough proto may have a NULL dst.bev
			if (ctx->dst.bev) {
				ctx->dst_fd = bufferevent_getfd(ctx->dst.bev);
				ctx->thr->max_fd = max(ctx->thr->max_fd, ctx->dst_fd);
			}
		}
	}
	return 0;
}

/*
 * Callback for meta events on the up- and downstream connection bufferevents.
 * Called when EOF has been reached, a connection has been made, and on errors.
 */
void
pxy_bev_eventcb(struct bufferevent *bev, short events, void *arg)
{
	pxy_conn_ctx_t *ctx = arg;

	ctx->atime = time(NULL);

	if (events & BEV_EVENT_ERROR) {
		log_err_printf("Client-side BEV_EVENT_ERROR\n");
		ctx->thr->errors++;
	}
//    pxy_bev_eventcb_postexec_logging_and_stats(bev, events, ctx);
	ctx->protoctx->bev_eventcb(bev, events, arg);

	pxy_bev_eventcb_postexec_logging_and_stats(bev, events, ctx);

	// Logging functions may set term or enomem too
	// EOF eventcb may call readcb possibly causing enomem
	if (ctx->term || ctx->enomem) {
		pxy_conn_free(ctx, ctx->term ? ctx->term_requestor : (bev == ctx->src.bev));
	}
}

void
pxy_bev_eventcb_postexec_stats_child(short events, pxy_conn_child_ctx_t *ctx)
{
	if (events & BEV_EVENT_CONNECTED) {
		ctx->conn->thr->max_fd = max(ctx->conn->thr->max_fd, max(bufferevent_getfd(ctx->src.bev), bufferevent_getfd(ctx->dst.bev)));
	}
}

void
pxy_bev_eventcb_child(struct bufferevent *bev, short events, void *arg)
{
	pxy_conn_child_ctx_t *ctx = arg;

	ctx->conn->atime = time(NULL);

	if (events & BEV_EVENT_ERROR) {
		log_err_printf("Server-side BEV_EVENT_ERROR\n");
		ctx->conn->thr->errors++;
	}

	// All child conns including this one will be freed if this child engages passthrough mode
	// So save the vars used after eventcb call
	pxy_conn_ctx_t *conn = ctx->conn;
	unsigned int term_requestor = bev == ctx->src.bev;

	ctx->protoctx->bev_eventcb(bev, events, arg);

	// EOF eventcb may call readcb possibly causing enomem
	if (conn->term || conn->enomem) {
		pxy_conn_free(conn, conn->term ? conn->term_requestor : term_requestor);
		return;
	}

	if (conn->children) {
		if (ctx->term) {
			pxy_conn_free_child(ctx);
			return;
		}

		pxy_bev_eventcb_postexec_stats_child(events, ctx);
	}
}

static filter_action_t * NONNULL(1,2)
pxy_conn_filter_match_ip(pxy_conn_ctx_t *ctx, filter_list_t *list)
{
	filter_site_t *site = filter_site_find(list->ip_btree, list->ip_acm, list->ip_all, ctx->dsthost_str);
	if (!site)
		return NULL;

	log_fine_va("Found site (line=%d): %s for %s:%s, %s:%s", site->action.line_num, site->site,
		STRORDASH(ctx->srchost_str), STRORDASH(ctx->srcport_str), STRORDASH(ctx->dsthost_str), STRORDASH(ctx->dstport_str));

	// Port spec determines the precedence of a site rule, unless the rule does not have any port
	if (!site->port_btree && !site->port_acm && (site->action.precedence < ctx->filter_precedence)) {
		log_finest_va("Rule precedence lower than conn filter precedence %d < %d (line=%d): %s, %s", site->action.precedence, ctx->filter_precedence, site->action.line_num, site->site, ctx->dsthost_str);
		return NULL;
	}

#ifdef DEBUG_PROXY
	if (site->all_sites)
		log_finest_va("Match all dst (line=%d): %s, %s", site->action.line_num, site->site, ctx->dsthost_str);
	else if (site->exact)
		log_finest_va("Match exact with dst (line=%d): %s, %s", site->action.line_num, site->site, ctx->dsthost_str);
	else
		log_finest_va("Match substring in dst (line=%d): %s, %s", site->action.line_num, site->site, ctx->dsthost_str);
#endif /* DEBUG_PROXY */

	filter_action_t *port_action = pxy_conn_filter_port(ctx, site);
	if (port_action)
		return port_action;

	return &site->action;
}

static filter_action_t * NONNULL(1,2)
pxy_conn_dsthost_filter(pxy_conn_ctx_t *ctx, filter_list_t *list)
{
	if (ctx->dsthost_str) {
		filter_action_t *action;
		if ((action = pxy_conn_filter_match_ip(ctx, list)))
			return pxy_conn_set_filter_action(action, NULL
#ifdef DEBUG_PROXY
					, ctx, ctx->dsthost_str, NULL
#endif /* DEBUG_PROXY */
					);

		log_finest_va("No filter match with ip: %s:%s, %s:%s",
			STRORDASH(ctx->srchost_str), STRORDASH(ctx->srcport_str), STRORDASH(ctx->dsthost_str), STRORDASH(ctx->dstport_str));
	}
	return NULL;
}

int
pxy_conn_apply_filter(pxy_conn_ctx_t *ctx, unsigned int defer_action)
{
	int rv = 0;
	filter_action_t *a;
	if ((a = pxy_conn_filter(ctx, pxy_conn_dsthost_filter))) {
		unsigned int action = pxy_conn_translate_filter_action(ctx, a);

		ctx->filter_precedence = action & FILTER_PRECEDENCE;

		// If we reach here, the matching filtering rule must have a higher precedence
		// Override any deferred action, if the current rule action is not match
		// Match action cannot override other filter actions

		if (action & FILTER_ACTION_DIVERT) {
			ctx->deferred_action = FILTER_ACTION_NONE;
			ctx->divert = 1;
		}
		else if (action & FILTER_ACTION_SPLIT) {
			ctx->deferred_action = FILTER_ACTION_NONE;
			ctx->divert = 0;
		}
		else if (action & FILTER_ACTION_PASS) {
			if (defer_action & FILTER_ACTION_PASS) {
				log_fine("Deferring pass action");
				ctx->deferred_action = FILTER_ACTION_PASS;
			}
			else {
				ctx->deferred_action = FILTER_ACTION_NONE;
				protopassthrough_engage(ctx);
				ctx->pass = 1;
				rv = 1;
			}
		}
		else if (action & FILTER_ACTION_BLOCK) {
			if (defer_action & FILTER_ACTION_BLOCK) {
				// This block action should override any deferred pass action,
				// because the current rule must have a higher precedence
				log_fine("Deferring block action");
				ctx->deferred_action = FILTER_ACTION_BLOCK;
			}
			else {
				pxy_conn_term(ctx, 1);
				rv = 1;
			}
		}
		//else { /* FILTER_ACTION_MATCH */ }

		// Filtering rules at higher precedence can enable/disable logging
		if (action & FILTER_LOG_CONNECT)
			ctx->log_connect = 1;
		else if (action & FILTER_LOG_NOCONNECT)
			ctx->log_connect = 0;
		if (action & FILTER_LOG_MASTER)
			ctx->log_master = 1;
		else if (action & FILTER_LOG_NOMASTER)
			ctx->log_master = 0;
		if (action & FILTER_LOG_CERT)
			ctx->log_cert = 1;
		else if (action & FILTER_LOG_NOCERT)
			ctx->log_cert = 0;
		if (action & FILTER_LOG_CONTENT)
			ctx->log_content = 1;
		else if (action & FILTER_LOG_NOCONTENT)
			ctx->log_content = 0;
		if (action & FILTER_LOG_PCAP)
			ctx->log_pcap = 1;
		else if (action & FILTER_LOG_NOPCAP)
			ctx->log_pcap = 0;

		if (a->conn_opts)
			ctx->conn_opts = a->conn_opts;
	}
	return rv;
}

/*
 * Complete the connection.  This gets called after finding out where to connect to.
 完成连接。在找到连接到哪里之后，将调用这个函数。
 */
void
pxy_conn_connect(pxy_conn_ctx_t *ctx)
{
	log_finest("ENTER");

	if (!ctx->dstaddrlen) {
		log_err_level_printf(LOG_CRIT, "No target address; aborting connection\n");
		evutil_closesocket(ctx->fd);
		pxy_conn_ctx_free(ctx, 1);
		return;
	}

	// This function may be called more than once for the same conn
	// So, set the dstaddr only once
    // 对于同一个conn，这个函数可以被调用多次。因此，只设置dstaddr一次
	if (!ctx->dsthost_str && (pxy_set_dstaddr(ctx) == -1)) {
		return;
	}

	// Apply dstip filter now, so we can replace the SSL/TLS configuration of the conn with the one in the matching filtering rule
	// It does not matter if this function is called more than once for the same conn
	// Defer any pass action until srvdst connected
	// Defer any block action until HTTP filter application or the first src readcb of non-http proto
	if (pxy_conn_apply_filter(ctx, FILTER_ACTION_PASS | FILTER_ACTION_BLOCK)) {
		// We never reach here, since we defer pass and block actions
		return;
	}

	if (OPTS_DEBUG(ctx->global)) {
		log_dbg_printf("Connecting to [%s]:%s\n", ctx->dsthost_str, ctx->dstport_str); // 调试的时候，得好好看看这个日志，为什么我会觉得代理地址就是目标地址呢 ？不应该
	}

	if (ctx->protoctx->connectcb(ctx) == -1) {
		// The return value of -1 from connectcb indicates that there was a fatal error before event callbacks were set, so we can terminate the connection.
		// Otherwise, it is up to the event callbacks to terminate the connection.
		if (ctx->term || ctx->enomem) {
			pxy_conn_free(ctx, ctx->term ? ctx->term_requestor : 1);
			return;
		}
	}
    ctx->connect_s = current_time();
	if (bufferevent_socket_connect(ctx->srvdst.bev, (struct sockaddr *)&ctx->dstaddr, ctx->dstaddrlen) == -1) {
		log_err_level(LOG_CRIT, "bufferevent_socket_connect for srvdst failed");
		pxy_conn_free(ctx, ctx->term ? ctx->term_requestor : 1);
	}
}

//#ifndef WITHOUT_USERAUTH
//#if defined(__OpenBSD__) || defined(__linux__)
//int
//pxy_is_listuser(userlist_t *list, const char *user
//#ifdef DEBUG_PROXY
//	, pxy_conn_ctx_t *ctx, const char *listname
//#endif /* DEBUG_PROXY */
//	)
//{
//	while (list) {
//		if (equal(user, list->user)) {
//			log_finest_va("User %s in %s", user, listname);
//			return 1;
//		}
//		list = list->next;
//	}
//	return 0;
//}
//
//void
//pxy_classify_user(pxy_conn_ctx_t *ctx)
//{
//	if (ctx->spec->opts->passusers && pxy_is_listuser(ctx->spec->opts->passusers, ctx->user
//#ifdef DEBUG_PROXY
//			, ctx, "PassUsers"
//#endif /* DEBUG_PROXY */
//			)) {
//		log_fine_va("User %s in PassUsers; engaging passthrough mode", ctx->user);
//		protopassthrough_engage(ctx);
//	} else if (ctx->spec->opts->divertusers && !pxy_is_listuser(ctx->spec->opts->divertusers, ctx->user
//#ifdef DEBUG_PROXY
//			, ctx, "DivertUsers"
//#endif /* DEBUG_PROXY */
//			)) {
//		log_fine_va("User %s not in DivertUsers; terminating connection", ctx->user);
//		pxy_conn_term(ctx, 1);
//	}
//}
//
//static void
//identify_user(UNUSED evutil_socket_t fd, UNUSED short what, void *arg)
//{
//	pxy_conn_ctx_t *ctx = arg;
//
//	log_finest("ENTER");
//
//	if (ctx->ev) {
//		event_free(ctx->ev);
//		ctx->ev = NULL;
//	}
//
//	if (ctx->identify_user_count++ >= 50) {
//		log_finest("Cannot get conn user");
//		goto redirect;
//	} else {
//		int rc;
//
//		// @todo Do we really need to reset the stmt, as we always reset while returning?
//		sqlite3_reset(ctx->thr->get_user);
//		sqlite3_bind_text(ctx->thr->get_user, 1, ctx->srchost_str, -1, NULL);
//		rc = sqlite3_step(ctx->thr->get_user);
//
//		// Retry in case we cannot acquire db file or database: SQLITE_BUSY or SQLITE_LOCKED respectively
//		if (rc == SQLITE_BUSY || rc == SQLITE_LOCKED) {
//			log_finest_va("User db busy or locked, retrying, count=%d", ctx->identify_user_count);
//
//			// Do not forget to reset sqlite stmt, or else the userdb may remain busy/locked
//			sqlite3_reset(ctx->thr->get_user);
//
//			ctx->ev = event_new(ctx->thr->evbase, -1, 0, identify_user, ctx);
//			if (!ctx->ev)
//				goto memout;
//			struct timeval retry_delay = {0, 100};
//			if (event_add(ctx->ev, &retry_delay) == -1)
//				goto memout;
//			return;
//		} else if (rc == SQLITE_DONE) {
//			log_finest("Conn has no user");
//			goto redirect;
//		} else if (rc == SQLITE_ROW) {
//			char *ether = (char *)sqlite3_column_text(ctx->thr->get_user, 1);
//			if (strncasecmp(ether, ctx->ether, 17)) {
//				log_finest_va("Ethernet addresses do not match, db=%s, arp cache=%s", ether, ctx->ether);
//				goto redirect;
//			}
//
//			log_finest_va("Passed ethernet address test, %s", ether);
//
//			ctx->idletime = time(NULL) - sqlite3_column_int(ctx->thr->get_user, 2);
//			if (ctx->idletime > ctx->conn_opts->user_timeout) {
//				log_finest_va("User entry timed out, idletime=%u", ctx->idletime);
//				goto redirect;
//			}
//
//			log_finest_va("Passed timeout test, idletime=%u", ctx->idletime);
//
//			ctx->user = strdup((char *)sqlite3_column_text(ctx->thr->get_user, 0));
//			// Desc is needed for filtering
//			ctx->desc = strdup((char *)sqlite3_column_text(ctx->thr->get_user, 3));
//			if (!ctx->user || !ctx->desc) {
//				goto memout;
//			}
//
//			log_finest_va("Conn user=%s, desc=%s", ctx->user, ctx->desc);
//
//			ctx->protoctx->classify_usercb(ctx);
//		}
//	}
//	log_finest("Passed user identification");
//redirect:
//	sqlite3_reset(ctx->thr->get_user);
//
//	if (ctx->ev) {
//		event_free(ctx->ev);
//		ctx->ev = NULL;
//	}
//	return;
//
//memout:
//	log_err_level_printf(LOG_CRIT, "Aborting connection user identification!\n");
//	pxy_conn_term(ctx, 1);
//}
//#endif /* __OpenBSD__ || __linux__ */
//
//#ifdef __linux__
//// Assume proc filesystem support
//#define ARP_CACHE "/proc/net/arp"
//
///*
// * We do not care about multiple matches or expiration status of arp cache entries on Linux.
// */
//static int NONNULL(1)
//get_client_ether(pxy_conn_ctx_t *ctx)
//{
//	int rv = 0;
//
//	FILE *arp_cache = fopen(ARP_CACHE, "r");
//	if (!arp_cache) {
//		log_err_level_printf(LOG_CRIT, "Failed to open arp cache: \"" ARP_CACHE "\"\n");
//		return -1;
//	}
//
//	// Skip the first line, which contains the header
//	char header[1024];
//	if (!fgets(header, sizeof(header), arp_cache)) {
//		log_err_level_printf(LOG_CRIT, "Failed to skip arp cache header\n");
//		rv = -1;
//		goto out;
//	}
//
//	char ip[46], ether[18];
//	//192.168.0.1     0x1         0x2         00:50:56:2c:bf:e0     *        enp3s0f1
//	while (fscanf(arp_cache, "%45s %*s %*s %17s %*s %*s", ip, ether) == 2) {
//		if (!strncasecmp(ip, ctx->srchost_str, 45)) {
//			log_finest_va("Arp entry for %s: %s", ip, ether);
//			ctx->ether = strdup(ether);
//			rv = 1;
//			goto out;
//		}
//	}
//out:
//	fclose(arp_cache);
//	return rv;
//}
//#endif /* __linux__ */
//
//#ifdef __OpenBSD__
///*
// * This is a modified version of the same function from OpenBSD sources,
// * which has a 3-clause BSD license.
// */
//static char *
//ether_str(struct sockaddr_dl *sdl)
//{
//	char hbuf[NI_MAXHOST];
//	u_char *cp;
//
//	if (sdl->sdl_alen) {
//		cp = (u_char *)LLADDR(sdl);
//		snprintf(hbuf, sizeof(hbuf), "%02x:%02x:%02x:%02x:%02x:%02x",
//			cp[0], cp[1], cp[2], cp[3], cp[4], cp[5]);
//		return strdup(hbuf);
//	} else {
//		return NULL;
//	}
//}
//
///*
// * This is a modified version of a similar function from OpenBSD sources,
// * which has a 3-clause BSD license.
// */
//static int NONNULL(2)
//get_client_ether(in_addr_t addr, pxy_conn_ctx_t *ctx)
//{
//	int mib[7];
//	size_t needed;
//	char *lim, *buf = NULL, *next;
//	struct rt_msghdr *rtm;
//	struct sockaddr_inarp *sin;
//	struct sockaddr_dl *sdl;
//	int found_entry = 0;
//	int rdomain = getrtable();
//
//	mib[0] = CTL_NET;
//	mib[1] = PF_ROUTE;
//	mib[2] = 0;
//	mib[3] = AF_INET;
//	mib[4] = NET_RT_FLAGS;
//	mib[5] = RTF_LLINFO;
//	mib[6] = rdomain;
//	while (1) {
//		if (sysctl(mib, 7, NULL, &needed, NULL, 0) == -1) {
//			log_err_level_printf(LOG_WARNING, "route-sysctl-estimate\n");
//		}
//		if (needed == 0) {
//			return found_entry;
//		}
//		if ((buf = realloc(buf, needed)) == NULL) {
//			return -1;
//		}
//		if (sysctl(mib, 7, buf, &needed, NULL, 0) == -1) {
//			if (errno == ENOMEM)
//				continue;
//			log_finest("actual retrieval of routing table");
//		}
//		lim = buf + needed;
//		break;
//	}
//
//	int expired = 0;
//	int incomplete = 0;
//	for (next = buf; next < lim; next += rtm->rtm_msglen) {
//		rtm = (struct rt_msghdr *)next;
//		if (rtm->rtm_version != RTM_VERSION)
//			continue;
//		sin = (struct sockaddr_inarp *)(next + rtm->rtm_hdrlen);
//		sdl = (struct sockaddr_dl *)(sin + 1);
//		if (addr) {
//			if (addr != sin->sin_addr.s_addr)
//				continue;
//			found_entry++;
//		}
//
//		char *expire = NULL;
//		if (rtm->rtm_flags & (RTF_PERMANENT_ARP | RTF_LOCAL)) {
//			expire = "permanent";
//		} else if (rtm->rtm_rmx.rmx_expire == 0) {
//			expire = "static";
//		} else if (rtm->rtm_rmx.rmx_expire > time(NULL)) {
//			expire = "active";
//		} else {
//			expire = "expired";
//			expired++;
//		}
//
//		char *ether = ether_str(sdl);
//		if (ether) {
//			// Record the first unexpired complete entry
//			if (!ctx->ether && (found_entry - expired) == 1) {
//				log_finest_va("Arp entry for %s: %s", inet_ntoa(sin->sin_addr), ether);
//				// Dup before assignment because we free local var ether below
//				ctx->ether = strdup(ether);
//				// Do not care about multiple matches, return immediately
//				free(ether);
//				goto out;
//			}
//		} else {
//			incomplete++;
//		}
//
//		log_finest_va("Arp entry %u for %s: %s (%s)", found_entry, inet_ntoa(sin->sin_addr), ether ? ether : "incomplete", expire);
//
//		if (ether) {
//			free(ether);
//		}
//	}
//out:
//	free(buf);
//	return found_entry - expired - incomplete;
//}
//#endif /* __OpenBSD__ */
//
//void
//pxy_userauth(pxy_conn_ctx_t *ctx)
//{
//	if (ctx->conn_opts->user_auth && !ctx->user) {
//#if defined(__OpenBSD__) || defined(__linux__)
//		int ec = get_client_ether(
//#if defined(__OpenBSD__)
//			((struct sockaddr_in *)&ctx->srcaddr)->sin_addr.s_addr,
//#endif /* __OpenBSD__ */
//			ctx);
//		if (ec == 1) {
//			identify_user(-1, 0, ctx);
//			return;
//		} else if (ec == 0) {
//			log_err_level_printf(LOG_CRIT, "Cannot find ethernet address of client IP address\n");
//		} else if (ec > 1) {
//			// get_client_ether() does not return multiple matches, but keep this in case a future version does
//			log_err_level_printf(LOG_CRIT, "Multiple ethernet addresses for the same client IP address\n");
//		} else {
//			// ec == -1
//			log_err_level_printf(LOG_CRIT, "Aborting connection setup (out of memory)!\n");
//		}
//#endif /* __OpenBSD__ || __linux__ */
//		log_err_level_printf(LOG_CRIT, "Aborting connection setup (user auth)!\n");
//		pxy_conn_term(ctx, 1);
//	}
//}
//#endif /* !WITHOUT_USERAUTH */

int
pxy_conn_apply_deferred_block_action(pxy_conn_ctx_t *ctx)
{
	if (ctx->deferred_action & FILTER_ACTION_BLOCK) {
		log_fine("Applying deferred block action");
		pxy_conn_term(ctx, 1);
		return 1;
	}
	return 0;
}

unsigned int
pxy_conn_translate_filter_action(pxy_conn_ctx_t *ctx, filter_action_t *a)
{
	unsigned int action = FILTER_ACTION_NONE;

	if (a->divert) {
		action = FILTER_ACTION_DIVERT;
	}
	else if (a->split) {
		action = FILTER_ACTION_SPLIT;
	}
	else if (a->pass) {
		// Ignore pass action if already in passthrough mode
		if (!ctx->pass) {
			action = FILTER_ACTION_PASS;
		}
	}
	else if (a->block) {
		action = FILTER_ACTION_BLOCK;
	}
	else if (a->match) {
		action = FILTER_ACTION_MATCH;
	}

	// Multiple log actions can be defined, hence no 'else'
	// 0: don't change, 1: disable, 2: enable
	if (a->log_connect) {
		action |= (a->log_connect % 2) ? FILTER_LOG_NOCONNECT : FILTER_LOG_CONNECT;
	}
	if (a->log_master) {
		action |= (a->log_master % 2) ? FILTER_LOG_NOMASTER : FILTER_LOG_MASTER;
	}
	if (a->log_cert) {
		action |= (a->log_cert % 2) ? FILTER_LOG_NOCERT : FILTER_LOG_CERT;
	}
	if (a->log_content) {
		action |= (a->log_content % 2) ? FILTER_LOG_NOCONTENT : FILTER_LOG_CONTENT;
	}
	if (a->log_pcap) {
		action |= (a->log_pcap % 2) ? FILTER_LOG_NOPCAP : FILTER_LOG_PCAP;
	}

	action |= a->precedence;

	return action;
}

filter_action_t *
pxy_conn_set_filter_action(filter_action_t *a1, filter_action_t *a2
#ifdef DEBUG_PROXY
	, pxy_conn_ctx_t *ctx, char *s1, char *s2
#endif /* DEBUG_PROXY */
	)
{
	filter_action_t *a;
#ifdef DEBUG_PROXY
	char *site;
#endif /* DEBUG_PROXY */

	// a1 has precedence over a2, unless a2's precedence is higher
	if (!a1 || (a1 &&  a2 && (a1->precedence < a2->precedence))) {
		a = a2;
#ifdef DEBUG_PROXY
		site = s2;
		if (a1 &&  a2 && (a1->precedence < a2->precedence))
			log_finest_va("Rule 2 has higher precedence than rule 1: %d > %d (line=%d, %d), %s, %s", a2->precedence, a1->precedence, a2->line_num, a1->line_num, s2, s1);
#endif /* DEBUG_PROXY */
	} else {
		a = a1;
#ifdef DEBUG_PROXY
		site = s1;
#endif /* DEBUG_PROXY */
	}

#ifdef DEBUG_PROXY
	if (a->divert) {
		log_fine_va("Filter divert action for %s, precedence %d (line=%d)", site, a->precedence, a->line_num);
	}
	else if (a->split) {
		log_fine_va("Filter split action for %s, precedence %d (line=%d)", site, a->precedence, a->line_num);
	}
	else if (a->pass) {
		// Ignore pass action if already in passthrough mode
		if (!ctx->pass) {
			log_fine_va("Filter pass action for %s, precedence %d (line=%d)", site, a->precedence, a->line_num);
		}
	}
	else if (a->block) {
		log_fine_va("Filter block action for %s, precedence %d (line=%d)", site, a->precedence, a->line_num);
	}
	else if (a->match) {
		log_fine_va("Filter match action for %s, precedence %d (line=%d)", site, a->precedence, a->line_num);
	}

	// Multiple log actions can be defined, hence no 'else'
	// 0: don't change, 1: disable, 2: enable
	if (a->log_connect) {
		log_fine_va("Filter %s connect log for %s, precedence %d (line=%d)", a->log_connect % 2 ? "disable" : "enable", site, a->precedence, a->line_num);
	}
	if (a->log_master) {
		log_fine_va("Filter %s master log for %s, precedence %d (line=%d)", a->log_master % 2 ? "disable" : "enable", site, a->precedence, a->line_num);
	}
	if (a->log_cert) {
		log_fine_va("Filter %s cert log for %s, precedence %d (line=%d)", a->log_cert % 2 ? "disable" : "enable", site, a->precedence, a->line_num);
	}
	if (a->log_content) {
		log_fine_va("Filter %s content log for %s, precedence %d (line=%d)", a->log_content % 2 ? "disable" : "enable", site, a->precedence, a->line_num);
	}
	if (a->log_pcap) {
		log_fine_va("Filter %s pcap log for %s, precedence %d (line=%d)", a->log_pcap % 2 ? "disable" : "enable", site, a->precedence, a->line_num);
	}
#endif /* DEBUG_PROXY */
	return a;
}

static int NONNULL(1,2)
pxy_conn_filter_match_port(pxy_conn_ctx_t *ctx, filter_port_t *port)
{
	if (port->action.precedence < ctx->filter_precedence) {
		log_finest_va("Rule port precedence lower than conn filter precedence %d < %d (line=%d): %s, %s", port->action.precedence, ctx->filter_precedence, port->action.line_num, port->port, ctx->dsthost_str);
		return 0;
	}

#ifdef DEBUG_PROXY
	if (port->all_ports)
		log_finest_va("Match all dst ports (line=%d): %s, %s", port->action.line_num, port->port, ctx->dstport_str);
	else if (port->exact)
		log_finest_va("Match exact with dst port (line=%d): %s, %s", port->action.line_num, port->port, ctx->dstport_str);
	else
		log_finest_va("Match substring in dst port (line=%d): %s, %s", port->action.line_num, port->port, ctx->dstport_str);
#endif /* DEBUG_PROXY */

	return 1;
}

filter_action_t *
pxy_conn_filter_port(pxy_conn_ctx_t *ctx, filter_site_t *site)
{
	filter_port_t *port = filter_port_find(site, ctx->dstport_str);
	if (port) {
		log_fine_va("Found port (line=%d): %s for %s:%s, %s:%s", port->action.line_num, port->port,
			STRORDASH(ctx->srchost_str), STRORDASH(ctx->srcport_str), STRORDASH(ctx->dsthost_str), STRORDASH(ctx->dstport_str));
		if (pxy_conn_filter_match_port(ctx, port))
			return &port->action;
	}
	else
		log_finest_va("No filter match with port: %s:%s, %s:%s",
			STRORDASH(ctx->srchost_str), STRORDASH(ctx->srcport_str), STRORDASH(ctx->dsthost_str), STRORDASH(ctx->dstport_str));

	return NULL;
}

//#ifndef WITHOUT_USERAUTH
//static filter_action_t *
//pxy_conn_filter_user(pxy_conn_ctx_t *ctx, proto_filter_func_t filtercb, filter_user_t *user)
//{
//	filter_action_t * action = NULL;
//	if (user) {
//		if (ctx->desc) {
//			log_finest_va("Searching user keyword exact: %s, %s", ctx->user, ctx->desc);
//			filter_desc_t *keyword = filter_desc_exact_match(user->desc_btree, ctx->desc);
//			if (keyword && (action = filtercb(ctx, keyword->list))) {
//				return action;
//			}
//
//			log_finest_va("Searching user keyword substring: %s, %s", ctx->user, ctx->desc);
//			keyword = filter_desc_substring_match(user->desc_acm, ctx->desc);
//			if (keyword && (action = filtercb(ctx, keyword->list))) {
//				return action;
//			}
//		}
//		if ((action = filtercb(ctx, user->list))) {
//			return action;
//		}
//	}
//	return action;
//}
//#endif /* !WITHOUT_USERAUTH */

filter_action_t *
pxy_conn_filter(pxy_conn_ctx_t *ctx, proto_filter_func_t filtercb)
{
	filter_action_t * action = NULL;

	filter_t *filter = ctx->spec->opts->filter;
	if (filter) {
//#ifndef WITHOUT_USERAUTH
//		if (ctx->user) {
//			log_finest_va("Searching user exact: %s", ctx->user);
//			filter_user_t *user = filter_user_exact_match(filter->user_btree, ctx->user);
//			if ((action = pxy_conn_filter_user(ctx, filtercb, user)))
//				return action;
//
//			log_finest_va("Searching user substring: %s", ctx->user);
//			user = filter_user_substring_match(filter->user_acm, ctx->user);
//			if ((action = pxy_conn_filter_user(ctx, filtercb, user)))
//				return action;
//
//			if (ctx->desc) {
//				log_finest_va("Searching keyword exact: %s", ctx->desc);
//				filter_desc_t *keyword = filter_desc_exact_match(filter->desc_btree, ctx->desc);
//				if (keyword && (action = filtercb(ctx, keyword->list))) {
//					return action;
//				}
//
//				log_finest_va("Searching keyword substring: %s, %s", ctx->user, ctx->desc);
//				keyword = filter_desc_substring_match(filter->desc_acm, ctx->desc);
//				if (keyword && (action = filtercb(ctx, keyword->list))) {
//					return action;
//				}
//			}
//
//			log_finest("Searching all_user");
//			if (filter->all_user && (action = filtercb(ctx, filter->all_user))) {
//				return action;
//			}
//		}
//#endif /* !WITHOUT_USERAUTH */
		if (ctx->srchost_str) {
			log_finest_va("Searching ip exact: %s", ctx->srchost_str);
			filter_ip_t *ip = filter_ip_exact_match(filter->ip_btree, ctx->srchost_str);
			if (ip && (action = filtercb(ctx, ip->list))) {
				return action;
			}

			log_finest_va("Searching ip substring: %s", ctx->srchost_str);
			ip = filter_ip_substring_match(filter->ip_acm, ctx->srchost_str);
			if (ip && (action = filtercb(ctx, ip->list))) {
				return action;
			}
		}

		log_finest("Searching all");
		if (filter->all && (action = filtercb(ctx, filter->all))) {
			return action;
		}
	}
	return action;
}

evutil_socket_t get_tcp_socket_for_host(const char *hostname, ev_uint16_t port)
{
    char port_buf[6];
    struct evutil_addrinfo hints;
    struct evutil_addrinfo *answer = NULL;
    int err;
    evutil_socket_t sock;

    /* Convert the port to decimal. */
    evutil_snprintf(port_buf, sizeof(port_buf), "%d", (int)port);

    /* Build the hints to tell getaddrinfo how to act. */
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_UNSPEC; /* v4 or v6 is fine. */
    hints.ai_socktype = SOCK_STREAM;
    hints.ai_protocol = IPPROTO_TCP; /* We want a TCP socket */
    /* Only return addresses we can use. */
    hints.ai_flags = EVUTIL_AI_ADDRCONFIG;

    /* Look up the hostname. */
    err = evutil_getaddrinfo(hostname, port_buf, &hints, &answer);
    if (err != 0) {
        fprintf(stderr, "Error while resolving '%s': %s", hostname, evutil_gai_strerror(err));
        return -1;
    }

    /* If there was no error, we should have at least one answer. */
    assert(answer);
    /* Just use the first answer. */
    sock = socket(answer->ai_family,
                  answer->ai_socktype,
                  answer->ai_protocol);
    if (sock < 0)
        return -1;
    if (connect(sock, answer->ai_addr, answer->ai_addrlen)) {
        /* Note that we're doing a blocking connect in this function.
         * If this were nonblocking, we'd need to treat some errors
         * (like EINTR and EAGAIN) specially. */
        EVUTIL_CLOSESOCKET(sock);
        return -1;
    }

    return sock;
}


int
pxy_conn_init(pxy_conn_ctx_t *ctx)
{
	log_finest("ENTER");

	pxy_thr_attach(ctx);

	ctx->ctime = time(NULL);
	ctx->atime = ctx->ctime;

	if (check_fd_usage(
#ifdef DEBUG_PROXY
			ctx
#endif /* DEBUG_PROXY */
			) == -1) {
			goto out;
	}

	ctx->af = ctx->srcaddr.ss_family;

	/* determine original destination of connection 确定连接的原始目的地 */
//	if (ctx->spec->natlookup) {
//		/* NAT engine lookup */
//		ctx->dstaddrlen = sizeof(struct sockaddr_storage);
//		if (ctx->spec->natlookup((struct sockaddr *)&ctx->dstaddr, &ctx->dstaddrlen, ctx->fd, (struct sockaddr *)&ctx->srcaddr, ctx->srcaddrlen) == -1) {
//			log_err_printf("Connection not found in NAT state table, aborting connection\n");
//			goto out;
//		}
//	} else
//    if (ctx->spec->connect_addrlen > 0) {
//		/* static forwarding */
//		ctx->dstaddrlen = ctx->spec->connect_addrlen;
//		memcpy(&ctx->dstaddr, &ctx->spec->connect_addr, ctx->dstaddrlen);
//	} else {
//		/* SNI mode */
//		if (!ctx->spec->ssl) {
//			/* if this happens, the proxyspec parser is broken */
//			log_err_printf("SNI mode used for non-SSL connection; aborting connection\n");
//			goto out;
//		}
//	}
    // 从ctx->fd ==》 真实地址
    //    if (getsockname(ctx->fd, (struct sockaddr *)&ctx->dstaddr, &ctx->dstaddrlen) == -1) {
    //        log_err_level_printf(LOG_CRIT, "Error from getsockname(): %s\n",strerror(errno));
    //        return -1;
    //    }
    
//    ctx->thr->evbase = ctx->thr->evbase;
//    evutil_getaddrinfo()
	if (sys_sockaddr_str((struct sockaddr *)&ctx->srcaddr, ctx->srcaddrlen, &ctx->srchost_str, &ctx->srcport_str) != 0) {
		log_err_level_printf(LOG_CRIT, "Aborting connection setup (out of memory)!\n");
		goto out;
	}
	log_finest_va("srcaddr= [%s]:%s", ctx->srchost_str, ctx->srcport_str);
	return 0;
out:
	evutil_closesocket(ctx->fd);
	pxy_conn_ctx_free(ctx, 1);
	return -1;
}

/* vim: set noet ft=c: */
