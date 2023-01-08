/*-
 */

#include "protossl.h"
#include "prototcp.h"
#include "protopassthrough.h"
#include "util.h"
#include "cachemgr.h"
#include <netdb.h>
#include <sys/socket.h>
#include <arpa/inet.h>

#include <string.h>
#include <sys/param.h>
#include <event2/bufferevent_ssl.h>

/*
 * Context used for all server sessions.
 */
#ifdef USE_SSL_SESSION_ID_CONTEXT
static unsigned long ssl_session_context = 0x31415926;
#endif /* USE_SSL_SESSION_ID_CONTEXT */

void
protossl_log_ssl_error(struct bufferevent *bev, pxy_conn_ctx_t *ctx)
{
	unsigned long sslerr;

	/* Can happen for socket errs, ssl errs;
	 * may happen for unclean ssl socket shutdowns. */
	sslerr = bufferevent_get_openssl_error(bev);
	if (sslerr)
		ctx->sslctx->have_sslerr = 1;
	if (!errno && !sslerr) {
#if LIBEVENT_VERSION_NUMBER >= 0x02010000
		/* We have disabled notification for unclean shutdowns
		 * so this should not happen; log a warning. */
		log_err_level_printf(LOG_WARNING, "Spurious error from bufferevent (errno=0,sslerr=0)\n");
#else /* LIBEVENT_VERSION_NUMBER < 0x02010000 */
		/* Older versions of libevent will report these. */
		if (OPTS_DEBUG(ctx->global)) {
			log_dbg_printf("Unclean SSL shutdown, fd=%d\n", ctx->fd);
		}
#endif /* LIBEVENT_VERSION_NUMBER < 0x02010000 */
	} else if (ERR_GET_REASON(sslerr) == SSL_R_SSLV3_ALERT_HANDSHAKE_FAILURE) {
		/* these can happen due to client cert auth,
		 * only log error if debugging is activated */
		log_dbg_printf("Error from bufferevent: %i:%s %lu:%i:%s:%i:%s:%i:%s\n",
					   errno, errno ? strerror(errno) : "-", sslerr,
					   ERR_GET_REASON(sslerr), STRORDASH(ERR_reason_error_string(sslerr)),
					   ERR_GET_LIB(sslerr), STRORDASH(ERR_lib_error_string(sslerr)),
					   ERR_GET_FUNC(sslerr), STRORDASH(ERR_func_error_string(sslerr)));
		while ((sslerr = bufferevent_get_openssl_error(bev))) {
			log_dbg_printf("Additional SSL error: %lu:%i:%s:%i:%s:%i:%s\n",
						   sslerr,
						   ERR_GET_REASON(sslerr), STRORDASH(ERR_reason_error_string(sslerr)),
						   ERR_GET_LIB(sslerr), STRORDASH(ERR_lib_error_string(sslerr)),
						   ERR_GET_FUNC(sslerr), STRORDASH(ERR_func_error_string(sslerr)));
		}
	} else {
		/* real errors */
		log_err_printf("Error from bufferevent: %i:%s %lu:%i:%s:%i:%s:%i:%s\n",
					   errno, errno ? strerror(errno) : "-",
					   sslerr,
					   ERR_GET_REASON(sslerr), STRORDASH(ERR_reason_error_string(sslerr)),
					   ERR_GET_LIB(sslerr), STRORDASH(ERR_lib_error_string(sslerr)),
					   ERR_GET_FUNC(sslerr), STRORDASH(ERR_func_error_string(sslerr)));
		while ((sslerr = bufferevent_get_openssl_error(bev))) {
			log_err_printf("Additional SSL error: %lu:%i:%s:%i:%s:%i:%s\n",
						   sslerr,
						   ERR_GET_REASON(sslerr), STRORDASH(ERR_reason_error_string(sslerr)),
						   ERR_GET_LIB(sslerr), STRORDASH(ERR_lib_error_string(sslerr)),
						   ERR_GET_FUNC(sslerr), STRORDASH(ERR_func_error_string(sslerr)));
		}
	}
	if (ctx->spec->opts->filter && !ctx->pass) {
		log_err_level_printf(LOG_WARNING, "Closing on ssl error without filter match: %s:%s, %s:%s, "
//#ifndef WITHOUT_USERAUTH
//			"%s, %s, "
//#endif /* !WITHOUT_USERAUTH */
			"%s, %s\n",
			STRORDASH(ctx->srchost_str), STRORDASH(ctx->srcport_str), STRORDASH(ctx->dsthost_str), STRORDASH(ctx->dstport_str),
//#ifndef WITHOUT_USERAUTH
//			STRORDASH(ctx->user), STRORDASH(ctx->desc),
//#endif /* !WITHOUT_USERAUTH */
			STRORDASH(ctx->sslctx->sni), STRORDASH(ctx->sslctx->ssl_names));
	}
}

int
protossl_log_masterkey(pxy_conn_ctx_t *ctx, pxy_conn_desc_t *this)
{
	// XXX: Remove ssl check? But the caller function is called by non-ssl protos.
	if (this->ssl) {
		/* log master key */
		if (ctx->log_master && ctx->global->masterkeylog) {
			char *keystr;
			keystr = ssl_ssl_masterkey_to_str(this->ssl);
			if ((keystr == NULL) ||
				(log_masterkey_print_free(keystr) == -1)) {
				if (errno == ENOMEM)
					ctx->enomem = 1;
				pxy_conn_term(ctx, 1);
				return -1;
			}
		}
	}
	return 0;
}

/* forward declaration of OpenSSL callbacks */
#ifndef OPENSSL_NO_TLSEXT
static int protossl_ossl_servername_cb(SSL *ssl, int *al, void *arg);
#endif /* !OPENSSL_NO_TLSEXT */
static int protossl_ossl_sessnew_cb(SSL *, SSL_SESSION *);
static void protossl_ossl_sessremove_cb(SSL_CTX *, SSL_SESSION *);
#if (OPENSSL_VERSION_NUMBER < 0x10100000L) || (defined(LIBRESSL_VERSION_NUMBER) && LIBRESSL_VERSION_NUMBER < 0x20800000L)
static SSL_SESSION * protossl_ossl_sessget_cb(SSL *, unsigned char *, int, int *);
#else /* OPENSSL_VERSION_NUMBER >= 0x10100000L */
static SSL_SESSION * protossl_ossl_sessget_cb(SSL *, const unsigned char *, int, int *);
#endif /* OPENSSL_VERSION_NUMBER >= 0x10100000L */

/*
 * Dump information on a certificate to the debug log.
 */
static void
protossl_debug_crt(X509 *crt)
{
	char *sj = ssl_x509_subject(crt);
	if (sj) {
		log_dbg_printf("Subject DN: %s\n", sj);
		free(sj);
	}

	char *names = ssl_x509_names_to_str(crt);
	if (names) {
		log_dbg_printf("Common Names: %s\n", names);
		free(names);
	}

	char *fpr;
	if (!(fpr = ssl_x509_fingerprint(crt, 1))) {
		log_err_level_printf(LOG_WARNING, "Error generating X509 fingerprint\n");
	} else {
		log_dbg_printf("Fingerprint: %s\n", fpr);
		free(fpr);
	}

#ifdef DEBUG_CERTIFICATE
	/* dump certificate */
	log_dbg_print_free(ssl_x509_to_str(crt));
	log_dbg_print_free(ssl_x509_to_pem(crt));
#endif /* DEBUG_CERTIFICATE */
}

/*
 * Called by OpenSSL when a new src SSL session is created.
 * OpenSSL increments the refcount before calling the callback and will
 * decrement it again if we return 0.  Returning 1 will make OpenSSL skip
 * the refcount decrementing.  In other words, return 0 if we did not
 * keep a pointer to the object (which we never do here).
 */
#ifdef HAVE_SSLV2
#define MAYBE_UNUSED 
#else /* !HAVE_SSLV2 */
#define MAYBE_UNUSED UNUSED
#endif /* !HAVE_SSLV2 */
static int
protossl_ossl_sessnew_cb(MAYBE_UNUSED SSL *ssl, SSL_SESSION *sess)
#undef MAYBE_UNUSED
{
#ifdef DEBUG_SESSION_CACHE
	log_dbg_printf("===> OpenSSL new session callback:\n");
	if (sess) {
		log_dbg_print_free(ssl_session_to_str(sess));
	} else {
		log_dbg_printf("(null)\n");
	}
#endif /* DEBUG_SESSION_CACHE */
#ifdef HAVE_SSLV2
	/* Session resumption seems to fail for SSLv2 with protocol
	 * parsing errors, so we disable caching for SSLv2. */
	if (SSL_version(ssl) == SSL2_VERSION) {
		log_err_level_printf(LOG_WARNING, "Session resumption denied to SSLv2"
		               "client.\n");
		return 0;
	}
#endif /* HAVE_SSLV2 */
	if (sess) {
		cachemgr_ssess_set(sess);
	}
	return 0;
}

/*
 * Called by OpenSSL when a src SSL session should be removed.
 * OpenSSL calls SSL_SESSION_free() after calling the callback;
 * we do not need to free the reference here.
 */
static void
protossl_ossl_sessremove_cb(UNUSED SSL_CTX *sslctx, SSL_SESSION *sess)
{
#ifdef DEBUG_SESSION_CACHE
	log_dbg_printf("===> OpenSSL remove session callback:\n");
	if (sess) {
		log_dbg_print_free(ssl_session_to_str(sess));
	} else {
		log_dbg_printf("(null)\n");
	}
#endif /* DEBUG_SESSION_CACHE */
	if (sess) {
		cachemgr_ssess_del(sess);
	}
}

/*
 * Called by OpenSSL when a src SSL session is requested by the client.
 */
