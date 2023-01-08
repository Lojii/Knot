/*-
 */

#ifndef CACHETGCRT_H
#define CACHETGCRT_H

#include "cache.h"
#include "attrib.h"
#include "cert.h"

void cachetgcrt_init_cb(struct cache *) NONNULL(1);

cache_key_t cachetgcrt_mkkey(const char *) NONNULL(1) WUNRES;
cache_val_t cachetgcrt_mkval(cert_t *) NONNULL(1) WUNRES;

#endif /* !CACHETGCRT_H */

/* vim: set noet ft=c: */
