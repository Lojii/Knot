/*-
 */

#ifndef PROTOSMTP_H
#define PROTOSMTP_H

#include "pxyconn.h"

typedef struct protosmtp_ctx {
	unsigned int not_valid : 1;
	unsigned int seen_command_count;
} protosmtp_ctx_t;

int protosmtp_validate(pxy_conn_ctx_t *, char *, size_t) NONNULL(1,2);
int protosmtp_validate_response(pxy_conn_ctx_t *, char *, size_t) NONNULL(1,2);

protocol_t protosmtp_setup(pxy_conn_ctx_t *) NONNULL(1);
protocol_t protosmtps_setup(pxy_conn_ctx_t *) NONNULL(1);

#endif /* PROTOSMTP_H */
