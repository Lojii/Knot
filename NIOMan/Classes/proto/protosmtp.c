/*-
 */

#include "protosmtp.h"
#include "prototcp.h"
#include "protossl.h"
#include "util.h"

#include <string.h>

// Size = 25
static char *protosmtp_commands[] = { "EHLO", "HELO", "AUTH", "MAIL", "MAIL FROM", "RCPT", "RCPT TO", "DATA", "SEND", "RSET", "QUIT", "ATRN", "ETRN", "TURN",
	"SAML", "SOML", "EXPN", "NOOP", "HELP", "ONEX", "BDAT", "BURL", "SUBMITTER", "VERB", "VRFY" };

static int NONNULL(1)
protosmtp_validate_command(char *packet, size_t packet_size
#ifdef DEBUG_PROXY
	, pxy_conn_ctx_t *ctx
#endif /* DEBUG_PROXY */
	)
{
	// @attention We validate MAIL FROM and RCPT TO commands as MAIL and RCPT, since we use space as separator.
	size_t command_len = util_get_first_word_len(packet, packet_size);

	unsigned int i;
	for (i = 0; i < sizeof(protosmtp_commands)/sizeof(char *); i++) {
		char *c = protosmtp_commands[i];
		// We need case-insensitive comparison, and here it is safe to call strncasecmp()
		// with a non-string param packet, as we call it only if the lengths are the same
		if (strlen(c) == command_len && !strncasecmp(packet, c, command_len)) {
			log_finest_va("Passed command validation: %.*s", (int)packet_size, packet);
			return 0;
		}
	}
	return -1;
}

int
protosmtp_validate(pxy_conn_ctx_t *ctx, char *packet, size_t packet_size)
{
	protosmtp_ctx_t *smtp_ctx = ctx->protoctx->arg;

	if (smtp_ctx->not_valid) {
		log_finest("Not smtp, validation failed previously");
		return -1;
	}
	if (protosmtp_validate_command(packet, packet_size
#ifdef DEBUG_PROXY
			, ctx
#endif /* DEBUG_PROXY */
			) == -1) {
		smtp_ctx->not_valid = 1;
		log_finest_va("Failed command validation: %.*s", (int)packet_size, packet);
		return -1;
	} else {
		smtp_ctx->seen_command_count++;
	}
	if (smtp_ctx->seen_command_count > 2) {
		ctx->protoctx->is_valid = 1;
		log_finest("Passed validation");
	}
	return 0;
}

int
protosmtp_validate_response(pxy_conn_ctx_t *ctx, char *packet, size_t packet_size)
{
	protosmtp_ctx_t *smtp_ctx = ctx->protoctx->arg;

	if (smtp_ctx->not_valid) {
		log_finest("Not smtp, validation failed previously");
		return -1;
	}

	size_t response_len = util_get_first_word_len(packet, packet_size);

	char response[response_len + 1];
	memcpy(response, packet, response_len);
	response[response_len] = '\0';

	unsigned int i = atoi(response);
	if (i >= 200 && i < 600) {
		// Don't set the is_valid flag here, it should be set on the client side
		//ctx->protoctx->is_valid = 1;
		log_finest_va("Passed response validation: %.*s", (int)packet_size, packet);
		return 0;
	}

	smtp_ctx->not_valid = 1;
	log_finest_va("Failed response validation: %.*s", (int)packet_size, packet);
	return -1;
}

static int NONNULL(1,2,3,4)
protosmtp_try_validate_response(struct bufferevent *bev, pxy_conn_ctx_t *ctx, struct evbuffer *inbuf, struct evbuffer *outbuf)
{
	if (ctx->conn_opts->validate_proto) {
		size_t packet_size = evbuffer_get_length(inbuf);
		char *packet = (char *)pxy_malloc_packet(packet_size, ctx);
		if (!packet) {
			return -1;
		}
		if (evbuffer_copyout(inbuf, packet, packet_size) == -1) {
			free(packet);
			return -1;
		}
		if (protosmtp_validate_response(ctx, packet, packet_size) == -1) {
			// Send message to the client: outbuf of src
			evbuffer_add(outbuf, PROTOERROR_MSG, PROTOERROR_MSG_LEN);
			ctx->sent_protoerror_msg = 1;
			// Discard packets from the client: inbuf of src
			pxy_discard_inbuf(ctx->src.bev);
			// Discard packets to the server: outbuf of srvdst
			evbuffer_drain(bufferevent_get_output(bev), evbuffer_get_length(bufferevent_get_output(bev)));
			free(packet);
			return -1;
		}
		free(packet);
	}
	return 0;
}