static SSL_SESSION *
#if (OPENSSL_VERSION_NUMBER < 0x10100000L) || (defined(LIBRESSL_VERSION_NUMBER) && LIBRESSL_VERSION_NUMBER < 0x20800000L)
protossl_ossl_sessget_cb(UNUSED SSL *ssl, unsigned char *id, int idlen, int *copy)
#else /* OPENSSL_VERSION_NUMBER >= 0x10100000L */
protossl_ossl_sessget_cb(UNUSED SSL *ssl, const unsigned char *id, int idlen, int *copy)
#endif /* OPENSSL_VERSION_NUMBER >= 0x10100000L */
{
	SSL_SESSION *sess;

#ifdef DEBUG_SESSION_CACHE
	log_dbg_printf("===> OpenSSL get session callback:\n");
#endif /* DEBUG_SESSION_CACHE */

	*copy = 0; /* SSL should not increment reference count of session */
	sess = cachemgr_ssess_get(id, idlen);

#ifdef DEBUG_SESSION_CACHE
	if (sess) {
		log_dbg_print_free(ssl_session_to_str(sess));
	}
#endif /* DEBUG_SESSION_CACHE */

	log_dbg_printf("SSL session cache: %s\n", sess ? "HIT" : "MISS");
	return sess;
}

/*
 * Set SSL_CTX options that are the same for incoming and outgoing SSL_CTX.
 */
static void
protossl_sslctx_setoptions(SSL_CTX *sslctx, pxy_conn_ctx_t *ctx)
{
	SSL_CTX_set_options(sslctx, SSL_OP_ALL);
#ifdef SSL_OP_TLS_ROLLBACK_BUG
	SSL_CTX_set_options(sslctx, SSL_OP_TLS_ROLLBACK_BUG);
#endif /* SSL_OP_TLS_ROLLBACK_BUG */
#ifdef SSL_OP_ALLOW_UNSAFE_LEGACY_RENEGOTIATION
	SSL_CTX_set_options(sslctx, SSL_OP_ALLOW_UNSAFE_LEGACY_RENEGOTIATION);
#endif /* SSL_OP_ALLOW_UNSAFE_LEGACY_RENEGOTIATION */
#ifdef SSL_OP_DONT_INSERT_EMPTY_FRAGMENTS
	SSL_CTX_set_options(sslctx, SSL_OP_DONT_INSERT_EMPTY_FRAGMENTS);
#endif /* SSL_OP_DONT_INSERT_EMPTY_FRAGMENTS */
#ifdef SSL_OP_NO_TICKET
	SSL_CTX_set_options(sslctx, SSL_OP_NO_TICKET);
#endif /* SSL_OP_NO_TICKET */

#ifdef SSL_OP_NO_SSLv2
#ifdef HAVE_SSLV2
	if (ctx->conn_opts->no_ssl2) {
#endif /* HAVE_SSLV2 */
		SSL_CTX_set_options(sslctx, SSL_OP_NO_SSLv2);
#ifdef HAVE_SSLV2
	}
#endif /* HAVE_SSLV2 */
#endif /* !SSL_OP_NO_SSLv2 */
#ifdef HAVE_SSLV3
	if (ctx->conn_opts->no_ssl3) {
		SSL_CTX_set_options(sslctx, SSL_OP_NO_SSLv3);
	}
#endif /* HAVE_SSLV3 */
#ifdef HAVE_TLSV10
	if (ctx->conn_opts->no_tls10) {
		SSL_CTX_set_options(sslctx, SSL_OP_NO_TLSv1);
	}
#endif /* HAVE_TLSV10 */
#ifdef HAVE_TLSV11
	if (ctx->conn_opts->no_tls11) {
		SSL_CTX_set_options(sslctx, SSL_OP_NO_TLSv1_1);
	}
#endif /* HAVE_TLSV11 */
#ifdef HAVE_TLSV12
	if (ctx->conn_opts->no_tls12) {
		SSL_CTX_set_options(sslctx, SSL_OP_NO_TLSv1_2);
	}
#endif /* HAVE_TLSV12 */
#ifdef HAVE_TLSV13
	if (ctx->conn_opts->no_tls13) {
		SSL_CTX_set_options(sslctx, SSL_OP_NO_TLSv1_3);
	}
#endif /* HAVE_TLSV13 */

#ifdef SSL_OP_NO_COMPRESSION
	if (!ctx->conn_opts->sslcomp) {
		SSL_CTX_set_options(sslctx, SSL_OP_NO_COMPRESSION);
	}
#endif /* SSL_OP_NO_COMPRESSION */

	SSL_CTX_set_cipher_list(sslctx, ctx->conn_opts->ciphers);
#ifdef HAVE_TLSV13
	SSL_CTX_set_ciphersuites(sslctx, ctx->conn_opts->ciphersuites);
#endif /* HAVE_TLSV13 */

#if (OPENSSL_VERSION_NUMBER >= 0x10100000L) && !defined(LIBRESSL_VERSION_NUMBER)
	/* If the security level of OpenSSL is set to 2+ in system configuration, 
	 * our forged certificates with 1024-bit RSA key size will be rejected */
	SSL_CTX_set_security_level(sslctx, 1);
#endif /* OPENSSL_VERSION_NUMBER >= 0x10100000L */
}

/*
 * Create and set up a new SSL_CTX instance for terminating SSL.
 * Set up all the necessary callbacks, the certificate, the cert chain and key.
 */
static SSL_CTX *
protossl_srcsslctx_create(pxy_conn_ctx_t *ctx, X509 *crt, STACK_OF(X509) *chain,
                     EVP_PKEY *key)
{
	SSL_CTX *sslctx = SSL_CTX_new(ctx->conn_opts->sslmethod());
	if (!sslctx) {
		ctx->enomem = 1;
		return NULL;
	}

	protossl_sslctx_setoptions(sslctx, ctx);

#if (OPENSSL_VERSION_NUMBER >= 0x10100000L && !defined(LIBRESSL_VERSION_NUMBER)) || (defined(LIBRESSL_VERSION_NUMBER) && LIBRESSL_VERSION_NUMBER >= 0x20702000L)
	if (ctx->conn_opts->minsslversion) {
		if (SSL_CTX_set_min_proto_version(sslctx, ctx->conn_opts->minsslversion) == 0) {
			SSL_CTX_free(sslctx);
			return NULL;
		}
	}
	if (ctx->conn_opts->maxsslversion) {
		if (SSL_CTX_set_max_proto_version(sslctx, ctx->conn_opts->maxsslversion) == 0) {
			SSL_CTX_free(sslctx);
			return NULL;
		}
	}
	// ForceSSLproto has precedence
	if (ctx->conn_opts->sslversion) {
		if (SSL_CTX_set_min_proto_version(sslctx, ctx->conn_opts->sslversion) == 0 ||
			SSL_CTX_set_max_proto_version(sslctx, ctx->conn_opts->sslversion) == 0) {
			SSL_CTX_free(sslctx);
			return NULL;
		}
	}
#endif /* OPENSSL_VERSION_NUMBER >= 0x10100000L */

	SSL_CTX_sess_set_new_cb(sslctx, protossl_ossl_sessnew_cb);
	SSL_CTX_sess_set_remove_cb(sslctx, protossl_ossl_sessremove_cb);
	SSL_CTX_sess_set_get_cb(sslctx, protossl_ossl_sessget_cb);
	SSL_CTX_set_session_cache_mode(sslctx, SSL_SESS_CACHE_SERVER |
	                                       SSL_SESS_CACHE_NO_INTERNAL);
#ifdef USE_SSL_SESSION_ID_CONTEXT
	SSL_CTX_set_session_id_context(sslctx, (void *)(&ssl_session_context),
	                                       sizeof(ssl_session_context));
#endif /* USE_SSL_SESSION_ID_CONTEXT */
#ifndef OPENSSL_NO_TLSEXT
	SSL_CTX_set_tlsext_servername_callback(sslctx, protossl_ossl_servername_cb);
	SSL_CTX_set_tlsext_servername_arg(sslctx, ctx);
#endif /* !OPENSSL_NO_TLSEXT */
#ifndef OPENSSL_NO_DH
	if (ctx->conn_opts->dh) {
		SSL_CTX_set_tmp_dh(sslctx, ctx->conn_opts->dh);
	} else {
		SSL_CTX_set_tmp_dh_callback(sslctx, ssl_tmp_dh_callback);
	}
#endif /* !OPENSSL_NO_DH */
#ifndef OPENSSL_NO_ECDH
	if (ctx->conn_opts->ecdhcurve) {
		EC_KEY *ecdh = ssl_ec_by_name(ctx->conn_opts->ecdhcurve);
		SSL_CTX_set_tmp_ecdh(sslctx, ecdh);
		EC_KEY_free(ecdh);
	} else {
		EC_KEY *ecdh = ssl_ec_by_name(NULL);
		SSL_CTX_set_tmp_ecdh(sslctx, ecdh);
		EC_KEY_free(ecdh);
	}
#endif /* !OPENSSL_NO_ECDH */
	if (SSL_CTX_use_certificate(sslctx, crt) != 1) {
		log_dbg_printf("loading src server certificate failed\n");
		SSL_CTX_free(sslctx);
		return NULL;
	}
	if (SSL_CTX_use_PrivateKey(sslctx, key) != 1) {
		log_dbg_printf("loading src server key failed\n");
		SSL_CTX_free(sslctx);
		return NULL;
	}
	for (int i = 0; i < sk_X509_num(chain); i++) {
		X509 *c = sk_X509_value(chain, i);
		ssl_x509_refcount_inc(c); /* next call consumes a reference */
		SSL_CTX_add_extra_chain_cert(sslctx, c);
	}

#ifdef DEBUG_SESSION_CACHE
	if (OPTS_DEBUG(ctx->global)) {
		int mode = SSL_CTX_get_session_cache_mode(sslctx);
		log_dbg_printf("SSL session cache mode: %08x\n", mode);
		if (mode == SSL_SESS_CACHE_OFF)
			log_dbg_printf("SSL_SESS_CACHE_OFF\n");
		if (mode & SSL_SESS_CACHE_CLIENT)
			log_dbg_printf("SSL_SESS_CACHE_CLIENT\n");
		if (mode & SSL_SESS_CACHE_SERVER)
			log_dbg_printf("SSL_SESS_CACHE_SERVER\n");
		if (mode & SSL_SESS_CACHE_NO_AUTO_CLEAR)
			log_dbg_printf("SSL_SESS_CACHE_NO_AUTO_CLEAR\n");
		if (mode & SSL_SESS_CACHE_NO_INTERNAL_LOOKUP)
			log_dbg_printf("SSL_SESS_CACHE_NO_INTERNAL_LOOKUP\n");
		if (mode & SSL_SESS_CACHE_NO_INTERNAL_STORE)
			log_dbg_printf("SSL_SESS_CACHE_NO_INTERNAL_STORE\n");
	}
#endif /* DEBUG_SESSION_CACHE */

	return sslctx;
}

