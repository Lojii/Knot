/*-
 */

#ifndef CACHEMGR_H
#define CACHEMGR_H

#include "cache.h"
#include "cachefkcrt.h"
#include "cachetgcrt.h"
#include "cachessess.h"
#include "cachedsess.h"

extern cache_t *cachemgr_fkcrt;
extern cache_t *cachemgr_tgcrt;
extern cache_t *cachemgr_ssess;
extern cache_t *cachemgr_dsess;

int cachemgr_preinit(void) WUNRES;
int cachemgr_init(void) WUNRES;
void cachemgr_fini(void);
void cachemgr_gc(void);

#define cachemgr_fkcrt_get(key) \
        cache_get(cachemgr_fkcrt, cachefkcrt_mkkey(key))
#define cachemgr_fkcrt_set(key, val) \
        cache_set(cachemgr_fkcrt, cachefkcrt_mkkey(key), cachefkcrt_mkval(val))
#define cachemgr_fkcrt_del(key) \
        cache_del(cachemgr_fkcrt, cachefkcrt_mkkey(key))

#define cachemgr_tgcrt_get(key) \
        cache_get(cachemgr_tgcrt, cachetgcrt_mkkey(key))
#define cachemgr_tgcrt_set(key, val) \
        cache_set(cachemgr_tgcrt, cachetgcrt_mkkey(key), cachetgcrt_mkval(val))
#define cachemgr_tgcrt_del(key) \
        cache_del(cachemgr_tgcrt, cachetgcrt_mkkey(key))

#define cachemgr_ssess_get(key, keysz) \
        cache_get(cachemgr_ssess, cachessess_mkkey((key), (keysz)))
#define cachemgr_ssess_set(val) \
        { \
                unsigned int len; \
                const unsigned char* id = SSL_SESSION_get_id(val, &len); \
                cache_set(cachemgr_ssess, \
                          cachessess_mkkey(id, len), \
                          cachessess_mkval(val));    \
        }
#define cachemgr_ssess_del(val) \
        { \
                unsigned int len; \
                const unsigned char* id = SSL_SESSION_get_id(val, &len); \
                cache_del(cachemgr_ssess, \
                          cachessess_mkkey(id, len)); \
        }
#define cachemgr_dsess_get(addr, addrlen, sni) \
        cache_get(cachemgr_dsess, cachedsess_mkkey((addr), (addrlen), (sni)))
#define cachemgr_dsess_set(addr, addrlen, sni, val) \
        cache_set(cachemgr_dsess, cachedsess_mkkey((addr), (addrlen), (sni)), \
                                  cachedsess_mkval(val))
#define cachemgr_dsess_del(addr, addrlen, sni) \
        cache_del(cachemgr_dsess, cachedsess_mkkey((addr), (addrlen), (sni)))

#endif /* !CACHEMGR_H */

/* vim: set noet ft=c: */
