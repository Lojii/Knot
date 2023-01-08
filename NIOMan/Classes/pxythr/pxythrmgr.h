/*
 */

#ifndef PXYTHRMGR_H
#define PXYTHRMGR_H

#include "opts.h"
#include "attrib.h"
#include "pxythr.h"

extern int descriptor_table_size;
#define FD_RESERVE 10
//工作线程池管理结构
struct pxy_thrmgr_ctx {
	int num_thr;//线程总数
	global_t *global;//全局配置
	pxy_thr_ctx_t **thr;//线程数组
	long long unsigned int conn_count;
    long long unsigned int all_in_bytes;
    long long unsigned int all_out_bytes;
};

pxy_thrmgr_ctx_t * pxy_thrmgr_new(global_t *) MALLOC;
int pxy_thrmgr_run(pxy_thrmgr_ctx_t *) NONNULL(1) WUNRES;
void pxy_thrmgr_free(pxy_thrmgr_ctx_t *) NONNULL(1);

void pxy_thrmgr_assign_thr(pxy_conn_ctx_t *) NONNULL(1);

#endif /* !PXYTHRMGR_H */

/* vim: set noet ft=c: */
