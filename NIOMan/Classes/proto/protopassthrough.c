/*-
 */

#include "protopassthrough.h"
#include "prototcp.h"

#include <sys/param.h>

#ifdef HAVE_LOCAL_PROCINFO
static int NONNULL(1)
protopassthrough_prepare_logging(pxy_conn_ctx_t *ctx)
{
	/* prepare logging, part 2 */
	if (WANT_CONNECT_LOG(ctx)) {
		return pxy_prepare_logging_local_procinfo(ctx);
	}
	return 0;
}
#endif /* HAVE_LOCAL_PROCINFO */

static void NONNULL(1)
protopassthrough_log_dbg_connect_type(pxy_conn_ctx_t *ctx)
{
	if (OPTS_DEBUG(ctx->global)) {
		/* for TCP, we get only a dst connect event,
		 * since src was already connected from the
		 * beginning */
		log_dbg_printf("PASSTHROUGH connected to [%s]:%s\n",
					   STRORDASH(ctx->dsthost_str), STRORDASH(ctx->dstport_str));
		log_dbg_printf("PASSTHROUGH connected from [%s]:%s\n",
					   STRORDASH(ctx->srchost_str), STRORDASH(ctx->srcport_str));
	}
}

static void NONNULL(1)
protopassthrough_log_connect(pxy_conn_ctx_t *ctx)
{
	if (WANT_CONNECT_LOG(ctx)) {
		pxy_log_connect_nonhttp(ctx);
	}
	protopassthrough_log_dbg_connect_type(ctx);
}

/*
 * We cannot redirect failed ssl connections to login page while switchingt o passthrough mode, because redirect message should be sent over ssl, but it has failed (that's why we are engaging the passthrough mode).
 */
void
protopassthrough_engage(pxy_conn_ctx_t *ctx)
{
	log_fine("ENTER");

	// Free any children of the previous proto
	pxy_conn_free_children(ctx);

	// In split mode, srvdst is used as dst, so it should be freed as dst below
	// If srvdst has been xferred to the first child conn, the child should free it, not the parent
	if (ctx->divert && !ctx->srvdst_xferred) {
		ctx->srvdst.zfree(ctx->srvdst.bev, ctx);
	} else /*if (!ctx->divert || ctx->srvdst_xferred)*/ {
		struct bufferevent *ubev = bufferevent_get_underlying(ctx->srvdst.bev);

		bufferevent_setcb(ctx->srvdst.bev, NULL, NULL, NULL, NULL);
		bufferevent_disable(ctx->srvdst.bev, EV_READ|EV_WRITE);

		if (ubev) {
			bufferevent_setcb(ubev, NULL, NULL, NULL, NULL);
			bufferevent_disable(ubev, EV_READ|EV_WRITE);
		}
	}
	ctx->srvdst.bev = NULL;
	ctx->srvdst.ssl = NULL;
	ctx->connected = 0;

	// Close and free dst if open
	// Make sure bev is not NULL, as dst may not have been initialized yet
	if (!ctx->dst.closed && ctx->dst.bev) {
		ctx->dst.closed = 1;
		ctx->dst.zfree(ctx->dst.bev, ctx);
		ctx->dst.bev = NULL;
		ctx->dst_fd = 0;
	}

	// Free any/all data of the previous proto
	if (ctx->protoctx->proto_free) {
		ctx->protoctx->proto_free(ctx);
		// Disable proto_free callback of the previous proto, otherwise it is called while passthrough is closing too
		ctx->protoctx->proto_free = NULL;
	}

	ctx->proto = protopassthrough_setup(ctx);
	pxy_conn_connect(ctx);
}

static int NONNULL(1) WUNRES
protopassthrough_conn_connect(pxy_conn_ctx_t *ctx)
{
	log_finest("ENTER");

	if (prototcp_setup_srvdst(ctx) == -1) {
		return -1;
	}

	bufferevent_setcb(ctx->srvdst.bev, pxy_bev_readcb, pxy_bev_writecb, pxy_bev_eventcb, ctx);
	return 0;
}

