/*-
 */

#include "protopop3.h"
#include "protossl.h"
#include "util.h"

#include <string.h>

// Size = 14
static char *protopop3_commands[] = { "CAPA", "USER", "PASS", "AUTH", "APOP", "STLS", "LIST", "STAT", "UIDL", "RETR", "DELE", "RSET", "TOP", "QUIT", "NOOP" };

static int NONNULL(1)
protopop3_validate_command(char *packet, size_t packet_size
#ifdef DEBUG_PROXY
	, pxy_conn_ctx_t *ctx
#endif /* DEBUG_PROXY */
	)
{
	size_t command_len = util_get_first_word_len(packet, packet_size);

	unsigned int i;
	for (i = 0; i < sizeof(protopop3_commands)/sizeof(char *); i++) {
		char *c = protopop3_commands[i];
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
protopop3_validate(pxy_conn_ctx_t *ctx, char *packet, size_t packet_size)
{
	protopop3_ctx_t *pop3_ctx = ctx->protoctx->arg;

	if (pop3_ctx->not_valid) {
		log_finest("Not pop3, validation failed previously");
		return -1;
	}
	if (protopop3_validate_command(packet, packet_size
#ifdef DEBUG_PROXY
			, ctx
#endif /* DEBUG_PROXY */
			) == -1) {
		pop3_ctx->not_valid = 1;
		log_finest_va("Failed command validation: %.*s", (int)packet_size, packet);
		return -1;
	} else {
		pop3_ctx->seen_command_count++;
	}
	if (pop3_ctx->seen_command_count > 2) {
		ctx->protoctx->is_valid = 1;
		log_finest("Passed validation");
	}
	return 0;
}

// @attention Called by thrmgr thread
protocol_t
protopop3_setup(pxy_conn_ctx_t *ctx)
{
	ctx->protoctx->proto = PROTO_POP3;

	ctx->protoctx->validatecb = protopop3_validate;

	ctx->protoctx->arg = malloc(sizeof(protopop3_ctx_t));
	if (!ctx->protoctx->arg) {
		return PROTO_ERROR;
	}
	memset(ctx->protoctx->arg, 0, sizeof(protopop3_ctx_t));

	return PROTO_POP3;
}

// @attention Called by thrmgr thread
protocol_t
protopop3s_setup(pxy_conn_ctx_t *ctx)
{
	ctx->protoctx->proto = PROTO_POP3S;

	ctx->protoctx->connectcb = protossl_conn_connect;
	ctx->protoctx->init_conn = protossl_init_conn;
	
	ctx->protoctx->bev_eventcb = protossl_bev_eventcb;

	ctx->protoctx->proto_free = protossl_free;
	ctx->protoctx->validatecb = protopop3_validate;

	ctx->protoctx->arg = malloc(sizeof(protopop3_ctx_t));
	if (!ctx->protoctx->arg) {
		return PROTO_ERROR;
	}
	memset(ctx->protoctx->arg, 0, sizeof(protopop3_ctx_t));

	ctx->sslctx = malloc(sizeof(ssl_ctx_t));
	if (!ctx->sslctx) {
		free(ctx->protoctx->arg);
		return PROTO_ERROR;
	}
	memset(ctx->sslctx, 0, sizeof(ssl_ctx_t));

	return PROTO_POP3S;
}

/* vim: set noet ft=c: */