static int
protossl_srccert_write_to_gendir(pxy_conn_ctx_t *ctx, X509 *crt, int is_orig)
{
	char *fn;
	int rv;

	if (!ctx->sslctx->origcrtfpr)
		return -1;
	if (is_orig) {
		rv = asprintf(&fn, "%s/%s.crt", ctx->global->certgendir,
		              ctx->sslctx->origcrtfpr);
	} else {
		if (!ctx->sslctx->usedcrtfpr)
			return -1;
		rv = asprintf(&fn, "%s/%s-%s.crt", ctx->global->certgendir,
		              ctx->sslctx->origcrtfpr, ctx->sslctx->usedcrtfpr);
	}
	if (rv == -1) {
		ctx->enomem = 1;
		return -1;
	}
	rv = log_cert_submit(fn, crt);
	free(fn);
	return rv;
}

void
protossl_srccert_write(pxy_conn_ctx_t *ctx)
{
	if (ctx->global->certgen_writeall || ctx->sslctx->generated_cert) {
		if (protossl_srccert_write_to_gendir(ctx,
		                SSL_get_certificate(ctx->src.ssl), 0) == -1) {
			log_err_level_printf(LOG_CRIT, "Failed to write used certificate\n");
		}
	}
	if (ctx->global->certgen_writeall) {
		if (protossl_srccert_write_to_gendir(ctx, ctx->sslctx->origcrt, 1) == -1) {
			log_err_level_printf(LOG_CRIT, "Failed to write orig certificate\n");
		}
	}
}

static cert_t *
protossl_srccert_create(pxy_conn_ctx_t *ctx)
{
	cert_t *cert = NULL;

	if (ctx->global->leafcertdir) {
		if (ctx->sslctx->sni) {
			cert = cachemgr_tgcrt_get(ctx->sslctx->sni);
			if (!cert) {
				char *wildcarded;
				wildcarded = ssl_wildcardify(ctx->sslctx->sni);
				if (!wildcarded) {
					ctx->enomem = 1;
					return NULL;
				}
				cert = cachemgr_tgcrt_get(wildcarded);
				free(wildcarded);
			}
			if (cert && OPTS_DEBUG(ctx->global)) {
				log_dbg_printf("Target cert by SNI\n");
			}
		} else if (ctx->sslctx->origcrt) {
			char **names = ssl_x509_names(ctx->sslctx->origcrt);
			for (char **p = names; *p; p++) {
				if (!cert) {
					cert = cachemgr_tgcrt_get(*p);
				}
				if (!cert) {
					char *wildcarded;
					wildcarded = ssl_wildcardify(*p);
					if (!wildcarded) {
						ctx->enomem = 1;
					} else {
						/* increases ref count */
						cert = cachemgr_tgcrt_get(
						       wildcarded);
						free(wildcarded);
					}
				}
				free(*p);
			}
			free(names);
			if (ctx->enomem) {
				return NULL;
			}
			if (cert && OPTS_DEBUG(ctx->global)) {
				log_dbg_printf("Target cert by origcrt\n");
			}
		}

		if (cert) {
			ctx->sslctx->immutable_cert = 1;
		}
	}

	if (!cert && ctx->global->defaultleafcert) {
		cert = ctx->global->defaultleafcert;
		cert_refcount_inc(cert);
		ctx->sslctx->immutable_cert = 1;
		if (OPTS_DEBUG(ctx->global)) {
			log_dbg_printf("Using default leaf certificate\n");
		}
	}

	if (!cert && ctx->sslctx->origcrt && ctx->global->leafkey) {
		cert = cert_new();

		cert->crt = cachemgr_fkcrt_get(ctx->sslctx->origcrt);
		if (cert->crt) {
			if (OPTS_DEBUG(ctx->global))
				log_dbg_printf("Certificate cache: HIT\n");
		} else {
			if (OPTS_DEBUG(ctx->global))
				log_dbg_printf("Certificate cache: MISS\n");
			cert->crt = ssl_x509_forge(ctx->conn_opts->cacrt,
			                           ctx->conn_opts->cakey,
			                           ctx->sslctx->origcrt,
			                           ctx->global->leafkey,
			                           NULL,
			                           ctx->conn_opts->leafcrlurl);
			cachemgr_fkcrt_set(ctx->sslctx->origcrt, cert->crt);
		}
		cert_set_key(cert, ctx->global->leafkey);
		cert_set_chain(cert, ctx->conn_opts->chain);
		ctx->sslctx->generated_cert = 1;
	}

	if ((WANT_CONNECT_LOG(ctx) || ctx->global->certgendir) && ctx->sslctx->origcrt) {
		ctx->sslctx->origcrtfpr = ssl_x509_fingerprint(ctx->sslctx->origcrt, 0);
		if (!ctx->sslctx->origcrtfpr)
			ctx->enomem = 1;
	}
	if ((WANT_CONNECT_LOG(ctx) || ctx->global->certgen_writeall) &&
	    cert && cert->crt) {
		ctx->sslctx->usedcrtfpr = ssl_x509_fingerprint(cert->crt, 0);
		if (!ctx->sslctx->usedcrtfpr)
			ctx->enomem = 1;
	}

	return cert;
}

static filter_action_t * NONNULL(1,2)
protossl_filter_match_sni(pxy_conn_ctx_t *ctx, filter_list_t *list)
{
	filter_site_t *site = filter_site_find(list->sni_btree, list->sni_acm, list->sni_all, ctx->sslctx->sni);
	if (!site)
		return NULL;

//#ifndef WITHOUT_USERAUTH
//	log_fine_va("Found site (line=%d): %s for %s:%s, %s:%s, %s, %s, %s", site->action.line_num, site->site,
//		STRORDASH(ctx->srchost_str), STRORDASH(ctx->srcport_str), STRORDASH(ctx->dsthost_str), STRORDASH(ctx->dstport_str),
//		STRORDASH(ctx->user), STRORDASH(ctx->desc), STRORDASH(ctx->sslctx->sni));
//#else /* WITHOUT_USERAUTH */
	log_fine_va("Found site (line=%d): %s for %s:%s, %s:%s, %s", site->action.line_num, site->site,
		STRORDASH(ctx->srchost_str), STRORDASH(ctx->srcport_str), STRORDASH(ctx->dsthost_str), STRORDASH(ctx->dstport_str),
		STRORDASH(ctx->sslctx->sni));
//#endif /* WITHOUT_USERAUTH */

	if (!site->port_btree && !site->port_acm && (site->action.precedence < ctx->filter_precedence)) {
		log_finest_va("Rule precedence lower than conn filter precedence %d < %d (line=%d): %s, %s", site->action.precedence, ctx->filter_precedence, site->action.line_num, site->site, ctx->sslctx->sni);
		return NULL;
	}

#ifdef DEBUG_PROXY
	if (site->all_sites)
		log_finest_va("Match all sni (line=%d): %s, %s", site->action.line_num, site->site, ctx->sslctx->sni);
	else if (site->exact)
		log_finest_va("Match exact with sni (line=%d): %s, %s", site->action.line_num, site->site, ctx->sslctx->sni);
	else
		log_finest_va("Match substring in sni (line=%d): %s, %s", site->action.line_num, site->site, ctx->sslctx->sni);
#endif /* DEBUG_PROXY */

	filter_action_t *port_action = pxy_conn_filter_port(ctx, site);
	if (port_action)
		return port_action;

	return &site->action;
}