static void NONNULL(1)
protopassthrough_bev_readcb_src(struct bufferevent *bev, pxy_conn_ctx_t *ctx)
{
	log_finest_va("ENTER, size=%zu", evbuffer_get_length(bufferevent_get_input(bev)));

	// Passthrough packets are transferred between src and srvdst
	if (ctx->srvdst.closed) {
		pxy_discard_inbuf(bev);
		return;
	}

//#ifndef WITHOUT_USERAUTH
//	if (prototcp_try_send_userauth_msg(bev, ctx)) {
//		return;
//	}
//#endif /* !WITHOUT_USERAUTH */

	if (pxy_conn_apply_deferred_block_action(ctx)) {
		return;
	}

	evbuffer_add_buffer(bufferevent_get_output(ctx->srvdst.bev), bufferevent_get_input(bev));
	pxy_try_set_watermark(bev, ctx, ctx->srvdst.bev);
}

static void NONNULL(1)
protopassthrough_bev_readcb_srvdst(struct bufferevent *bev, pxy_conn_ctx_t *ctx)
{
	log_finest_va("ENTER, size=%zu", evbuffer_get_length(bufferevent_get_input(bev)));

	// Passthrough packets are transferred between src and srvdst
	if (ctx->src.closed) {
		pxy_discard_inbuf(bev);
		return;
	}

	evbuffer_add_buffer(bufferevent_get_output(ctx->src.bev), bufferevent_get_input(bev));
	pxy_try_set_watermark(bev, ctx, ctx->src.bev);
}

static void NONNULL(1)
protopassthrough_bev_writecb_src(struct bufferevent *bev, pxy_conn_ctx_t *ctx)
{
	log_finest("ENTER");

//#ifndef WITHOUT_USERAUTH
//	if (prototcp_try_close_unauth_conn(bev, ctx)) {
//		return;
//	}
//#endif /* !WITHOUT_USERAUTH */

	// @attention srvdst.bev may be NULL
	if (ctx->srvdst.closed) {
		if (pxy_try_close_conn_end(&ctx->src, ctx)) {
			log_finest("srvdst.closed, terminate conn");
			pxy_conn_term(ctx, 1);
		}
		return;
	}
	pxy_try_unset_watermark(bev, ctx, &ctx->srvdst);
}

static void NONNULL(1)
protopassthrough_bev_writecb_srvdst(struct bufferevent *bev, pxy_conn_ctx_t *ctx)
{
	log_finest("ENTER");

	if (ctx->src.closed) {
		if (pxy_try_close_conn_end(&ctx->srvdst, ctx) == 1) {
			log_finest("src.closed, terminate conn");
			pxy_conn_term(ctx, 0);
		}
		return;
	}
	pxy_try_unset_watermark(bev, ctx, &ctx->src);
}

static void NONNULL(1,2)
protopassthrough_bev_eventcb_connected_src(UNUSED struct bufferevent *bev, UNUSED pxy_conn_ctx_t *ctx)
{
	log_finest("ENTER");
}

static int NONNULL(1)
protopassthrough_enable_src(pxy_conn_ctx_t *ctx)
{
	log_finest("ENTER");

	if (prototcp_setup_src(ctx) == -1) {
		return -1;
	}
	bufferevent_setcb(ctx->src.bev, pxy_bev_readcb, pxy_bev_writecb, pxy_bev_eventcb, ctx);

	log_finer("Enabling src");

	// Now open the gates
	bufferevent_enable(ctx->src.bev, EV_READ|EV_WRITE);
	return 0;
}

//#ifndef WITHOUT_USERAUTH
//static void NONNULL(1)
//protopassthrough_classify_user(pxy_conn_ctx_t *ctx)
//{
//	// Do not re-engage passthrough mode in passthrough mode
//	if (ctx->spec->opts->passusers && !pxy_is_listuser(ctx->spec->opts->passusers, ctx->user
//#ifdef DEBUG_PROXY
//			, ctx, "PassUsers"
//#endif /* DEBUG_PROXY */
//			) &&
//			ctx->spec->opts->divertusers && !pxy_is_listuser(ctx->spec->opts->divertusers, ctx->user
//#ifdef DEBUG_PROXY
//			, ctx, "DivertUsers"
//#endif /* DEBUG_PROXY */
//			)) {
//		log_fine_va("User %s not in PassUsers or DivertUsers; terminating connection", ctx->user);
//		pxy_conn_term(ctx, 1);
//	}
//}
//#endif /* !WITHOUT_USERAUTH */

