/*-
 */

#include "cert.h"

#include "ssl.h"

#include <string.h>

/*
 * Certificate, including private key and certificate chain.
 */

cert_t *
cert_new(void)
{
	cert_t *c;

	if (!(c = malloc(sizeof(cert_t))))
		return NULL;
	memset(c, 0, sizeof(cert_t));
	if (pthread_mutex_init(&c->mutex, NULL)) {
		free(c);
		return NULL;
	}
	c->references = 1;
	return c;
}

/*
 * Passed OpenSSL objects are owned by cert_t; refcount will not be
 * incremented, stack will not be duplicated.
 */
cert_t *
cert_new3(EVP_PKEY *key, X509 *crt, STACK_OF(X509) *chain)
{
	cert_t *c;

	if (!(c = malloc(sizeof(cert_t))))
		return NULL;
	if (pthread_mutex_init(&c->mutex, NULL)) {
		free(c);
		return NULL;
	}
	c->key = key;
	c->crt = crt;
	c->chain = chain;
	c->references = 1;
	return c;
}

/*
 * Passed OpenSSL objects are copied by cert_t; crt/key refcount will be
 * incremented, stack will be duplicated.
 */
cert_t *
cert_new3_copy(EVP_PKEY *key, X509 *crt, STACK_OF(X509) *chain)
{
	cert_t *c;

	if (!(c = malloc(sizeof(cert_t))))
		return NULL;
	if (pthread_mutex_init(&c->mutex, NULL)) {
		free(c);
		return NULL;
	}
	c->key = key;
	ssl_key_refcount_inc(c->key);
	c->crt = crt;
	ssl_x509_refcount_inc(c->crt);
	c->chain = sk_X509_dup(chain);
	for (int i = 0; i < sk_X509_num(c->chain); i++) {
		ssl_x509_refcount_inc(sk_X509_value(c->chain, i));
	}
	c->references = 1;
	return c;
}

/*
 * Load cert_t from file.
 */
cert_t *
cert_new_load(const char *filename)
{
	cert_t *c;

	if (!(c = malloc(sizeof(cert_t))))
		return NULL;
	memset(c, 0, sizeof(cert_t));
	if (pthread_mutex_init(&c->mutex, NULL)) {
		free(c);
		return NULL;
	}

	if (ssl_x509chain_load(&c->crt, &c->chain, filename) == -1) {
		free(c);
		return NULL;
	}
	c->key = ssl_key_load(filename);
	if (!c->key) {
		X509_free(c->crt);
		if (c->chain) {
			sk_X509_pop_free(c->chain, X509_free);
		}
		free(c);
		return NULL;
	}
	c->references = 1;
	return c;
}

/*
 * Increment reference count.
 */
void
cert_refcount_inc(cert_t *c)
{
	pthread_mutex_lock(&c->mutex);
	c->references++;
	pthread_mutex_unlock(&c->mutex);
}

/*
 * Thread-safe setter functions; they copy the value (refcounts are inc'd).
 */
void
cert_set_key(cert_t *c, EVP_PKEY *key)
{
	pthread_mutex_lock(&c->mutex);
	if (c->key) {
		EVP_PKEY_free(c->key);
	}
	c->key = key;
	if (c->key) {
		ssl_key_refcount_inc(c->key);
	}
	pthread_mutex_unlock(&c->mutex);
}
void
cert_set_crt(cert_t *c, X509 *crt)
{
	pthread_mutex_lock(&c->mutex);
	if (c->crt) {
		X509_free(c->crt);
	}
	c->crt = crt;
	if (c->crt) {
		ssl_x509_refcount_inc(c->crt);
	}
	pthread_mutex_unlock(&c->mutex);
}
void
cert_set_chain(cert_t *c, STACK_OF(X509) *chain)
{
	pthread_mutex_lock(&c->mutex);
	if (c->chain) {
		sk_X509_pop_free(c->chain, X509_free);
	}
	if (chain) {
		c->chain = sk_X509_dup(chain);
		for (int i = 0; i < sk_X509_num(c->chain); i++) {
			ssl_x509_refcount_inc(sk_X509_value(c->chain, i));
		}
	} else {
		c->chain = NULL;
	}
	pthread_mutex_unlock(&c->mutex);
}

/*
 * Free cert including internal objects.
 */
void
cert_free(cert_t *c)
{
	pthread_mutex_lock(&c->mutex);
	c->references--;
	if (c->references) {
		pthread_mutex_unlock(&c->mutex);
		return;
	}
	pthread_mutex_unlock(&c->mutex);
	pthread_mutex_destroy(&c->mutex);
	if (c->key) {
		EVP_PKEY_free(c->key);
	}
	if (c->crt) {
		X509_free(c->crt);
	}
	if (c->chain) {
		sk_X509_pop_free(c->chain, X509_free);
	}
	free(c);
}

/* vim: set noet ft=c: */
