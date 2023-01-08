/*-
 */

#include "cachemgr.h"

#include "cachefkcrt.h"
#include "cachetgcrt.h"
#include "cachessess.h"
#include "cachedsess.h"
#include "log.h"
#include "attrib.h"

#include <string.h>
#include <pthread.h>

#include <netinet/in.h>

cache_t *cachemgr_fkcrt;
cache_t *cachemgr_tgcrt;
cache_t *cachemgr_ssess;
cache_t *cachemgr_dsess;

/*
 * Garbage collector thread entry point.
 * Calls the _gc() method on the cache passed as argument, then returns.
 */
static void *
cachemgr_gc_thread(UNUSED void * arg)
{
	cache_gc(arg);
	return NULL;
}

/*
 * Pre-initialize the caches.
 * The caches may be initialized before or after libevent and OpenSSL.
 * Returns -1 on error, 0 on success.
 */
int
cachemgr_preinit(void)
{
	if (!(cachemgr_fkcrt = cache_new(cachefkcrt_init_cb)))
		goto out4;
	if (!(cachemgr_tgcrt = cache_new(cachetgcrt_init_cb)))
		goto out3;
	if (!(cachemgr_ssess = cache_new(cachessess_init_cb)))
		goto out2;
	if (!(cachemgr_dsess = cache_new(cachedsess_init_cb)))
		goto out1;
	return 0;

out1:
	cache_free(cachemgr_ssess);
out2:
	cache_free(cachemgr_tgcrt);
out3:
	cache_free(cachemgr_fkcrt);
out4:
	return -1;
}

/*
 * Post-fork initialization.
 * Returns -1 on error, 0 on success.
 */
int
cachemgr_init(void)
{
	if (cache_reinit(cachemgr_fkcrt))
		return -1;
	if (cache_reinit(cachemgr_tgcrt))
		return -1;
	if (cache_reinit(cachemgr_ssess))
		return -1;
	if (cache_reinit(cachemgr_dsess))
		return -1;
	return 0;
}

/*
 * Cleanup the caches and free all memory.  Since OpenSSL certificates are
 * being freed, this must be done before calling the OpenSSL cleanup methods.
 * Also, it is not safe to call this while cachemgr_gc() is still running.
 */
void
cachemgr_fini(void)
{
	cache_free(cachemgr_dsess);
	cache_free(cachemgr_ssess);
	cache_free(cachemgr_tgcrt);
	cache_free(cachemgr_fkcrt);
}

/*
 * Garbage collect all the cache contents; free's up resources occupied by
 * certificates and sessions which are no longer valid.
 * This function returns after the cleanup completed and all threads are
 * joined.
 */
void
cachemgr_gc(void)
{
	pthread_t fkcrt_thr, dsess_thr, ssess_thr;
	int rv;

	/* the tgcrt cache does not need cleanup */

	rv = pthread_create(&fkcrt_thr, NULL, cachemgr_gc_thread,
	                    cachemgr_fkcrt);
	if (rv) {
		log_err_level_printf(LOG_CRIT, "cachemgr_gc: pthread_create failed: %s\n",
		               strerror(rv));
	}
	rv = pthread_create(&ssess_thr, NULL, cachemgr_gc_thread,
	                    cachemgr_ssess);
	if (rv) {
		log_err_level_printf(LOG_CRIT, "cachemgr_gc: pthread_create failed: %s\n",
		               strerror(rv));
	}
	rv = pthread_create(&dsess_thr, NULL, cachemgr_gc_thread,
	                    cachemgr_dsess);
	if (rv) {
		log_err_level_printf(LOG_CRIT, "cachemgr_gc: pthread_create failed: %s\n",
		               strerror(rv));
	}

	rv = pthread_join(fkcrt_thr, NULL);
	if (rv) {
		log_err_level_printf(LOG_CRIT, "cachemgr_gc: pthread_join failed: %s\n",
		               strerror(rv));
	}
	rv = pthread_join(ssess_thr, NULL);
	if (rv) {
		log_err_level_printf(LOG_CRIT, "cachemgr_gc: pthread_join failed: %s\n",
		               strerror(rv));
	}
	rv = pthread_join(dsess_thr, NULL);
	if (rv) {
		log_err_level_printf(LOG_CRIT, "cachemgr_gc: pthread_join failed: %s\n",
		               strerror(rv));
	}
}

/* vim: set noet ft=c: */
