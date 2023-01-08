/*-
 */

#ifndef CERT_H
#define CERT_H

#include "attrib.h"

#include <openssl/ssl.h>
#include <pthread.h>

typedef struct cert {
	EVP_PKEY *key;
	X509 *crt;
	STACK_OF(X509) * chain;
	pthread_mutex_t mutex;
	size_t references;
} cert_t;

cert_t * cert_new(void) MALLOC;
cert_t * cert_new_load(const char *) MALLOC;
cert_t * cert_new3(EVP_PKEY *, X509 *, STACK_OF(X509) *) MALLOC;
cert_t * cert_new3_copy(EVP_PKEY *, X509 *, STACK_OF(X509) *) MALLOC;
void cert_refcount_inc(cert_t *) NONNULL(1);
void cert_set_key(cert_t *, EVP_PKEY *) NONNULL(1);
void cert_set_crt(cert_t *, X509 *) NONNULL(1);
void cert_set_chain(cert_t *, STACK_OF(X509) *) NONNULL(1);
void cert_free(cert_t *) NONNULL(1);

#endif /* !CERT_H */

/* vim: set noet ft=c: */
