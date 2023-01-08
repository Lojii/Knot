/*-
 */

#ifndef PROTOSSL_H
#define PROTOSSL_H

#include "pxyconn.h"

int protossl_log_masterkey(pxy_conn_ctx_t *, pxy_conn_desc_t *) NONNULL(1,2);
void protossl_log_ssl_error(struct bufferevent *, pxy_conn_ctx_t *) NONNULL(1,2);

// @todo Used externally by pxy_log_connect_src(), create tcp and ssl versions of that function instead?
void protossl_srccert_write(pxy_conn_ctx_t *) NONNULL(1);
SSL *protossl_dstssl_create(pxy_conn_ctx_t *) NONNULL(1);

void protossl_free(pxy_conn_ctx_t *) NONNULL(1);
void protossl_init_conn(evutil_socket_t, short, void *);
int protossl_conn_connect(pxy_conn_ctx_t *) NONNULL(1) WUNRES;
void protossl_connect_child(pxy_conn_child_ctx_t *) NONNULL(1);

int protossl_enable_src(pxy_conn_ctx_t *) NONNULL(1);

int protossl_setup_src_ssl_from_dst(pxy_conn_ctx_t *) NONNULL(1);
int protossl_setup_src_ssl_from_child_dst(pxy_conn_child_ctx_t *) NONNULL(1);
int protossl_setup_src_new_bev_ssl_accepting(pxy_conn_ctx_t *) NONNULL(1);

int protossl_setup_dst_ssl(pxy_conn_ctx_t *) NONNULL(1);
int protossl_setup_dst_new_bev_ssl_connecting(pxy_conn_ctx_t *) NONNULL(1);
int protossl_setup_dst_ssl_child(pxy_conn_child_ctx_t *) NONNULL(1);
int protossl_setup_dst_new_bev_ssl_connecting_child(pxy_conn_child_ctx_t *) NONNULL(1);
int protossl_setup_dst_child(pxy_conn_child_ctx_t *) NONNULL(1);

int protossl_setup_srvdst(pxy_conn_ctx_t *ctx) NONNULL(1);

void protossl_bev_eventcb_srvdst(struct bufferevent *, short, pxy_conn_ctx_t *) NONNULL(1);

void protossl_bev_eventcb(struct bufferevent *, short, void *) NONNULL(1);
void protossl_bev_eventcb_child(struct bufferevent *, short, void *) NONNULL(1);

protocol_t protossl_setup(pxy_conn_ctx_t *) NONNULL(1);
protocol_t protossl_setup_child(pxy_conn_child_ctx_t *) NONNULL(1);

#endif /* PROTOSSL_H */