static int NONNULL(1) WUNRES
protosmtp_conn_connect(pxy_conn_ctx_t *ctx)
{
	log_finest("ENTER");

	/* create server-side socket and eventbuffer */
	if (prototcp_setup_srvdst(ctx) == -1) {
		return -1;
	}

	// Enable readcb for srvdst to relay the 220 smtp greeting from the server to the client, otherwise the conn stalls
	bufferevent_setcb(ctx->srvdst.bev, pxy_bev_readcb, NULL, pxy_bev_eventcb, ctx);
	return 0;
}

static int NONNULL(1) WUNRES
protosmtps_conn_connect(pxy_conn_ctx_t *ctx)
{
	log_finest("ENTER");

	/* create server-side socket and eventbuffer */
	if (protossl_setup_srvdst(ctx) == -1) {
		return -1;
	}

	// Enable readcb for srvdst to relay the 220 smtp greeting from the server to the client, otherwise the conn stalls
	bufferevent_setcb(ctx->srvdst.bev, pxy_bev_readcb, NULL, pxy_bev_eventcb, ctx);
	return 0;
}

static void NONNULL(1)
protosmtp_bev_readcb_srvdst(struct bufferevent *bev, pxy_conn_ctx_t *ctx)
{
	log_finest_va("ENTER, size=%zu", evbuffer_get_length(bufferevent_get_input(bev)));

	// Make sure src.bev exists
	if (!ctx->src.bev) {
		log_finest("src.bev does not exist");
		return;
	}

//#ifndef WITHOUT_USERAUTH
//	if (prototcp_try_send_userauth_msg(ctx->src.bev, ctx)) {
//		return;
//	}
//#endif /* !WITHOUT_USERAUTH */

	struct evbuffer *inbuf = bufferevent_get_input(bev);
	struct evbuffer *outbuf = bufferevent_get_output(ctx->src.bev);

	// We should validate the response from the smtp server to protect the client,
	// because here we directly relay the packets from the server to the client
	// until we receive the first packet from the client,
	// at which time we xfer srvdst to the first child conn and effectively disable this readcb,
	// hence start diverting packets to the listening program
	if (protosmtp_try_validate_response(bev, ctx, inbuf, outbuf) != 0) {
		return;
	}

	if (ctx->src.closed) {
		pxy_discard_inbuf(bev);
		return;
	}

	evbuffer_add_buffer(outbuf, inbuf);
	pxy_try_set_watermark(bev, ctx, ctx->src.bev);
}

static void NONNULL(1,2)
protosmtp_bev_eventcb_connected_dst(struct bufferevent *bev, pxy_conn_ctx_t *ctx)
{
	log_finest("ENTER");

	ctx->connected = 1;
	bufferevent_enable(bev, EV_READ|EV_WRITE);
	bufferevent_enable(ctx->srvdst.bev, EV_READ);

	if (ctx->proto == PROTO_SMTP) {
		prototcp_enable_src(ctx);
	} else {
		protossl_enable_src(ctx);
	}
}

static void NONNULL(1)
protosmtp_bev_readcb(struct bufferevent *bev, void *arg)
{
	pxy_conn_ctx_t *ctx = arg;

	if (bev == ctx->src.bev) {
		prototcp_bev_readcb_src(bev, ctx);
	} else if (bev == ctx->dst.bev) {
		prototcp_bev_readcb_dst(bev, ctx);
	} else if (bev == ctx->srvdst.bev) {
		protosmtp_bev_readcb_srvdst(bev, ctx);
	} else {
		log_err_printf("protosmtp_bev_readcb: UNKWN conn end\n");
	}
}

