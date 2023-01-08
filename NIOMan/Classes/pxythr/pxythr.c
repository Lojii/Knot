/*-
 */

#include "pxythr.h"

#include "log.h"
#include "pxyconn.h"
#include "util.h"

#include <assert.h>

/*
 * Attach a connection to its thread.
 * This function cannot fail.
 */
void
pxy_thr_attach(pxy_conn_ctx_t *ctx)
{
    if (ctx->attached == 1) {
        printf("---> thr_id:%d conn_id:%llu 重复attach \n", ctx->thr->id, ctx->id);
        return;
    }
	assert(ctx != NULL);
	// A thr should have already been assigned
	assert(ctx->thr != NULL);

	log_finest("Adding conn");
//    printf("---> thr_id:%d conn_id:%llu\n", ctx->thr->id, ctx->id);

	// Always keep thr load and conns list in sync
	ctx->thr->load++;

	ctx->next = ctx->thr->conns;
	ctx->thr->conns = ctx;
	if (ctx->next)
		ctx->next->prev = ctx;
    ctx->attached = 1;
}

/*
 * Detach a connection from a thread by index.
 * This function cannot fail.
 */
void
pxy_thr_detach(pxy_conn_ctx_t *ctx)
{
	assert(ctx != NULL);
	assert(ctx->children == NULL);
	// If this function is called, the thr conns list cannot be empty
	assert(ctx->thr->conns != NULL);

	log_finest("Removing conn");

	// We increment thr load in pxy_conn_init() only (for parent conns)
	ctx->thr->load--;

	if (ctx->prev) {
		ctx->prev->next = ctx->next;
	} else {
		ctx->thr->conns = ctx->next;
	}
	if (ctx->next)
		ctx->next->prev = ctx->prev;

#ifdef DEBUG_PROXY
	// We may get multiple conns with the same fd combinations, so fds cannot uniquely identify a conn; hence the need for unique ids.
	if (ctx->thr->conns) {
		if (ctx->id == ctx->thr->conns->id) {
			// This should never happen
			log_fine("Found conn in thr conns, first");
			assert(0);
		} else {
			pxy_conn_ctx_t *current = ctx->thr->conns->next;
			pxy_conn_ctx_t *previous = ctx->thr->conns;
			while (current != NULL && previous != NULL) {
				if (ctx->id == current->id) {
					// This should never happen
					log_fine("Found conn in thr conns");
					assert(0);
				}
				previous = current;
				current = current->next;
			}
			log_finest("Cannot find conn in thr conns");
		}
	} else {
		log_finest("Cannot find conn in thr conns, empty");
	}
#endif /* DEBUG_PROXY */
}
// 获取线程上已经超时的链接ctx
static void
pxy_thr_get_expired_conns(pxy_thr_ctx_t *tctx, pxy_conn_ctx_t **expired_conns)
{
	*expired_conns = NULL;

	if (tctx->conns) {
		time_t now = time(NULL);

		pxy_conn_ctx_t *ctx = tctx->conns;
		while (ctx) {
			time_t elapsed_time = now - ctx->atime;
			if (elapsed_time > (time_t)tctx->thrmgr->global->conn_idle_timeout) {
				ctx->next_expired = *expired_conns;
				*expired_conns = ctx;
			}
			ctx = ctx->next;
		}

		if (tctx->thrmgr->global->statslog) {
			ctx = *expired_conns;
			while (ctx) {
				time_t atime = now - ctx->atime;
				time_t ctime = now - ctx->ctime;

//#ifndef WITHOUT_USERAUTH
//				log_finest_main_va("thr=%d, id=%llu, fd=%d, child_fd=%d, dst=%d, srvdst=%d, child_src=%d, child_dst=%d, p=%d-%d-%d c=%d-%d, ce=%d cc=%d, at=%lld ct=%lld, src_addr=%s:%s, dst_addr=%s:%s, user=%s, valid=%d",
//					tctx->id, ctx->id, ctx->fd, ctx->child_fd, ctx->dst_fd, ctx->srvdst_fd, ctx->child_src_fd, ctx->child_dst_fd,
//					ctx->src.closed, ctx->dst.closed, ctx->srvdst.closed, ctx->children ? ctx->children->src.closed : 0, ctx->children ? ctx->children->dst.closed : 0,
//					ctx->children ? 1:0, ctx->child_count, (long long)atime, (long long)ctime,
//					STRORDASH(ctx->srchost_str), STRORDASH(ctx->srcport_str), STRORDASH(ctx->dsthost_str), STRORDASH(ctx->dstport_str),
//					STRORDASH(ctx->user), ctx->protoctx->is_valid);
//#else /* WITHOUT_USERAUTH */
				log_finest_main_va("thr=%d, id=%llu, fd=%d, child_fd=%d, dst=%d, srvdst=%d, child_src=%d, child_dst=%d, p=%d-%d-%d c=%d-%d, ce=%d cc=%d, at=%lld ct=%lld, src_addr=%s:%s, dst_addr=%s:%s, valid=%d",
					tctx->id, ctx->id, ctx->fd, ctx->child_fd, ctx->dst_fd, ctx->srvdst_fd, ctx->child_src_fd, ctx->child_dst_fd,
					ctx->src.closed, ctx->dst.closed, ctx->srvdst.closed, ctx->children ? ctx->children->src.closed : 0, ctx->children ? ctx->children->dst.closed : 0,
					ctx->children ? 1:0, ctx->child_count, (long long)atime, (long long)ctime,
					STRORDASH(ctx->srchost_str), STRORDASH(ctx->srcport_str), STRORDASH(ctx->dsthost_str), STRORDASH(ctx->dstport_str), ctx->protoctx->is_valid);
//#endif /* WITHOUT_USERAUTH */

				char *msg;
				if (asprintf(&msg, "EXPIRED: atime=%lld, ctime=%lld, src_addr=%s:%s, dst_addr=%s:%s,valid=%d\n",
						(long long)atime, (long long)ctime,
						STRORDASH(ctx->srchost_str), STRORDASH(ctx->srcport_str), STRORDASH(ctx->dsthost_str), STRORDASH(ctx->dstport_str),
						ctx->protoctx->is_valid) < 0) {
					break;
				}

				if (log_conn(msg) == -1) {
					log_err_level_printf(LOG_WARNING, "Expired conn logging failed\n");
				}
				free(msg);

				ctx = ctx->next_expired;
			}
		}
	}
}

