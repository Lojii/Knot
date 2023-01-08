/*-
 */

#include "cachetgcrt.h"

#include "ssl.h"
#include "khash.h"

/*
 * Cache for target cert / chain / key tuples read from configured directory.
 * This cache does not need garbage collection.
 *
 * key: char *    common name
 * val: cert_t *  cert / chain / key tuple
 */

KHASH_INIT(cstrmap_t, char*, void*, 1, kh_str_hash_func, kh_str_hash_equal)

static khash_t(cstrmap_t) *certmap;

static cache_iter_t
cachetgcrt_begin_cb(void)
{
	return kh_begin(certmap);
}

static cache_iter_t
cachetgcrt_end_cb(void)
{
	return kh_end(certmap);
}

static int
cachetgcrt_exist_cb(cache_iter_t it)
{
	return kh_exist(certmap, it);
}

static void
cachetgcrt_del_cb(cache_iter_t it)
{
	kh_del(cstrmap_t, certmap, it);
}

static cache_iter_t
cachetgcrt_get_cb(cache_key_t key)
{
	return kh_get(cstrmap_t, certmap, key);
}

static cache_iter_t
cachetgcrt_put_cb(cache_key_t key, int *ret)
{
	return kh_put(cstrmap_t, certmap, key, ret);
}

static void
cachetgcrt_free_key_cb(cache_key_t key)
{
	free(key);
}

static void
cachetgcrt_free_val_cb(cache_val_t val)
{
	cert_free(val);
}

static cache_key_t
cachetgcrt_get_key_cb(cache_iter_t it)
{
	return kh_key(certmap, it);
}

static cache_val_t
cachetgcrt_get_val_cb(cache_iter_t it)
{
	return kh_val(certmap, it);
}

static void
cachetgcrt_set_val_cb(cache_iter_t it, cache_val_t val)
{
	kh_val(certmap, it) = val;
}

static cache_val_t
cachetgcrt_unpackverify_val_cb(cache_val_t val, int copy)
{
	if (copy) {
		cert_refcount_inc(val);
		return val;
	}
	return ((void*)-1);
}

static void
cachetgcrt_fini_cb(void)
{
	kh_destroy(cstrmap_t, certmap);
}

void
cachetgcrt_init_cb(cache_t *cache)
{
	certmap = kh_init(cstrmap_t);

	cache->begin_cb                 = cachetgcrt_begin_cb;
	cache->end_cb                   = cachetgcrt_end_cb;
	cache->exist_cb                 = cachetgcrt_exist_cb;
	cache->del_cb                   = cachetgcrt_del_cb;
	cache->get_cb                   = cachetgcrt_get_cb;
	cache->put_cb                   = cachetgcrt_put_cb;
	cache->free_key_cb              = cachetgcrt_free_key_cb;
	cache->free_val_cb              = cachetgcrt_free_val_cb;
	cache->get_key_cb               = cachetgcrt_get_key_cb;
	cache->get_val_cb               = cachetgcrt_get_val_cb;
	cache->set_val_cb               = cachetgcrt_set_val_cb;
	cache->unpackverify_val_cb      = cachetgcrt_unpackverify_val_cb;
	cache->fini_cb                  = cachetgcrt_fini_cb;
}

cache_key_t
cachetgcrt_mkkey(const char *keycn)
{
	return strdup(keycn);
}

cache_val_t
cachetgcrt_mkval(cert_t *valcrt)
{
	cert_refcount_inc(valcrt);
	return valcrt;
}

/* vim: set noet ft=c: */