static filter_action_t * NONNULL(1,2)
protossl_filter_match_cn(pxy_conn_ctx_t *ctx, filter_list_t *list)
{
	filter_site_t *site = NULL;

// ballpark figures
#define MAX_CN_LEN 4096
#define MAX_CN_TOKENS 100

	int argc = 0;
	char *p, *last = NULL;

	size_t len = strlen(ctx->sslctx->ssl_names);

	if (len > MAX_CN_LEN) {
		log_err_level_printf(LOG_WARNING, "Skip too long common names, max len %d: %s\n", MAX_CN_LEN, ctx->sslctx->ssl_names);
		return NULL;
	}

	// Do not tokenize ssl_names if there is no rule to match exact common names
	if (list->cn_btree) {
		// strtok_r() modifies the string param, so copy ssl_names to a local var and pass it to strtok_r()
		char _cn[len + 1];
		memcpy(_cn, ctx->sslctx->ssl_names, len);
		_cn[len] = '\0';

		for ((p = strtok_r(_cn, "/", &last));
			 p;
			 (p = strtok_r(NULL, "/", &last))) {
			if (argc++ < MAX_CN_TOKENS) {
				site = filter_site_exact_match(list->cn_btree, p);
				if (site) {
					log_finest_va("Match exact with common name (%d) (line=%d): %s, %s", argc, site->action.line_num, p, ctx->sslctx->ssl_names);
					break;
				}
			}
			else {
				log_err_level_printf(LOG_WARNING, "Too many tokens in common names, max tokens %d: %s\n", MAX_CN_TOKENS, ctx->sslctx->ssl_names);
				break;
			}
		}
	}

	if (!site) {
		site = filter_site_substring_match(list->cn_acm, ctx->sslctx->ssl_names);
		if (site)
			log_finest_va("Match substring in common names (line=%d): %s, %s", site->action.line_num, site->site, ctx->sslctx->ssl_names);
	}

	if (!site)
		return NULL;

//#ifndef WITHOUT_USERAUTH
//	log_fine_va("Found site (line=%d): %s for %s:%s, %s:%s, %s, %s, %s", site->action.line_num, site->site,
//		STRORDASH(ctx->srchost_str), STRORDASH(ctx->srcport_str), STRORDASH(ctx->dsthost_str), STRORDASH(ctx->dstport_str),
//		STRORDASH(ctx->user), STRORDASH(ctx->desc), STRORDASH(ctx->sslctx->ssl_names));
//#else /* WITHOUT_USERAUTH */
	log_fine_va("Found site (line=%d): %s for %s:%s, %s:%s, %s", site->action.line_num, site->site,
		STRORDASH(ctx->srchost_str), STRORDASH(ctx->srcport_str), STRORDASH(ctx->dsthost_str), STRORDASH(ctx->dstport_str),
		STRORDASH(ctx->sslctx->ssl_names));
//#endif /* WITHOUT_USERAUTH */

	if (!site->port_btree && !site->port_acm && (site->action.precedence < ctx->filter_precedence)) {
		log_finest_va("Rule precedence lower than conn filter precedence %d < %d (line=%d): %s, %s", site->action.precedence, ctx->filter_precedence, site->action.line_num, site->site, ctx->sslctx->ssl_names);
		return NULL;
	}

	if (site->all_sites)
		log_finest_va("Match all common names (line=%d): %s, %s", site->action.line_num, site->site, ctx->sslctx->ssl_names);

	filter_action_t *port_action = pxy_conn_filter_port(ctx, site);
	if (port_action)
		return port_action;

	return &site->action;
}

static filter_action_t * NONNULL(1,2)
protossl_filter(pxy_conn_ctx_t *ctx, filter_list_t *list)
{
	filter_action_t *action_sni = NULL;
	filter_action_t *action_cn = NULL;

	if (ctx->sslctx->sni) {
		if (!(action_sni = protossl_filter_match_sni(ctx, list))) {
//#ifndef WITHOUT_USERAUTH
//			log_finest_va("No filter match with sni: %s:%s, %s:%s, %s, %s, %s, %s",
//				STRORDASH(ctx->srchost_str), STRORDASH(ctx->srcport_str), STRORDASH(ctx->dsthost_str), STRORDASH(ctx->dstport_str),
//				STRORDASH(ctx->user), STRORDASH(ctx->desc), STRORDASH(ctx->sslctx->sni), STRORDASH(ctx->sslctx->ssl_names));
//#else /* WITHOUT_USERAUTH */
			log_finest_va("No filter match with sni: %s:%s, %s:%s, %s, %s",
				STRORDASH(ctx->srchost_str), STRORDASH(ctx->srcport_str), STRORDASH(ctx->dsthost_str), STRORDASH(ctx->dstport_str),
				STRORDASH(ctx->sslctx->sni), STRORDASH(ctx->sslctx->ssl_names));
//#endif /* !WITHOUT_USERAUTH */
		}
	}

	if (ctx->sslctx->ssl_names) {
		if (!(action_cn = protossl_filter_match_cn(ctx, list))) {
//#ifndef WITHOUT_USERAUTH
//			log_finest_va("No filter match with common names: %s:%s, %s:%s, %s, %s, %s, %s",
//				STRORDASH(ctx->srchost_str), STRORDASH(ctx->srcport_str), STRORDASH(ctx->dsthost_str), STRORDASH(ctx->dstport_str),
//				STRORDASH(ctx->user), STRORDASH(ctx->desc), STRORDASH(ctx->sslctx->sni), STRORDASH(ctx->sslctx->ssl_names));
//#else /* WITHOUT_USERAUTH */
			log_finest_va("No filter match with common names: %s:%s, %s:%s, %s, %s",
				STRORDASH(ctx->srchost_str), STRORDASH(ctx->srcport_str), STRORDASH(ctx->dsthost_str), STRORDASH(ctx->dstport_str),
				STRORDASH(ctx->sslctx->sni), STRORDASH(ctx->sslctx->ssl_names));
//#endif /* !WITHOUT_USERAUTH */
		}
	}

	if (action_sni ||  action_cn)
		return pxy_conn_set_filter_action(action_sni, action_cn
#ifdef DEBUG_PROXY
				, ctx, ctx->sslctx->sni, ctx->sslctx->ssl_names
#endif /* DEBUG_PROXY */
				);

	return NULL;
}

static void
protossl_reconnect_srvdst(pxy_conn_ctx_t *ctx)
{
	log_fine("ENTER");

	// Reconnect only once
	ctx->sslctx->reconnected = 1;

	ctx->srvdst.zfree(ctx->srvdst.bev, ctx);
	ctx->srvdst.bev = NULL;
	ctx->srvdst.ssl = NULL;
	ctx->connected = 0;

	if (protossl_conn_connect(ctx) == -1) {
		return;
	}

	if (bufferevent_socket_connect(ctx->srvdst.bev, (struct sockaddr *)&ctx->dstaddr, ctx->dstaddrlen) == -1) {
		log_err_level(LOG_CRIT, "bufferevent_socket_connect for srvdst failed");
		pxy_conn_term(ctx, 1);
	}
}

static int
protossl_apply_filter(pxy_conn_ctx_t *ctx)
{
	int rv = 0;
	filter_action_t *a;
	if ((a = pxy_conn_filter(ctx, protossl_filter))) {
		unsigned int action = pxy_conn_translate_filter_action(ctx, a);

		ctx->filter_precedence = action & FILTER_PRECEDENCE;

		if (action & FILTER_ACTION_DIVERT) {
			ctx->deferred_action = FILTER_ACTION_NONE;
			ctx->divert = 1;
		}
		else if (action & FILTER_ACTION_SPLIT) {
			ctx->deferred_action = FILTER_ACTION_NONE;
			ctx->divert = 0;
		}
		else if (action & FILTER_ACTION_PASS) {
			ctx->deferred_action = FILTER_ACTION_NONE;
			ctx->pass = 1;
			rv = 1;
		}
		else if (action & FILTER_ACTION_BLOCK) {
			// Always defer block action, the only action we can defer from this point on
			// This block action should override any deferred pass action,
			// because the current rule must have a higher precedence
			log_fine("Deferring block action");
			ctx->deferred_action = FILTER_ACTION_BLOCK;
		}
		//else { /* FILTER_ACTION_MATCH */ }

		// Filtering rules at higher precedence can enable/disable logging
		if (action & FILTER_LOG_CONNECT)
			ctx->log_connect = 1;
		else if (action & FILTER_LOG_NOCONNECT)
			ctx->log_connect = 0;
		if (action & FILTER_LOG_MASTER)
			ctx->log_master = 1;
		else if (action & FILTER_LOG_NOMASTER)
			ctx->log_master = 0;
		if (action & FILTER_LOG_CERT)
			ctx->log_cert = 1;
		else if (action & FILTER_LOG_NOCERT)
			ctx->log_cert = 0;
		if (action & FILTER_LOG_CONTENT)
			ctx->log_content = 1;
		else if (action & FILTER_LOG_NOCONTENT)
			ctx->log_content = 0;
		if (action & FILTER_LOG_PCAP)
			ctx->log_pcap = 1;
		else if (action & FILTER_LOG_NOPCAP)
			ctx->log_pcap = 0;

		if (a->conn_opts) {
			ctx->conn_opts = a->conn_opts;

			if (ctx->conn_opts->reconnect_ssl) {
				// Reconnect srvdst only once, if ReconnectSSL set in the rule
				if (!ctx->sslctx->reconnected) {
					protossl_reconnect_srvdst(ctx);
					// Return immediately to avoid applying deferred pass action
					return 1;
				} else {
					log_finest("Already reconnected once, will not reconnect again");
				}
			}
		}
	}

	// Cannot defer pass action any longer
	// Match action should not override pass action, hence no 'else if'
	if (ctx->deferred_action & FILTER_ACTION_PASS) {
		log_fine("Applying deferred pass action");
		ctx->deferred_action = FILTER_ACTION_NONE;
		ctx->pass = 1;
		rv = 1;
	}

	return rv;
}

/*
 * Create new SSL context for the incoming connection, based on the original
 * destination SSL certificate.
 * Returns NULL if no suitable certificate could be found or the site should 
 * be passed through.
 */
