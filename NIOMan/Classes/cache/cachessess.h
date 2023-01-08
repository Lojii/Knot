/*-
 */

#ifndef CACHESSESS_H
#define CACHESSESS_H

#include "cache.h"
#include "attrib.h"

#include <openssl/ssl.h>

void cachessess_init_cb(struct cache *) NONNULL(1);

cache_key_t cachessess_mkkey(const unsigned char *, const size_t)
            NONNULL(1) WUNRES;
cache_val_t cachessess_mkval(SSL_SESSION *) NONNULL(1) WUNRES;

#endif /* !CACHESSESS_H */

/* vim: set noet ft=c: */
