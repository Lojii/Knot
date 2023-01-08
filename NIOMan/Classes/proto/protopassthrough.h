/*-
 */

#ifndef PROTOPASSTHROUGH_H
#define PROTOPASSTHROUGH_H

#include "pxyconn.h"

void protopassthrough_engage(pxy_conn_ctx_t *) NONNULL(1);
protocol_t protopassthrough_setup(pxy_conn_ctx_t *) NONNULL(1);

#endif /* PROTOPASSTHROUGH_H */