static void NONNULL(1,2)
protopassthrough_bev_eventcb_connected_srvdst(struct bufferevent *bev, pxy_conn_ctx_t *ctx)
{
	log_finest("ENTER");

//#ifndef WITHOUT_USERAUTH
//	pxy_userauth(ctx);
//	if (ctx->term || ctx->enomem) {
//		return;
//	}
//#endif /* !WITHOUT_USERAUTH */

	ctx->connected = 1;
	bufferevent_enable(bev, EV_READ|EV_WRITE);

	// Do not re-enable src if it is already enabled, e.g. in autossl
	if (!ctx->src.bev && protopassthrough_enable_src(ctx) == -1) {
		return;
	}
}

static void NONNULL(1,2)
protopassthrough_bev_eventcb_eof_src(struct bufferevent *bev, pxy_conn_ctx_t *ctx)
{
#ifdef DEBUG_PROXY
	log_finest("ENTER");
	pxy_log_dbg_evbuf_info(ctx, &ctx->src, &ctx->srvdst);
#endif /* DEBUG_PROXY */

	if (!ctx->connected) {
		log_err_level(LOG_WARNING, "EOF on outbound connection before connection establishment");
		ctx->srvdst.closed = 1;
	} else if (!ctx->srvdst.closed) {
		log_finest("!srvdst.closed, terminate conn");
		if (pxy_try_consume_last_input(bev, ctx) == -1) {
			return;
		}
		pxy_try_close_conn_end(&ctx->srvdst, ctx);
	}

	pxy_try_disconnect(ctx, &ctx->src, &ctx->srvdst, 1);
}

static void NONNULL(1,2)
protopassthrough_bev_eventcb_eof_srvdst(struct bufferevent *bev, pxy_conn_ctx_t *ctx)
{
#ifdef DEBUG_PROXY
	log_finest("ENTER");
	pxy_log_dbg_evbuf_info(ctx, &ctx->srvdst, &ctx->src);
#endif /* DEBUG_PROXY */

	if (!ctx->connected) {
		log_err_level(LOG_WARNING, "EOF on outbound connection before connection establishment");
		ctx->src.closed = 1;
	} else if (!ctx->src.closed) {
		log_finest("!src.closed, terminate conn");
		if (pxy_try_consume_last_input(bev, ctx) == -1) {
			return;
		}
		pxy_try_close_conn_end(&ctx->src, ctx);
	}

	pxy_try_disconnect(ctx, &ctx->srvdst, &ctx->src, 0);
}

static void NONNULL(1,2)
protopassthrough_bev_eventcb_error_src(UNUSED struct bufferevent *bev, pxy_conn_ctx_t *ctx)
{
	log_fine("ENTER");

	// Passthrough packets are transferred between src and srvdst
	if (!ctx->connected) {
		ctx->srvdst.closed = 1;
	} else if (!ctx->srvdst.closed) {
		pxy_try_close_conn_end(&ctx->srvdst, ctx);
	}

	pxy_try_disconnect(ctx, &ctx->src, &ctx->srvdst, 1);
}

static void NONNULL(1,2)
protopassthrough_bev_eventcb_error_srvdst(UNUSED struct bufferevent *bev, pxy_conn_ctx_t *ctx)
{
	log_fine("ENTER");

	// Passthrough packets are transferred between src and srvdst
	if (!ctx->connected) {
		ctx->src.closed = 1;
	} else if (!ctx->src.closed) {
		pxy_try_close_conn_end(&ctx->src, ctx);
	}

	pxy_try_disconnect(ctx, &ctx->srvdst, &ctx->src, 0);
}