static void NONNULL(1)
protosmtp_bev_eventcb_dst(struct bufferevent *bev, short events, pxy_conn_ctx_t *ctx)
{
	if (events & BEV_EVENT_CONNECTED) {
		protosmtp_bev_eventcb_connected_dst(bev, ctx);
	} else if (events & BEV_EVENT_EOF) {
		prototcp_bev_eventcb_eof_dst(bev, ctx);
	} else if (events & BEV_EVENT_ERROR) {
		prototcp_bev_eventcb_error_dst(bev, ctx);
	}
}

static void NONNULL(1)
protosmtp_bev_eventcb(struct bufferevent *bev, short events, void *arg)
{
	pxy_conn_ctx_t *ctx = arg;

	if (bev == ctx->src.bev) {
		prototcp_bev_eventcb_src(bev, events, ctx);
	} else if (bev == ctx->dst.bev) {
		protosmtp_bev_eventcb_dst(bev, events, ctx);
	} else if (bev == ctx->srvdst.bev) {
		prototcp_bev_eventcb_srvdst(bev, events, ctx);
	} else {
		log_err_printf("protosmtp_bev_eventcb: UNKWN conn end\n");
	}
}

void
protosmtps_bev_eventcb(struct bufferevent *bev, short events, void *arg)
{
	pxy_conn_ctx_t *ctx = arg;

	if (events & BEV_EVENT_ERROR) {
		protossl_log_ssl_error(bev, ctx);
	}

	if (bev == ctx->src.bev) {
		prototcp_bev_eventcb_src(bev, events, ctx);
	} else if (bev == ctx->dst.bev) {
		protosmtp_bev_eventcb_dst(bev, events, ctx);
	} else if (bev == ctx->srvdst.bev) {
		protossl_bev_eventcb_srvdst(bev, events, ctx);
	} else {
		log_err_printf("protosmtps_bev_eventcb: UNKWN conn end\n");
	}
}

// @attention Called by thrmgr thread
protocol_t
protosmtp_setup(pxy_conn_ctx_t *ctx)
{
	ctx->protoctx->proto = PROTO_SMTP;

	ctx->protoctx->connectcb = protosmtp_conn_connect;

	ctx->protoctx->bev_readcb = protosmtp_bev_readcb;
	ctx->protoctx->bev_eventcb = protosmtp_bev_eventcb;

	ctx->protoctx->validatecb = protosmtp_validate;

	ctx->protoctx->arg = malloc(sizeof(protosmtp_ctx_t));
	if (!ctx->protoctx->arg) {
		return PROTO_ERROR;
	}
	memset(ctx->protoctx->arg, 0, sizeof(protosmtp_ctx_t));

	return PROTO_SMTP;
}

// @attention Called by thrmgr thread
protocol_t
protosmtps_setup(pxy_conn_ctx_t *ctx)
{
	ctx->protoctx->proto = PROTO_SMTPS;

	ctx->protoctx->connectcb = protosmtps_conn_connect;
	ctx->protoctx->init_conn = protossl_init_conn;
	
	ctx->protoctx->bev_readcb = protosmtp_bev_readcb;
	ctx->protoctx->bev_eventcb = protosmtps_bev_eventcb;

	ctx->protoctx->proto_free = protossl_free;
	ctx->protoctx->validatecb = protosmtp_validate;

	ctx->protoctx->arg = malloc(sizeof(protosmtp_ctx_t));
	if (!ctx->protoctx->arg) {
		return PROTO_ERROR;
	}
	memset(ctx->protoctx->arg, 0, sizeof(protosmtp_ctx_t));

	ctx->sslctx = malloc(sizeof(ssl_ctx_t));
	if (!ctx->sslctx) {
		free(ctx->protoctx->arg);
		return PROTO_ERROR;
	}
	memset(ctx->sslctx, 0, sizeof(ssl_ctx_t));

	return PROTO_SMTPS;
}

/* vim: set noet ft=c: */
