/*-
 */

#ifndef PROTOPOP3_H
#define PROTOPOP3_H

#include "pxyconn.h"

typedef struct protopop3_ctx {
	unsigned int not_valid : 1;
	unsigned int seen_command_count;
} protopop3_ctx_t;

int protopop3_validate(pxy_conn_ctx_t *, char *, size_t) NONNULL(1,2);

protocol_t protopop3_setup(pxy_conn_ctx_t *) NONNULL(1);
protocol_t protopop3s_setup(pxy_conn_ctx_t *) NONNULL(1);

#endif /* PROTOPOP3_H */