static void NONNULL(1)
protopassthrough_bev_readcb(struct bufferevent *bev, void *arg)
{
	pxy_conn_ctx_t *ctx = arg;

	if (bev == ctx->src.bev) {
		protopassthrough_bev_readcb_src(bev, ctx);
	} else if (bev == ctx->srvdst.bev) {
		protopassthrough_bev_readcb_srvdst(bev, ctx);
	} else {
		log_err_printf("protopassthrough_bev_readcb: UNKWN conn end\n");
	}
}

static void NONNULL(1)
protopassthrough_bev_writecb(struct bufferevent *bev, void *arg)
{
	pxy_conn_ctx_t *ctx = arg;

	if (bev == ctx->src.bev) {
		protopassthrough_bev_writecb_src(bev, ctx);
	} else if (bev == ctx->srvdst.bev) {
		protopassthrough_bev_writecb_srvdst(bev, ctx);
	} else {
		log_err_printf("protopassthrough_bev_writecb: UNKWN conn end\n");
	}
}

static void NONNULL(1)
protopassthrough_bev_eventcb_src(struct bufferevent *bev, short events, pxy_conn_ctx_t *ctx)
{
	if (events & BEV_EVENT_CONNECTED) {
		protopassthrough_bev_eventcb_connected_src(bev, ctx);
	} else if (events & BEV_EVENT_EOF) {
		protopassthrough_bev_eventcb_eof_src(bev, ctx);
	} else if (events & BEV_EVENT_ERROR) {
		protopassthrough_bev_eventcb_error_src(bev, ctx);
	}
}

static void NONNULL(1)
protopassthrough_bev_eventcb_srvdst(struct bufferevent *bev, short events, pxy_conn_ctx_t *ctx)
{
	if (events & BEV_EVENT_CONNECTED) {
		protopassthrough_bev_eventcb_connected_srvdst(bev, ctx);
	} else if (events & BEV_EVENT_EOF) {
		protopassthrough_bev_eventcb_eof_srvdst(bev, ctx);
	} else if (events & BEV_EVENT_ERROR) {
		protopassthrough_bev_eventcb_error_srvdst(bev, ctx);
	}
}

static void NONNULL(1)
protopassthrough_bev_eventcb(struct bufferevent *bev, short events, void *arg)
{
	pxy_conn_ctx_t *ctx = arg;

	if (bev == ctx->src.bev) {
		protopassthrough_bev_eventcb_src(bev, events, ctx);
	} else if (bev == ctx->srvdst.bev) {
		protopassthrough_bev_eventcb_srvdst(bev, events, ctx);
	} else {
		log_err_printf("protopassthrough_bev_eventcb: UNKWN conn end\n");
		return;
	}

	// The topmost eventcb handles the term and enomem flags, frees the conn
	if (ctx->term || ctx->enomem) {
		return;
	}

	if (events & BEV_EVENT_CONNECTED) {
		if (ctx->connected) {
#ifdef HAVE_LOCAL_PROCINFO
			if (protopassthrough_prepare_logging(ctx) == -1) {
				return;
			}
#endif /* HAVE_LOCAL_PROCINFO */
			protopassthrough_log_connect(ctx);
		}
	}
}

protocol_t
protopassthrough_setup(pxy_conn_ctx_t *ctx)
{
	// @attention Reset all callbacks while switching to passthrough mode, because we should override any/all protocol settings of the previous protocol.
	// This is different from initial protocol setup, which may choose to keep the default tcp settings.
	ctx->protoctx->proto = PROTO_PASSTHROUGH;
	ctx->protoctx->connectcb = protopassthrough_conn_connect;
	// Never used, but set it to the correct callback anyway
	ctx->protoctx->init_conn = prototcp_init_conn;
	
	ctx->protoctx->bev_readcb = protopassthrough_bev_readcb;
	ctx->protoctx->bev_writecb = protopassthrough_bev_writecb;
	ctx->protoctx->bev_eventcb = protopassthrough_bev_eventcb;

//#ifndef WITHOUT_USERAUTH
//	ctx->protoctx->classify_usercb = protopassthrough_classify_user;
//#endif /* !WITHOUT_USERAUTH */

	return PROTO_PASSTHROUGH;
}

/* vim: set noet ft=c: */