static SSL *
protossl_srcssl_create(pxy_conn_ctx_t *ctx, SSL *origssl)
{
	cert_t *cert;

	cachemgr_dsess_set((struct sockaddr*)&ctx->dstaddr,
	                   ctx->dstaddrlen, ctx->sslctx->sni,
	                   SSL_get0_session(origssl));

	ctx->sslctx->origcrt = SSL_get_peer_certificate(origssl);

	if (OPTS_DEBUG(ctx->global)) {
		if (ctx->sslctx->origcrt) {
			log_dbg_printf("===> Original server certificate:\n");
			protossl_debug_crt(ctx->sslctx->origcrt);
		} else {
			log_dbg_printf("===> Original server has no cert!\n");
		}
	}

	cert = protossl_srccert_create(ctx);
	if (!cert)
		return NULL;

	if (OPTS_DEBUG(ctx->global)) {
		log_dbg_printf("===> Forged server certificate:\n");
		protossl_debug_crt(cert->crt);
	}

	if (WANT_CONNECT_LOG(ctx) || ctx->spec->opts->filter) {
		ctx->sslctx->ssl_names = ssl_x509_names_to_str(ctx->sslctx->origcrt ?
		                                       ctx->sslctx->origcrt :
		                                       cert->crt);
		if (!ctx->sslctx->ssl_names)
			ctx->enomem = 1;
	}

	// Defers any block action until HTTP filter application
	// or until the first src readcb of non-http protos
	if (protossl_apply_filter(ctx)) {
		cert_free(cert);
		return NULL;
	}

	SSL_CTX *sslctx = protossl_srcsslctx_create(ctx, cert->crt, cert->chain,
	                                       cert->key);
	cert_free(cert);
	if (!sslctx)
		return NULL;
	SSL *ssl = SSL_new(sslctx);
	SSL_CTX_free(sslctx); /* SSL_new() increments refcount */
	if (!ssl) {
		ctx->enomem = 1;
		return NULL;
	}
#ifdef SSL_MODE_RELEASE_BUFFERS
	/* lower memory footprint for idle connections */
	SSL_set_mode(ssl, SSL_get_mode(ssl) | SSL_MODE_RELEASE_BUFFERS);
#endif /* SSL_MODE_RELEASE_BUFFERS */
	return ssl;
}

#ifndef OPENSSL_NO_TLSEXT
/*
 * OpenSSL servername callback, called when OpenSSL receives a servername
 * TLS extension in the clientHello.  Must switch to a new SSL_CTX with
 * a different certificate if we want to replace the server cert here.
 * We generate a new certificate if the current one does not match the
 * supplied servername.  This should only happen if the original destination
 * server supplies a certificate which does not match the server name we
 * indicate to it.
 */
static int
protossl_ossl_servername_cb(SSL *ssl, UNUSED int *al, void *arg)
{
	pxy_conn_ctx_t *ctx = arg;
	const char *sn;
	X509 *sslcrt;

	if (!(sn = SSL_get_servername(ssl, TLSEXT_NAMETYPE_host_name)))
		return SSL_TLSEXT_ERR_NOACK;

	if (!ctx->sslctx->sni) {
		if (OPTS_DEBUG(ctx->global)) {
			log_dbg_printf("Warning: SNI parser yielded no "
			               "hostname, copying OpenSSL one: "
			               "[NULL] != [%s]\n", sn);
		}
		ctx->sslctx->sni = strdup(sn);
		if (!ctx->sslctx->sni) {
			ctx->enomem = 1;
			return SSL_TLSEXT_ERR_NOACK;
		}
	}
	if (OPTS_DEBUG(ctx->global)) {
		if (!!strcmp(sn, ctx->sslctx->sni)) {
			/*
			 * This may happen if the client resumes a session, but
			 * uses a different SNI hostname when resuming than it
			 * used when the session was created.  OpenSSL
			 * correctly ignores the SNI in the ClientHello in this
			 * case, but since we have already sent the SNI onwards
			 * to the original destination, there is no way back.
			 * We log an error and hope this never happens.
			 */
			log_dbg_printf("Warning: SNI parser yielded different "
			               "hostname than OpenSSL callback for "
			               "the same ClientHello message: "
			               "[%s] != [%s]\n", ctx->sslctx->sni, sn);
		}
	}

	/* generate a new certificate with sn as additional altSubjectName
	 * and replace it both in the current SSL ctx and in the cert cache */
	if (ctx->conn_opts->allow_wrong_host && !ctx->sslctx->immutable_cert &&
	    !ssl_x509_names_match((sslcrt = SSL_get_certificate(ssl)), sn)) {
		X509 *newcrt;
		SSL_CTX *newsslctx;

		if (OPTS_DEBUG(ctx->global)) {
			log_dbg_printf("Certificate cache: UPDATE "
			               "(SNI mismatch)\n");
		}
		newcrt = ssl_x509_forge(ctx->conn_opts->cacrt, ctx->conn_opts->cakey,
		                        sslcrt, ctx->global->leafkey,
		                        sn, ctx->conn_opts->leafcrlurl);
		if (!newcrt) {
			ctx->enomem = 1;
			return SSL_TLSEXT_ERR_NOACK;
		}
		cachemgr_fkcrt_set(ctx->sslctx->origcrt, newcrt);
		ctx->sslctx->generated_cert = 1;
		if (OPTS_DEBUG(ctx->global)) {
			log_dbg_printf("===> Updated forged server "
			               "certificate:\n");
			protossl_debug_crt(newcrt);
		}
		if (WANT_CONNECT_LOG(ctx) || ctx->spec->opts->filter) {
			if (ctx->sslctx->ssl_names) {
				free(ctx->sslctx->ssl_names);
			}
			ctx->sslctx->ssl_names = ssl_x509_names_to_str(newcrt);
			if (!ctx->sslctx->ssl_names) {
				ctx->enomem = 1;
			}
		}
		if (WANT_CONNECT_LOG(ctx) || ctx->global->certgendir) {
			if (ctx->sslctx->usedcrtfpr) {
				free(ctx->sslctx->usedcrtfpr);
			}
			ctx->sslctx->usedcrtfpr = ssl_x509_fingerprint(newcrt, 0);
			if (!ctx->sslctx->usedcrtfpr) {
				ctx->enomem = 1;
			}
		}

		newsslctx = protossl_srcsslctx_create(ctx, newcrt, ctx->conn_opts->chain,
		                                 ctx->global->leafkey);
		if (!newsslctx) {
			X509_free(newcrt);
			return SSL_TLSEXT_ERR_NOACK;
		}
		SSL_set_SSL_CTX(ssl, newsslctx); /* decr's old incr new refc */
		SSL_CTX_free(newsslctx);
		X509_free(newcrt);
	} else if (OPTS_DEBUG(ctx->global)) {
		log_dbg_printf("Certificate cache: KEEP (SNI match or "
		               "target mode)\n");
	}

	return SSL_TLSEXT_ERR_OK;
}
#endif /* !OPENSSL_NO_TLSEXT */

/*
 * Create new SSL context for outgoing connections to the original destination.
 * If hostname sni is provided, use it for Server Name Indication.
 * 为发送到原始目的地的连接创建新的SSL上下文。如果主机名sni被提供，则使用它作为服务器名称指示。
 */
SSL *
protossl_dstssl_create(pxy_conn_ctx_t *ctx)
{
	SSL_CTX *sslctx;
	SSL *ssl;
	SSL_SESSION *sess;

	sslctx = SSL_CTX_new(ctx->conn_opts->sslmethod());
	if (!sslctx) {
		ctx->enomem = 1;
		return NULL;
	}

	protossl_sslctx_setoptions(sslctx, ctx);

#if (OPENSSL_VERSION_NUMBER >= 0x10100000L && !defined(LIBRESSL_VERSION_NUMBER)) || (defined(LIBRESSL_VERSION_NUMBER) && LIBRESSL_VERSION_NUMBER >= 0x20702000L)
	if (ctx->conn_opts->minsslversion) {
		if (SSL_CTX_set_min_proto_version(sslctx, ctx->conn_opts->minsslversion) == 0) {
			SSL_CTX_free(sslctx);
			return NULL;
		}
	}
	if (ctx->conn_opts->maxsslversion) {
		if (SSL_CTX_set_max_proto_version(sslctx, ctx->conn_opts->maxsslversion) == 0) {
			SSL_CTX_free(sslctx);
			return NULL;
		}
	}
	// ForceSSLproto has precedence
	if (ctx->conn_opts->sslversion) {
		if (SSL_CTX_set_min_proto_version(sslctx, ctx->conn_opts->sslversion) == 0 ||
			SSL_CTX_set_max_proto_version(sslctx, ctx->conn_opts->sslversion) == 0) {
			SSL_CTX_free(sslctx);
			return NULL;
		}
	}
#endif /* OPENSSL_VERSION_NUMBER >= 0x10100000L */

	if (ctx->conn_opts->verify_peer) {
		SSL_CTX_set_verify(sslctx, SSL_VERIFY_PEER, NULL);
		SSL_CTX_set_default_verify_paths(sslctx);
	} else {
		SSL_CTX_set_verify(sslctx, SSL_VERIFY_NONE, NULL);
	}

	if (ctx->conn_opts->clientcrt &&
	    (SSL_CTX_use_certificate(sslctx, ctx->conn_opts->clientcrt) != 1)) {
		log_dbg_printf("loading dst client certificate failed\n");
		SSL_CTX_free(sslctx);
		return NULL;
	}
	if (ctx->conn_opts->clientkey &&
	    (SSL_CTX_use_PrivateKey(sslctx, ctx->conn_opts->clientkey) != 1)) {
		log_dbg_printf("loading dst client key failed\n");
		SSL_CTX_free(sslctx);
		return NULL;
	}

	ssl = SSL_new(sslctx);
	SSL_CTX_free(sslctx); /* SSL_new() increments refcount */
	if (!ssl) {
		ctx->enomem = 1;
		return NULL;
	}
#ifndef OPENSSL_NO_TLSEXT
	if (ctx->sslctx->sni) {
		SSL_set_tlsext_host_name(ssl, ctx->sslctx->sni);
	}
#endif /* !OPENSSL_NO_TLSEXT */

#ifdef SSL_MODE_RELEASE_BUFFERS
	/* lower memory footprint for idle connections */
	SSL_set_mode(ssl, SSL_get_mode(ssl) | SSL_MODE_RELEASE_BUFFERS);
#endif /* SSL_MODE_RELEASE_BUFFERS */

	/* session resuming based on remote endpoint address and port */
	sess = cachemgr_dsess_get((struct sockaddr *)&ctx->dstaddr,
	                          ctx->dstaddrlen, ctx->sslctx->sni); /* new sess inst */
	if (sess) {
		if (OPTS_DEBUG(ctx->global)) {
			log_dbg_printf("Attempt reuse dst SSL session\n");
		}
		SSL_set_session(ssl, sess); /* increments sess refcount */
		SSL_SESSION_free(sess);
	}

	return ssl;
}

