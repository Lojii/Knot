/*-
 */

#ifndef PROXY_H
#define PROXY_H

#include "opts.h"
#include "attrib.h"
#include "pxythrmgr.h"

#include <sys/syslog.h>

typedef struct proxy_ctx proxy_ctx_t;

/*
 * Listener context.
 */
typedef struct proxy_listener_ctx {
	pxy_thrmgr_ctx_t *thrmgr; // 线程管理
	proxyspec_t *spec; // 代理配置
	global_t *global; // 全局配置
	struct evconnlistener *evcl; // libevent 监听
	struct proxy_listener_ctx *next;
} proxy_listener_ctx_t;
// 主结构体
proxy_ctx_t * proxy_new(global_t *, int) NONNULL(1) MALLOC;
// 开启代理
int proxy_run(proxy_ctx_t *) NONNULL(1);
// 中断
void proxy_loopbreak(proxy_ctx_t *, int) NONNULL(1);
// 释放
void proxy_free(proxy_ctx_t *) NONNULL(1);
// 监听出错回调
void proxy_listener_errorcb(struct evconnlistener *, UNUSED void *);

pxy_conn_ctx_t *proxy_conn_ctx_new(evutil_socket_t, pxy_thrmgr_ctx_t *, proxyspec_t *, global_t *) MALLOC NONNULL(2,3,4);
#endif /* !PROXY_H */

/* vim: set noet ft=c: */
