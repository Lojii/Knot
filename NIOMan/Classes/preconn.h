//
//  preconn.h
//  NIO2022
//
//  Created by LiuJie on 2022/3/9.
//
#include "proxy.h"
#include "opts.h"
#include "filter.h"
#include "attrib.h"
#include "pxythrmgr.h"
#include "log.h"
#include "pxyconn.h"

#include <sys/types.h>
#include <sys/socket.h>

#include <event2/buffer.h>
#include <event2/bufferevent.h>

#ifndef preconn_h
#define preconn_h

//pxy_bev_readcb, pxy_bev_writecb, pxy_bev_eventcb
void pre_bev_readcb(struct bufferevent *, void *);
void pre_bev_writecb(struct bufferevent *, void *);
void pre_bev_eventcb(struct bufferevent *, short, void *);

void NONNULL(1) pre_setup_proto(pxy_conn_ctx_t *ctx, protocol_t proto);

void pre_conn(evutil_socket_t fd, UNUSED short what, void *arg);

char *findHost(char *, char *);
char *findPort(char *, char *);

#endif /* preconn_h */