/*
 * Set up a bufferevent structure for either a dst or src connection,
 * optionally with or without SSL.  Sets all callbacks, enables read
 * and write events, but does not call bufferevent_socket_connect().
 *
 * For dst connections, pass -1 as fd.  Pass a pointer to an initialized
 * SSL struct as ssl if the connection should use SSL.
 *
 * Returns pointer to initialized bufferevent structure, as returned
 * by bufferevent_socket_new() or bufferevent_openssl_socket_new().
 */
static struct bufferevent * NONNULL(1,3)
protossl_bufferevent_setup(pxy_conn_ctx_t *ctx, evutil_socket_t fd, SSL *ssl)
{
	log_finest_va("ENTER, fd=%d", fd);

	struct bufferevent *bev = bufferevent_openssl_socket_new(ctx->thr->evbase, fd, ssl,
			((fd == -1) ? BUFFEREVENT_SSL_CONNECTING : BUFFEREVENT_SSL_ACCEPTING), BEV_OPT_DEFER_CALLBACKS);
	if (!bev) {
		log_err_level_printf(LOG_CRIT, "Error creating bufferevent socket\n");
		return NULL;
	}
#if LIBEVENT_VERSION_NUMBER >= 0x02010000
	log_finest_va("bufferevent_openssl_set_allow_dirty_shutdown, fd=%d", fd);

	/* Prevent unclean (dirty) shutdowns to cause error
	 * events on the SSL socket bufferevent. */
	bufferevent_openssl_set_allow_dirty_shutdown(bev, 1);
#endif /* LIBEVENT_VERSION_NUMBER >= 0x02010000 */

	// @attention Do not set callbacks here, we do not set r cb for tcp/ssl srvdst
	//bufferevent_setcb(bev, pxy_bev_readcb, pxy_bev_writecb, pxy_bev_eventcb, ctx);
	// @attention Do not enable r/w events here, we do not set r cb for tcp/ssl srvdst
	// Also, to avoid r/w cb before connected, we should enable r/w events after the conn is connected
	//bufferevent_enable(bev, EV_READ|EV_WRITE);
	return bev;
}

static struct bufferevent * NONNULL(1,3)
protossl_bufferevent_setup_child(pxy_conn_child_ctx_t *ctx, evutil_socket_t fd, SSL *ssl)
{
	log_finest_va("ENTER, fd=%d", fd);

	struct bufferevent *bev = bufferevent_openssl_socket_new(ctx->conn->thr->evbase, fd, ssl,
			((fd == -1) ? BUFFEREVENT_SSL_CONNECTING : BUFFEREVENT_SSL_ACCEPTING), BEV_OPT_DEFER_CALLBACKS);
	if (!bev) {
		log_err_level_printf(LOG_CRIT, "Error creating bufferevent socket\n");
		return NULL;
	}

#if LIBEVENT_VERSION_NUMBER >= 0x02010000
	log_finest_va("bufferevent_openssl_set_allow_dirty_shutdown, fd=%d", fd);

	/* Prevent unclean (dirty) shutdowns to cause error
	 * events on the SSL socket bufferevent. */
	bufferevent_openssl_set_allow_dirty_shutdown(bev, 1);
#endif /* LIBEVENT_VERSION_NUMBER >= 0x02010000 */

	bufferevent_setcb(bev, pxy_bev_readcb_child, pxy_bev_writecb_child, pxy_bev_eventcb_child, ctx);

	// @attention We cannot enable events here, because src events will be deferred until after dst is connected
	// Also, to avoid r/w cb before connected, we should enable r/w events after the conn is connected
	//bufferevent_enable(bev, EV_READ|EV_WRITE);
	return bev;
}

/*
 * Free bufferenvent and close underlying socket properly.
 * For OpenSSL bufferevents, this will shutdown the SSL connection.
 */
static void
protossl_bufferevent_free_and_close_fd(struct bufferevent *bev, pxy_conn_ctx_t *ctx)
{
	SSL *ssl = bufferevent_openssl_get_ssl(bev); /* does not inc refc */
	struct bufferevent *ubev = bufferevent_get_underlying(bev);
	evutil_socket_t fd;

	if (ubev) {
		fd = bufferevent_getfd(ubev);
	} else {
		fd = bufferevent_getfd(bev);
	}

	log_finer_va("in=%zu, out=%zu, fd=%d", evbuffer_get_length(bufferevent_get_input(bev)), evbuffer_get_length(bufferevent_get_output(bev)), fd);

	// @see https://stackoverflow.com/questions/31688709/knowing-all-callbacks-have-run-with-libevent-and-bufferevent-free
	bufferevent_setcb(bev, NULL, NULL, NULL, NULL);

	/*
	 * From the libevent book:  SSL_RECEIVED_SHUTDOWN tells
	 * SSL_shutdown to act as if we had already received a close
	 * notify from the other end.  SSL_shutdown will then send the
	 * final close notify in reply.  The other end will receive the
	 * close notify and send theirs.  By this time, we will have
	 * already closed the socket and the other end's real close
	 * notify will never be received.  In effect, both sides will
	 * think that they have completed a clean shutdown and keep
	 * their sessions valid.  This strategy will fail if the socket
	 * is not ready for writing, in which case this hack will lead
	 * to an unclean shutdown and lost session on the other end.
	 *
	 * Note that in the case of autossl, the SSL object operates on
	 * a BIO wrapper around the underlying bufferevent.
	 */
	SSL_set_shutdown(ssl, SSL_RECEIVED_SHUTDOWN);
	SSL_shutdown(ssl);

	bufferevent_disable(bev, EV_READ|EV_WRITE);
	if (ubev) {
		bufferevent_disable(ubev, EV_READ|EV_WRITE);
		bufferevent_setfd(ubev, -1);
		bufferevent_setcb(ubev, NULL, NULL, NULL, NULL);
		bufferevent_free(ubev);
	}
	bufferevent_free(bev);

	if (OPTS_DEBUG(ctx->global)) {
		char *str = ssl_ssl_state_to_str(ssl, "SSL_free() in state ", 1);
		if (str)
			log_dbg_print_free(str);
	}
#ifdef DEBUG_PROXY
	char *str = ssl_ssl_state_to_str(ssl, "SSL_free() in state ", 0);
	if (str) {
		log_finer_va("fd=%d, %s", fd, str);
		free(str);
	}
#endif /* DEBUG_PROXY */

	SSL_free(ssl);
	/* bufferevent_getfd() returns -1 if no file descriptor is associated
	 * with the bufferevent */
	if (fd >= 0)
		evutil_closesocket(fd);
}

void
protossl_free(pxy_conn_ctx_t *ctx)
{
	if (ctx->sslctx->ssl_names) {
		free(ctx->sslctx->ssl_names);
	}
	if (ctx->sslctx->origcrtfpr) {
		free(ctx->sslctx->origcrtfpr);
	}
	if (ctx->sslctx->usedcrtfpr) {
		free(ctx->sslctx->usedcrtfpr);
	}
	if (ctx->sslctx->origcrt) {
		X509_free(ctx->sslctx->origcrt);
	}
	if (ctx->sslctx->sni) {
		free(ctx->sslctx->sni);
	}
	if (ctx->sslctx->srvdst_ssl_version) {
		free(ctx->sslctx->srvdst_ssl_version);
	}
	if (ctx->sslctx->srvdst_ssl_cipher) {
		free(ctx->sslctx->srvdst_ssl_cipher);
	}
	free(ctx->sslctx);
	// It is necessary to NULL the sslctx to prevent passthrough mode trying to access it (signal 11 crash)
	ctx->sslctx = NULL;
}

#ifndef OPENSSL_NO_TLSEXT
/*
 * The SNI hostname has been resolved.  Fill the first resolved address into the context and continue connecting.
 * SNI主机名已经解析。将第一个解析的地址填入上下文并继续连接。
 */
static void
protossl_sni_resolve_cb(int errcode, struct evutil_addrinfo *ai, void *arg)
{
	pxy_conn_ctx_t *ctx = arg;
//    printf("---> DNS SSL thr:%d - conn:%llu \n", ctx->thr->id,ctx->id);
	log_finest("ENTER");

	if (errcode) {
		log_err_printf("Cannot resolve SNI hostname '%s': %s\n", ctx->sslctx->sni, evutil_gai_strerror(errcode));
		evutil_closesocket(ctx->fd);
		pxy_conn_ctx_free(ctx, 1);
		return;
	}
    
    ctx->dns_time_e = current_time();

	memcpy(&ctx->dstaddr, ai->ai_addr, ai->ai_addrlen);
	ctx->dstaddrlen = ai->ai_addrlen;
	evutil_freeaddrinfo(ai);
	pxy_conn_connect(ctx);
}
#endif /* !OPENSSL_NO_TLSEXT */

/*
 * The src fd is readable.  This is used to sneak-preview the SNI on SSL
 * connections.  If ctx->ev is NULL, it was called manually for a non-SSL
 * connection.  If ctx->opts->passthrough is set, it was called a second time
 * after the first ssl callout failed because of client cert auth.
 */
