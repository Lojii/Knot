/*-
 */

#include "cache.h"

#include "log.h"
#include "khash.h"

#include <pthread.h>

/*
 * Generic, thread-safe cache.
 */

/*
 * Create a new cache based on the initializer callback init_cb.
 */
cache_t *
cache_new(cache_init_cb_t init_cb)
{
	cache_t *cache;

	if (!(cache = malloc(sizeof(cache_t))))
		return NULL;

	if (pthread_mutex_init(&cache->mutex, NULL)) {
		free(cache);
		return NULL;
	}

	init_cb(cache);
	return cache;
}

/*
 * Reinitialize cache after fork().  Returns 0 on success, -1 on failure.
 */
int
cache_reinit(cache_t *cache)
{
	return pthread_mutex_init(&cache->mutex, NULL) ? -1 : 0;
}

/*
 * Free a cache and all associated resources.
 * This function is not thread-safe.
 */
void
cache_free(cache_t *cache)
{
	khiter_t it;

	for (it = cache->begin_cb(); it != cache->end_cb(); it++) {
		if (cache->exist_cb(it)) {
			cache->free_key_cb(cache->get_key_cb(it));
			cache->free_val_cb(cache->get_val_cb(it));
		}
	}
	cache->fini_cb();
	pthread_mutex_destroy(&cache->mutex);
	free(cache);
}

void
cache_gc(cache_t *cache)
{
	khiter_t it;
	cache_val_t val;

	pthread_mutex_lock(&cache->mutex);
	for (it = cache->begin_cb(); it != cache->end_cb(); it++) {
		if (cache->exist_cb(it)) {
			val = cache->get_val_cb(it);
			if (!cache->unpackverify_val_cb(val, 0)) {
				cache->free_val_cb(val);
				cache->free_key_cb(cache->get_key_cb(it));
				cache->del_cb(it);
			}
		}
	}
	pthread_mutex_unlock(&cache->mutex);
}

cache_val_t
cache_get(cache_t *cache, cache_key_t key)
{
	cache_val_t rval = NULL;
	khiter_t it;

	if (!key)
		return NULL;

	pthread_mutex_lock(&cache->mutex);
	it = cache->get_cb(key);
	if (it != cache->end_cb()) {
		cache_val_t val;
		val = cache->get_val_cb(it);
		if (!(rval = cache->unpackverify_val_cb(val, 1))) {
			cache->free_val_cb(val);
			cache->free_key_cb(cache->get_key_cb(it));
			cache->del_cb(it);
		}
	}
	cache->free_key_cb(key);
	pthread_mutex_unlock(&cache->mutex);
	return rval;
}

void
cache_set(cache_t *cache, cache_key_t key, cache_val_t val)
{
	khiter_t it;
	int ret;

	if (!key || !val)
		return;

	pthread_mutex_lock(&cache->mutex);
	it = cache->put_cb(key, &ret);
	if (!ret) {
		cache->free_key_cb(key);
		cache->free_val_cb(cache->get_val_cb(it));
	}
	cache->set_val_cb(it, val);
	pthread_mutex_unlock(&cache->mutex);
}

void
cache_del(cache_t *cache, cache_key_t key)
{
	khiter_t it;

	pthread_mutex_lock(&cache->mutex);
	it = cache->get_cb(key);
	if (it != cache->end_cb()) {
		cache->free_val_cb(cache->get_val_cb(it));
		cache->free_key_cb(cache->get_key_cb(it));
		cache->del_cb(it);
	}
	cache->free_key_cb(key);
	pthread_mutex_unlock(&cache->mutex);
}

/* vim: set noet ft=c: */