static evutil_socket_t
pxy_thr_print_children(pxy_conn_child_ctx_t *ctx)
{
	evutil_socket_t max_fd = 0;
	while (ctx) {
		// No need to log child stats
		log_finest_main_va("CHILD CONN: thr=%d, id=%llu, cid=%d, src=%d, dst=%d, c=%d-%d",
			ctx->conn->thr->id, ctx->conn->id, ctx->id, ctx->fd, ctx->dst_fd, ctx->src.closed, ctx->dst.closed);
		max_fd = max(max_fd, max(ctx->fd, ctx->dst_fd));
		ctx = ctx->next;
	}
	return max_fd;
}

static void
pxy_thr_print_info(pxy_thr_ctx_t *tctx)
{
	log_finest_main_va("thr=%d, load=%zu", tctx->id, tctx->load);

	evutil_socket_t max_fd = 0;
	time_t max_atime = 0;
	time_t max_ctime = 0;

	char *smsg = NULL;

	if (tctx->conns) {
		time_t now = time(NULL);

		pxy_conn_ctx_t *ctx = tctx->conns;
		while (ctx) {
			time_t atime = now - ctx->atime;
			time_t ctime = now - ctx->ctime;

//#ifndef WITHOUT_USERAUTH
//			log_finest_main_va("PARENT CONN: thr=%d, id=%llu, fd=%d, child_fd=%d, dst=%d, srvdst=%d, child_src=%d, child_dst=%d, p=%d-%d-%d c=%d-%d, ce=%d cc=%d, at=%lld ct=%lld, src_addr=%s:%s, dst_addr=%s:%s, user=%s, valid=%d",
//				tctx->id, ctx->id, ctx->fd, ctx->child_fd, ctx->dst_fd, ctx->srvdst_fd, ctx->child_src_fd, ctx->child_dst_fd,
//				ctx->src.closed, ctx->dst.closed, ctx->srvdst.closed, ctx->children ? ctx->children->src.closed : 0, ctx->children ? ctx->children->dst.closed : 0,
//				ctx->children ? 1:0, ctx->child_count, (long long)atime, (long long)ctime,
//				STRORDASH(ctx->srchost_str), STRORDASH(ctx->srcport_str), STRORDASH(ctx->dsthost_str), STRORDASH(ctx->dstport_str),
//				STRORDASH(ctx->user), ctx->protoctx->is_valid);
//#else /* WITHOUT_USERAUTH */
			log_finest_main_va("PARENT CONN: thr=%d, id=%llu, fd=%d, child_fd=%d, dst=%d, srvdst=%d, child_src=%d, child_dst=%d, p=%d-%d-%d c=%d-%d, ce=%d cc=%d, at=%lld ct=%lld, src_addr=%s:%s, dst_addr=%s:%s, valid=%d",
				tctx->id, ctx->id, ctx->fd, ctx->child_fd, ctx->dst_fd, ctx->srvdst_fd, ctx->child_src_fd, ctx->child_dst_fd,
				ctx->src.closed, ctx->dst.closed, ctx->srvdst.closed, ctx->children ? ctx->children->src.closed : 0, ctx->children ? ctx->children->dst.closed : 0,
				ctx->children ? 1:0, ctx->child_count, (long long)atime, (long long)ctime,
				STRORDASH(ctx->srchost_str), STRORDASH(ctx->srcport_str), STRORDASH(ctx->dsthost_str), STRORDASH(ctx->dstport_str),
				ctx->protoctx->is_valid);
//#endif /* WITHOUT_USERAUTH */

			// @attention Report idle connections only, i.e. the conns which have been idle since the last time we checked for expired conns
			if (atime >= (time_t)tctx->thrmgr->global->expired_conn_check_period) {
				if (asprintf(&smsg, "IDLE: atime=%lld, ctime=%lld, src_addr=%s:%s, dst_addr=%s:%s, "
//#ifndef WITHOUT_USERAUTH
//						"user=%s, "
//#endif /* !WITHOUT_USERAUTH */
						"valid=%d\n",
						(long long)atime, (long long)ctime,
						STRORDASH(ctx->srchost_str), STRORDASH(ctx->srcport_str), STRORDASH(ctx->dsthost_str), STRORDASH(ctx->dstport_str),
//#ifndef WITHOUT_USERAUTH
//						STRORDASH(ctx->user),
//#endif /* !WITHOUT_USERAUTH */
						ctx->protoctx->is_valid) < 0) {
					return;
				}
				if (log_conn(smsg) == -1) {
					log_err_level_printf(LOG_WARNING, "Idle conn logging failed\n");
				}
				free(smsg);
				smsg = NULL;
			}

			// child_src_fd and child_dst_fd fields are mostly for debugging purposes, used in debug printing parent conns.
			// However, while an ssl child is closing, the children list may be empty, but child's ssl fd may be still open,
			// hence we include those fields in this max comparisons too
			max_fd = max(max_fd, max(ctx->fd, max(ctx->dst_fd, max(ctx->srvdst_fd, max(ctx->child_fd, max(ctx->child_src_fd, ctx->child_dst_fd))))));
			max_atime = util_max(max_atime, atime);
			max_ctime = util_max(max_ctime, ctime);

			if (ctx->children) {
				// @attention Do not pass pxy_thr_print_children() to MAX() or util_max() macro functions as param, or else it is called twice
				// Use the inline max() function instead
				max_fd = max(max_fd, pxy_thr_print_children(ctx->children));
			}
			ctx = ctx->next;
		}
	}

	log_finest_main_va("thr=%d, mld=%zu, mfd=%d, mat=%lld, mct=%lld, iib=%llu, iob=%llu, eib=%llu, eob=%llu, swm=%zu, uwm=%zu, to=%zu, err=%zu, si=%u",
			tctx->id, tctx->max_load, tctx->max_fd, (long long)max_atime, (long long)max_ctime, tctx->intif_in_bytes, tctx->intif_out_bytes, tctx->extif_in_bytes, tctx->extif_out_bytes,
			tctx->set_watermarks, tctx->unset_watermarks, tctx->timedout_conns, tctx->errors, tctx->stats_id);

	if (asprintf(&smsg, "STATS: thr=%d, mld=%zu, mfd=%d, mat=%lld, mct=%lld, iib=%llu, iob=%llu, eib=%llu, eob=%llu, swm=%zu, uwm=%zu, to=%zu, err=%zu, si=%u\n",
			tctx->id, tctx->max_load, tctx->max_fd, (long long)max_atime, (long long)max_ctime, tctx->intif_in_bytes, tctx->intif_out_bytes, tctx->extif_in_bytes, tctx->extif_out_bytes,
			tctx->set_watermarks, tctx->unset_watermarks, tctx->timedout_conns, tctx->errors, tctx->stats_id) < 0) {
		return;
	}
	if (log_stats(smsg) == -1) {
		log_err_level_printf(LOG_WARNING, "Stats logging failed\n");
	}
	free(smsg);

	tctx->stats_id++;

	tctx->timedout_conns = 0;
	tctx->errors = 0;
	tctx->set_watermarks = 0;
	tctx->unset_watermarks = 0;

	tctx->intif_in_bytes = 0;
	tctx->intif_out_bytes = 0;
	tctx->extif_in_bytes = 0;
	tctx->extif_out_bytes = 0;

	// Reset these stats with the current values (do not reset to 0 directly, there may be active conns)
	tctx->max_fd = max_fd;
	tctx->max_load = tctx->load;
}