static void
protossl_fd_readcb(evutil_socket_t fd, UNUSED short what, void *arg)
{
	pxy_conn_ctx_t *ctx = arg;

	log_finest("ENTER");

	event_free(ctx->ev);
	ctx->ev = NULL;

	// Child connections will use the sni info obtained by the parent conn
	/* for SSL, peek ClientHello and parse SNI from it */

	unsigned char buf[1024];
	ssize_t n;
	const unsigned char *chello;
	int rv;

	n = recv(fd, buf, sizeof(buf), MSG_PEEK);
	if (n == -1) {
		log_err_printf("Error peeking on fd, aborting connection\n");
		log_fine("Error peeking on fd, aborting connection");
		goto out;
	}
	if (n == 0) {
		/* socket got closed while we were waiting */
		log_err_printf("Socket got closed while waiting\n");
		log_fine("Socket got closed while waiting");
		goto out;
	}

	rv = ssl_tls_clienthello_parse(buf, n, 0, &chello, &ctx->sslctx->sni);
	if ((rv == 1) && !chello) {
		log_err_printf("Peeking did not yield a (truncated) ClientHello message, aborting connection\n");
		log_fine("Peeking did not yield a (truncated) ClientHello message, aborting connection");
		goto out;
	}
	if (OPTS_DEBUG(ctx->global)) {
		log_dbg_printf("SNI peek: [%s] [%s], fd=%d\n", ctx->sslctx->sni ? ctx->sslctx->sni : "n/a",
					   ((rv == 1) && chello) ? "incomplete" : "complete", ctx->fd);
	}
	if ((rv == 1) && chello && (ctx->sslctx->sni_peek_retries++ < 50)) {
		/* ssl_tls_clienthello_parse indicates that we
		 * should retry later when we have more data, and we
		 * haven't reached the maximum retry count yet.
		 * Reschedule this event as timeout-only event in
		 * order to prevent busy looping over the read event.
		 * Because we only peeked at the pending bytes and
		 * never actually read them, fd is still ready for
		 * reading now.  We use 25 * 0.2 s = 5 s timeout. */
		struct timeval retry_delay = {0, 100};

		ctx->ev = event_new(ctx->thr->evbase, fd, 0, protossl_fd_readcb, ctx);
		if (!ctx->ev) {
			log_err_level(LOG_CRIT, "Error creating retry event, aborting connection");
			goto out;
		}
		if (event_add(ctx->ev, &retry_delay) == -1)
			goto out;
		return;
	}

	if (ctx->sslctx->sni && !ctx->dstaddrlen ) {// && ctx->spec->sni_port
		char sniport[6];
		struct evutil_addrinfo hints;

		memset(&hints, 0, sizeof(hints));
		hints.ai_family = ctx->af;
		hints.ai_flags = EVUTIL_AI_ADDRCONFIG;
		hints.ai_socktype = SOCK_STREAM;
		hints.ai_protocol = IPPROTO_TCP;

        ctx->dns_time_s = current_time();
		snprintf(sniport, sizeof(sniport), "%i", 443);// ctx->spec->sni_port
		evdns_getaddrinfo(ctx->thr->dnsbase, ctx->sslctx->sni, sniport, &hints, protossl_sni_resolve_cb, ctx);
		return;
	}

	pxy_conn_connect(ctx);
	return;
out:
	evutil_closesocket(fd);
	pxy_conn_ctx_free(ctx, 1);
}

void
protossl_init_conn(evutil_socket_t fd, UNUSED short what, void *arg)
{
	pxy_conn_ctx_t *ctx = arg;

	log_finest("ENTER");

	event_free(ctx->ev);
	ctx->ev = NULL;

	if (pxy_conn_init(ctx) == -1)
		return;

#ifdef OPENSSL_NO_TLSEXT
	pxy_conn_connect(ctx);
	return;
#endif /* !OPENSSL_NO_TLSEXT */

	/* for SSL, defer dst connection setup to initial_readcb */
	ctx->ev = event_new(ctx->thr->evbase, ctx->fd, EV_READ, protossl_fd_readcb, ctx);
	if (!ctx->ev)
		goto out;

	if (event_add(ctx->ev, NULL) == -1) {
		log_finest("event_add failed");
		// Note that the timercb of the connection handling thread may try to access the ctx
		goto out;
	}
	return;
out:
	evutil_closesocket(fd);
	pxy_conn_ctx_free(ctx, 1);
}

int
protossl_setup_dst_ssl(pxy_conn_ctx_t *ctx)
{
	ctx->dst.ssl = protossl_dstssl_create(ctx);
	if (!ctx->dst.ssl) {
		log_err_level_printf(LOG_CRIT, "Error creating SSL for dst\n");
		pxy_conn_term(ctx, 1);
		return -1;
	}
	return 0;
}

static int NONNULL(1)
protossl_setup_srvdst_ssl(pxy_conn_ctx_t *ctx)
{
	ctx->srvdst.ssl = protossl_dstssl_create(ctx);
	if (!ctx->srvdst.ssl) {
		log_err_level_printf(LOG_CRIT, "Error creating SSL for srvdst\n");
		pxy_conn_term(ctx, 1);
		return -1;
	}
	return 0;
}

int
protossl_setup_srvdst(pxy_conn_ctx_t *ctx)
{
	if (protossl_setup_srvdst_ssl(ctx) == -1) {
		return -1;
	}

	ctx->srvdst.bev = protossl_bufferevent_setup(ctx, -1, ctx->srvdst.ssl);
	if (!ctx->srvdst.bev) {
		log_err_level_printf(LOG_CRIT, "Error creating srvdst\n");
		SSL_free(ctx->srvdst.ssl);
		ctx->srvdst.ssl = NULL;
		pxy_conn_term(ctx, 1);
		return -1;
	}
	ctx->srvdst.zfree = protossl_bufferevent_free_and_close_fd;
	return 0;
}

int
protossl_conn_connect(pxy_conn_ctx_t *ctx)
{
	log_finest("ENTER");

	/* create server-side socket and eventbuffer */
	if (protossl_setup_srvdst(ctx) == -1) {
		return -1;
	}

	// Disable and NULL r/w cbs, we do nothing for srvdst in r/w cbs
	bufferevent_setcb(ctx->srvdst.bev, NULL, NULL, pxy_bev_eventcb, ctx);
	return 0;
}

int
protossl_setup_dst_ssl_child(pxy_conn_child_ctx_t *ctx)
{
	// Children rely on the findings of parent
	ctx->dst.ssl = protossl_dstssl_create(ctx->conn);
	if (!ctx->dst.ssl) {
		log_err_level_printf(LOG_CRIT, "Error creating SSL\n");
		// pxy_conn_free()>pxy_conn_free_child() will close the fd, since we have a non-NULL src.bev now
		pxy_conn_term(ctx->conn, 1);
		return -1;
	}
	return 0;
}

int
protossl_setup_dst_child(pxy_conn_child_ctx_t *ctx)
{
	if (!ctx->conn->srvdst_xferred) {
		// Reuse srvdst of parent in the first child conn
		ctx->conn->srvdst_xferred = 1;
		ctx->srvdst_xferred = 1;
		ctx->dst = ctx->conn->srvdst;
		bufferevent_setcb(ctx->dst.bev, pxy_bev_readcb_child, pxy_bev_writecb_child, pxy_bev_eventcb_child, ctx);
		ctx->protoctx->bev_eventcb(ctx->dst.bev, BEV_EVENT_CONNECTED, ctx);
	} else {
		if (protossl_setup_dst_ssl_child(ctx) == -1) {
			return -1;
		}

		ctx->dst.bev = protossl_bufferevent_setup_child(ctx, -1, ctx->dst.ssl);
		if (!ctx->dst.bev) {
			log_err_level_printf(LOG_CRIT, "Error creating dst bufferevent\n");
			SSL_free(ctx->dst.ssl);
			ctx->dst.ssl = NULL;
			pxy_conn_term(ctx->conn, 1);
			return -1;
		}
		ctx->dst.zfree = protossl_bufferevent_free_and_close_fd;
	}
	return 0;
}

void
protossl_connect_child(pxy_conn_child_ctx_t *ctx)
{
	log_finest("ENTER");

	/* create server-side socket and eventbuffer */
	protossl_setup_dst_child(ctx);
}

static int NONNULL(1)
protossl_setup_src_ssl(pxy_conn_ctx_t *ctx)
{
	// @todo Make srvdst.ssl the origssl param
	if (ctx->src.ssl || (ctx->src.ssl = protossl_srcssl_create(ctx, ctx->srvdst.ssl))) {
		return 0;
	}
	else if (ctx->term) {
		return -1;
	}
	else if (!ctx->enomem && (ctx->pass || ctx->conn_opts->passthrough)) {
		log_err_level_printf(LOG_WARNING, "Falling back to passthrough\n");
		protopassthrough_engage(ctx);
		// report protocol change by returning 1
		return 1;
	}
	else if (ctx->sslctx->reconnected) {
		return -1;
	}
	pxy_conn_term(ctx, 1);
	return -1;
}

int
protossl_setup_src_ssl_from_dst(pxy_conn_ctx_t *ctx)
{
	// @attention We cannot engage passthrough mode upon ssl errors on already enabled src
	// This function is used by protoautossl only
	if (ctx->src.ssl || (ctx->src.ssl = protossl_srcssl_create(ctx, ctx->dst.ssl))) {
		return 0;
	}
	else if (ctx->term) {
		return -1;
	}
	pxy_conn_term(ctx, 1);
	return -1;
}

int
protossl_setup_src_ssl_from_child_dst(pxy_conn_child_ctx_t *ctx)
{
	// @attention We cannot engage passthrough mode upon ssl errors on already enabled src
	// This function is used by protoautossl only
	if (ctx->conn->src.ssl || (ctx->conn->src.ssl = protossl_srcssl_create(ctx->conn, ctx->dst.ssl))) {
		return 0;
	}
	else if (ctx->conn->term) {
		return -1;
	}
	pxy_conn_term(ctx->conn, 1);
	return -1;
}

