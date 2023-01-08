/*-
 */

#ifndef PROTOTCP_H
#define PROTOTCP_H

#include "pxyconn.h"

void prototcp_init_conn(evutil_socket_t, short, void *);

//#ifndef WITHOUT_USERAUTH
//int prototcp_try_send_userauth_msg(struct bufferevent *, pxy_conn_ctx_t *) NONNULL(1,2);
//int prototcp_try_close_unauth_conn(struct bufferevent *, pxy_conn_ctx_t *) NONNULL(1,2);
//#endif /* !WITHOUT_USERAUTH */
int prototcp_try_close_protoerror_conn(struct bufferevent *, pxy_conn_ctx_t *) NONNULL(1,2);

void prototcp_bev_readcb_src(struct bufferevent *, pxy_conn_ctx_t *) NONNULL(1,2);
void prototcp_bev_readcb_dst(struct bufferevent *, pxy_conn_ctx_t *) NONNULL(1);

void prototcp_bev_writecb_dst(struct bufferevent *, pxy_conn_ctx_t *) NONNULL(1);

void prototcp_bev_writecb(struct bufferevent *, void *) NONNULL(1);

void prototcp_bev_eventcb_eof_src(struct bufferevent *, pxy_conn_ctx_t *) NONNULL(1,2);
void prototcp_bev_eventcb_error_src(struct bufferevent *, pxy_conn_ctx_t *) NONNULL(1,2);

void prototcp_bev_eventcb_eof_dst(struct bufferevent *, pxy_conn_ctx_t *) NONNULL(1,2);
void prototcp_bev_eventcb_error_dst(struct bufferevent *, pxy_conn_ctx_t *) NONNULL(1,2);

void prototcp_bev_eventcb_eof_srvdst(struct bufferevent *, pxy_conn_ctx_t *) NONNULL(1,2);
void prototcp_bev_eventcb_error_srvdst(struct bufferevent *, pxy_conn_ctx_t *) NONNULL(1,2);

void prototcp_bev_eventcb_src(struct bufferevent *, short, pxy_conn_ctx_t *) NONNULL(1,3);

void prototcp_bev_writecb_child(struct bufferevent *, void *) NONNULL(1);

void prototcp_bev_eventcb_eof_dst_child(struct bufferevent *, pxy_conn_child_ctx_t *) NONNULL(1,2);
void prototcp_bev_eventcb_error_dst_child(struct bufferevent *, pxy_conn_child_ctx_t *) NONNULL(1,2);

void prototcp_bev_eventcb_src_child(struct bufferevent *, short, pxy_conn_child_ctx_t *) NONNULL(1,3);
void prototcp_bev_eventcb_dst_child(struct bufferevent *, short, pxy_conn_child_ctx_t *) NONNULL(1,3);

int prototcp_enable_src(pxy_conn_ctx_t *) NONNULL(1);
void prototcp_bev_eventcb_srvdst(struct bufferevent *, short, pxy_conn_ctx_t *) NONNULL(1);

int prototcp_setup_src(pxy_conn_ctx_t *) NONNULL(1);
int prototcp_setup_dst(pxy_conn_ctx_t *) NONNULL(1);
int prototcp_setup_srvdst(pxy_conn_ctx_t *) NONNULL(1);

int prototcp_setup_src_child(pxy_conn_child_ctx_t *) NONNULL(1);
int prototcp_setup_dst_child(pxy_conn_child_ctx_t *) NONNULL(1);

protocol_t prototcp_setup(pxy_conn_ctx_t *) NONNULL(1);
protocol_t prototcp_setup_child(pxy_conn_child_ctx_t *) NONNULL(1);

#endif /* PROTOTCP_H */