/*
 * Recurring timer event to prevent the event loops from exiting when they run out of events.
 子线程事件回调，重复计时器事件，以防止事件循环在耗尽事件时退出。
 */
static void
pxy_thr_timer_cb(UNUSED evutil_socket_t fd, UNUSED short what, UNUSED void *arg)
{
	pxy_thr_ctx_t *tctx = arg;

	log_finest_main_va("thr=%d, load=%zu, to=%u", tctx->id, tctx->load, tctx->timeout_count);

	pxy_conn_ctx_t *expired = NULL;
	pxy_thr_get_expired_conns(tctx, &expired);

#ifdef DEBUG_PROXY
	if (expired) {
		time_t now = time(NULL);
#endif /* DEBUG_PROXY */
		while (expired) {
			pxy_conn_ctx_t *next = expired->next_expired;

			log_fine_main_va("Delete timed out conn thr=%d, fd=%d, child_fd=%d, at=%lld ct=%lld",
				expired->thr->id, expired->fd, expired->child_fd, (long long)(now - expired->atime), (long long)(now - expired->ctime));

			// @attention Do not call the term function here, free the conn directly
			pxy_conn_free(expired, 1);
			tctx->timedout_conns++;

			expired = next;
		}
#ifdef DEBUG_PROXY
	}
#endif /* DEBUG_PROXY */

	// @attention Print thread info only if stats logging is enabled, if disabled debug logs are not printed either
	if (tctx->thrmgr->global->statslog) {
		tctx->timeout_count++;
		if (tctx->timeout_count >= tctx->thrmgr->global->stats_period) {
			tctx->timeout_count = 0;
			pxy_thr_print_info(tctx);
		}
	}
}

/*
 * Thread entry point; runs the event loop of the event base.
 * Does not exit until the libevent loop is broken explicitly.
 线程入口点;运行event base的事件循环。在libevent循环被显式破坏之前不会退出。
 */
void *
pxy_thr(void *arg)
{
	pxy_thr_ctx_t *tctx = arg;
	struct timeval timer_delay = {tctx->thrmgr->global->expired_conn_check_period, 0};
	struct event *ev;

	ev = event_new(tctx->evbase, -1, EV_PERSIST, pxy_thr_timer_cb, tctx);
	if (!ev)
		return NULL;
	evtimer_add(ev, &timer_delay);
	tctx->running = 1;
	event_base_dispatch(tctx->evbase);
	event_free(ev);

	return NULL;
}

/* vim: set noet ft=c: */