static int NONNULL(1)
protossl_setup_src(pxy_conn_ctx_t *ctx)
{
	int rv;
	if ((rv = protossl_setup_src_ssl(ctx)) != 0) {
		return rv;
	}

//	ctx->src.bev = protossl_bufferevent_setup(ctx, ctx->fd, ctx->src.ssl);
//    protossl_setup_src_new_bev_ssl_accepting(ctx);
    if (protossl_setup_src_new_bev_ssl_accepting(ctx) == -1) {
        return -1;
    }
	if (!ctx->src.bev) {
		log_err_level_printf(LOG_CRIT, "Error creating src bufferevent\n");
		SSL_free(ctx->src.ssl);
		ctx->src.ssl = NULL;
		pxy_conn_term(ctx, 1);
		return -1;
	}
	ctx->src.zfree = protossl_bufferevent_free_and_close_fd;
	return 0;
}

int
protossl_setup_src_new_bev_ssl_accepting(pxy_conn_ctx_t *ctx)
{
	ctx->src.bev = bufferevent_openssl_filter_new(ctx->thr->evbase, ctx->src.bev, ctx->src.ssl,
			BUFFEREVENT_SSL_ACCEPTING, BEV_OPT_DEFER_CALLBACKS);
	if (!ctx->src.bev) {
		log_err_level_printf(LOG_CRIT, "Error creating src bufferevent\n");
		SSL_free(ctx->src.ssl);
		ctx->src.ssl = NULL;
		pxy_conn_term(ctx, 1);
		return -1;
	}
	ctx->src.zfree = protossl_bufferevent_free_and_close_fd;
	return 0;
}

int
protossl_setup_dst_new_bev_ssl_connecting(pxy_conn_ctx_t *ctx)
{
	ctx->dst.bev = bufferevent_openssl_filter_new(ctx->thr->evbase, ctx->dst.bev, ctx->dst.ssl,
			BUFFEREVENT_SSL_CONNECTING, BEV_OPT_DEFER_CALLBACKS);
	if (!ctx->dst.bev) {
		log_err_level_printf(LOG_CRIT, "Error creating dst bufferevent\n");
		SSL_free(ctx->dst.ssl);
		ctx->dst.ssl = NULL;
		pxy_conn_term(ctx, 1);
		return -1;
	}
	ctx->dst.zfree = protossl_bufferevent_free_and_close_fd;
	return 0;
}

int
protossl_setup_dst_new_bev_ssl_connecting_child(pxy_conn_child_ctx_t *ctx)
{
	ctx->dst.bev = bufferevent_openssl_filter_new(ctx->conn->thr->evbase, ctx->dst.bev, ctx->dst.ssl,
			BUFFEREVENT_SSL_CONNECTING, BEV_OPT_DEFER_CALLBACKS);
	if (!ctx->dst.bev) {
		log_err_level_printf(LOG_CRIT, "Error creating dst bufferevent\n");
		SSL_free(ctx->dst.ssl);
		ctx->dst.ssl = NULL;
		pxy_conn_term(ctx->conn, 1);
		return -1;
	}
	ctx->dst.zfree = protossl_bufferevent_free_and_close_fd;
	return 0;
}

int
protossl_enable_src(pxy_conn_ctx_t *ctx)
{
	// @todo The return value of protossl_enable_src() never used, just return?
	int rv;
	if ((rv = protossl_setup_src(ctx)) != 0) {
		// Might have switched to passthrough mode
		return rv;
	}
	bufferevent_setcb(ctx->src.bev, pxy_bev_readcb, pxy_bev_writecb, pxy_bev_eventcb, ctx);

	// Save the srvdst ssl info for logging
	ctx->sslctx->srvdst_ssl_version = strdup(SSL_get_version(ctx->srvdst.ssl));
	ctx->sslctx->srvdst_ssl_cipher = strdup(SSL_get_cipher(ctx->srvdst.ssl));

	if (pxy_setup_child_listener(ctx) == -1) {
		return -1;
	}

	log_finer("Enabling src");
	// Now open the gates
	bufferevent_enable(ctx->src.bev, EV_READ|EV_WRITE);
	return 0;
}

static void NONNULL(1,2)
protossl_bev_eventcb_connected_dst(struct bufferevent *bev, pxy_conn_ctx_t *ctx)
{
	log_finest("ENTER");
    
    ctx->connect_e = current_time();
	ctx->connected = 1;
	bufferevent_enable(bev, EV_READ|EV_WRITE);

	protossl_enable_src(ctx);
}

static void
protossl_bev_eventcb_connected_srvdst(UNUSED struct bufferevent *bev, pxy_conn_ctx_t *ctx)
{
	log_finest("ENTER");

//#ifndef WITHOUT_USERAUTH
//	pxy_userauth(ctx);
//	if (ctx->term || ctx->enomem) {
//		return;
//	}
//#endif /* !WITHOUT_USERAUTH */

	// Defer any pass or block action until SSL filter application below
	if (pxy_conn_apply_filter(ctx, FILTER_ACTION_PASS | FILTER_ACTION_BLOCK)) {
		// We never reach here, since we defer pass and block actions
		return;
	}

	// Set src ssl up early to apply SSL filter,
	// this is the last moment we can take divert or split action
	if (protossl_setup_src_ssl(ctx) != 0) {
		return;
	}

	if (prototcp_setup_dst(ctx) == -1) {
		return;
	}

	if (ctx->divert) {
		bufferevent_setcb(ctx->dst.bev, pxy_bev_readcb, pxy_bev_writecb, pxy_bev_eventcb, ctx);
		if (bufferevent_socket_connect(ctx->dst.bev, (struct sockaddr *)&ctx->spec->divert_addr, ctx->spec->divert_addrlen) == -1) {
			log_fine("FAILED bufferevent_socket_connect for divert addr");
			pxy_conn_term(ctx, 1);
			return;
		}
	}
}

static void NONNULL(1,2)
protossl_bev_eventcb_error_srvdst(UNUSED struct bufferevent *bev, pxy_conn_ctx_t *ctx)
{
	log_fine("ENTER");

	if (!ctx->connected) {
		log_fine("!ctx->connected");

		/* the callout to the original destination failed,
		 * e.g. because it asked for client cert auth, so
		 * close the accepted socket and clean up */
        // 先不穿透 
//		if (((ctx->conn_opts->passthrough && ctx->sslctx->have_sslerr) || (ctx->pass && !ctx->sslctx->have_sslerr))) {
//			/* ssl callout failed, fall back to plain TCP passthrough of SSL connection */
//			log_err_level_printf(LOG_WARNING, "SSL srvdst connection failed; falling back to passthrough\n");
//			ctx->sslctx->have_sslerr = 0;
//			protopassthrough_engage(ctx);
//			return;
//		}
		pxy_conn_term(ctx, 0);
	}
}

static void NONNULL(1)
protossl_bev_eventcb_dst(struct bufferevent *bev, short events, pxy_conn_ctx_t *ctx)
{
	if (events & BEV_EVENT_CONNECTED) {
		protossl_bev_eventcb_connected_dst(bev, ctx);
	} else if (events & BEV_EVENT_EOF) {
		prototcp_bev_eventcb_eof_dst(bev, ctx);
	} else if (events & BEV_EVENT_ERROR) {
		prototcp_bev_eventcb_error_dst(bev, ctx);
	}
}

void
protossl_bev_eventcb_srvdst(struct bufferevent *bev, short events, pxy_conn_ctx_t *ctx)
{
	if (events & BEV_EVENT_CONNECTED) {
		protossl_bev_eventcb_connected_srvdst(bev, ctx);
	} else if (events & BEV_EVENT_EOF) {
		prototcp_bev_eventcb_eof_srvdst(bev, ctx);
	} else if (events & BEV_EVENT_ERROR) {
		protossl_bev_eventcb_error_srvdst(bev, ctx);
	}
}

void
protossl_bev_eventcb(struct bufferevent *bev, short events, void *arg)
{
	pxy_conn_ctx_t *ctx = arg;

	if (events & BEV_EVENT_ERROR) {
		protossl_log_ssl_error(bev, ctx);
	}

	if (bev == ctx->src.bev) {
		prototcp_bev_eventcb_src(bev, events, ctx);
	} else if (bev == ctx->dst.bev) {
		protossl_bev_eventcb_dst(bev, events, ctx);
	} else if (bev == ctx->srvdst.bev) {
		protossl_bev_eventcb_srvdst(bev, events, ctx);
	} else {
		log_err_printf("protossl_bev_eventcb: UNKWN conn end\n");
	}
}

void
protossl_bev_eventcb_child(struct bufferevent *bev, short events, void *arg)
{
	pxy_conn_child_ctx_t *ctx = arg;

	if (events & BEV_EVENT_ERROR) {
		protossl_log_ssl_error(bev, ctx->conn);
	}

	if (bev == ctx->src.bev) {
		prototcp_bev_eventcb_src_child(bev, events, ctx);
	} else if (bev == ctx->dst.bev) {
		prototcp_bev_eventcb_dst_child(bev, events, ctx);
	} else {
		log_err_printf("protossl_bev_eventcb_child: UNKWN conn end\n");
	}
}

// @attention Called by thrmgr thread
protocol_t
protossl_setup(pxy_conn_ctx_t *ctx)
{
	ctx->protoctx->proto = PROTO_SSL;
	ctx->protoctx->connectcb = protossl_conn_connect;
	ctx->protoctx->init_conn = protossl_init_conn;
	
	ctx->protoctx->bev_eventcb = protossl_bev_eventcb;

	ctx->protoctx->proto_free = protossl_free;

	ctx->sslctx = malloc(sizeof(ssl_ctx_t));
	if (!ctx->sslctx) {
		return PROTO_ERROR;
	}
	memset(ctx->sslctx, 0, sizeof(ssl_ctx_t));

	return PROTO_SSL;
}

protocol_t
protossl_setup_child(pxy_conn_child_ctx_t *ctx)
{
	ctx->protoctx->proto = PROTO_SSL;
	ctx->protoctx->connectcb = protossl_connect_child;

	ctx->protoctx->bev_eventcb = protossl_bev_eventcb_child;

	return PROTO_SSL;
}

/* vim: set noet ft=c: */
