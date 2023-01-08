/*-
 */

#ifndef PXYTHR_H
#define PXYTHR_H

#include "attrib.h"

#include <sys/types.h>
#include <sys/socket.h>

#include <event2/event.h>
#include <event2/dns.h>
#include <pthread.h>

typedef struct pxy_conn_ctx pxy_conn_ctx_t;
typedef struct pxy_thrmgr_ctx pxy_thrmgr_ctx_t;
//单个工作线程管理结构
typedef struct pxy_thr_ctx {
	pthread_t thr;
	int id;
	pxy_thrmgr_ctx_t *thrmgr;
	size_t load;
	struct event_base *evbase;
	struct evdns_base *dnsbase;
	int running;

	// Statistics
	evutil_socket_t max_fd;
	size_t max_load;
	size_t timedout_conns;
	size_t errors;
	size_t set_watermarks;
	size_t unset_watermarks;
	long long unsigned int intif_in_bytes;
	long long unsigned int intif_out_bytes;
	long long unsigned int extif_in_bytes;
	long long unsigned int extif_out_bytes;
	// Each stats has an id, incremented on each stats print
	unsigned short stats_id;
	// Used to print statistics, compared against stats_period
	unsigned int timeout_count;

	// 线程上活动连接的列表
	pxy_conn_ctx_t *conns;
} pxy_thr_ctx_t;

void pxy_thr_attach(pxy_conn_ctx_t *) NONNULL(1);
void pxy_thr_detach(pxy_conn_ctx_t *) NONNULL(1);

void *pxy_thr(void *);

#endif /* !PXYTHR_H */

/* vim: set noet ft=c: */
