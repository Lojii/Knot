/*-
 */

#ifndef PROTOAUTOSSL_H
#define PROTOAUTOSSL_H

#include "pxyconn.h"

protocol_t protoautossl_setup(pxy_conn_ctx_t *) NONNULL(1);
protocol_t protoautossl_setup_child(pxy_conn_child_ctx_t *) NONNULL(1);

#endif /* PROTOAUTOSSL_H */
