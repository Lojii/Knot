/*-
 */

#include "protohttp.h"
#include "prototcp.h"
#include "protossl.h"
#include "protopassthrough.h"

#include "util.h"
#include "base64.h"
#include "url.h"

#include <string.h>
#include <event2/bufferevent.h>

static void NONNULL(1)
protohttp_log_connect(pxy_conn_ctx_t *ctx)
{
    return;
	if (!ctx->log_connect)
		return;

	protohttp_ctx_t *http_ctx = ctx->protoctx->arg;

	char *msg;
#ifdef HAVE_LOCAL_PROCINFO
	char *lpi = NULL;
#endif /* HAVE_LOCAL_PROCINFO */
	int rv;

#ifdef HAVE_LOCAL_PROCINFO
	if (ctx->global->lprocinfo) {
		rv = asprintf(&lpi, "lproc:%i:%s:%s:%s",
		              ctx->lproc.pid,
		              STRORDASH(ctx->lproc.user),
		              STRORDASH(ctx->lproc.group),
		              STRORDASH(ctx->lproc.exec_path));
		if ((rv < 0) || !lpi) {
			ctx->enomem = 1;
			goto out;
		}
	}
#endif /* HAVE_LOCAL_PROCINFO */

	/*
	 * The following ifdef's within asprintf arguments list generates
	 * warnings with -Wembedded-directive on some compilers.
	 * Not fixing the code in order to avoid more code duplication.
	 */

	if (!ctx->spec->ssl || !ctx->sslctx) {
		rv = asprintf(&msg, "CONN: http %s %s %s %s %s %s %s %s %s"
#ifdef HAVE_LOCAL_PROCINFO
		              " %s"
#endif /* HAVE_LOCAL_PROCINFO */
		              "%s"
//#ifndef WITHOUT_USERAUTH
//		              " user:%s"
//#endif /* !WITHOUT_USERAUTH */
		              "\n",
		              STRORDASH(ctx->srchost_str),
		              STRORDASH(ctx->srcport_str),
		              STRORDASH(ctx->dsthost_str),
		              STRORDASH(ctx->dstport_str),
		              STRORDASH(http_ctx->http_host),
		              STRORDASH(http_ctx->http_method),
		              STRORDASH(http_ctx->http_uri),
		              STRORDASH(http_ctx->http_status_code),
		              STRORDASH(http_ctx->http_content_length),
#ifdef HAVE_LOCAL_PROCINFO
		              lpi,
#endif /* HAVE_LOCAL_PROCINFO */
		              http_ctx->ocsp_denied ? " ocsp:denied" : ""
//#ifndef WITHOUT_USERAUTH
//		              , STRORDASH(ctx->user)
//#endif /* !WITHOUT_USERAUTH */
		              );
	} else {
		rv = asprintf(&msg, "CONN: https %s %s %s %s %s %s %s %s %s "
		              "sni:%s names:%s "
		              "sproto:%s:%s dproto:%s:%s "
		              "origcrt:%s usedcrt:%s"
#ifdef HAVE_LOCAL_PROCINFO
		              " %s"
#endif /* HAVE_LOCAL_PROCINFO */
		              "%s"
//#ifndef WITHOUT_USERAUTH
//		              " user:%s"
//#endif /* !WITHOUT_USERAUTH */
		              "\n",
		              STRORDASH(ctx->srchost_str),
		              STRORDASH(ctx->srcport_str),
		              STRORDASH(ctx->dsthost_str),
		              STRORDASH(ctx->dstport_str),
		              STRORDASH(http_ctx->http_host),
		              STRORDASH(http_ctx->http_method),
		              STRORDASH(http_ctx->http_uri),
		              STRORDASH(http_ctx->http_status_code),
		              STRORDASH(http_ctx->http_content_length),
		              STRORDASH(ctx->sslctx->sni),
		              STRORDASH(ctx->sslctx->ssl_names),
		              SSL_get_version(ctx->src.ssl),
		              SSL_get_cipher(ctx->src.ssl),
		              STRORDASH(ctx->sslctx->srvdst_ssl_version),
		              STRORDASH(ctx->sslctx->srvdst_ssl_cipher),
		              STRORDASH(ctx->sslctx->origcrtfpr),
		              STRORDASH(ctx->sslctx->usedcrtfpr),
#ifdef HAVE_LOCAL_PROCINFO
		              lpi,
#endif /* HAVE_LOCAL_PROCINFO */
		              http_ctx->ocsp_denied ? " ocsp:denied" : ""
//#ifndef WITHOUT_USERAUTH
//		              , STRORDASH(ctx->user)
//#endif /* !WITHOUT_USERAUTH */
		              );
	}
	if ((rv < 0 ) || !msg) {
		ctx->enomem = 1;
		goto out;
	}
	if (!ctx->global->detach) {
		log_err_printf("%s", msg);
	} else if (ctx->global->statslog) {
		if (log_conn(msg) == -1) {
			log_err_level_printf(LOG_WARNING, "Conn logging failed\n");
		}
	}
	if (ctx->global->connectlog) {
		if (log_connect_print_free(msg) == -1) {
			free(msg);
			log_err_level_printf(LOG_WARNING, "Connection logging failed\n");
		}
	} else {
		free(msg);
	}
out:
#ifdef HAVE_LOCAL_PROCINFO
	if (lpi) {
		free(lpi);
	}
#endif /* HAVE_LOCAL_PROCINFO */
	return;
}

/*
 * Return 1 if uri is an OCSP GET URI, 0 if not.
 */
static int NONNULL(1,2)
protohttp_ocsp_is_valid_uri(const char *uri, pxy_conn_ctx_t *ctx)
{
	char *buf_url;
	size_t sz_url;
	char *buf_b64;
	size_t sz_b64;
	unsigned char *buf_asn1;
	size_t sz_asn1;
	int ret;

	buf_url = strrchr(uri, '/');
	if (!buf_url)
		return 0;
	buf_url++;

	/*
	 * Do some quick checks to avoid unnecessary buffer allocations and
	 * decoding URL, Base64 and ASN.1:
	 * -   OCSP requests begin with a SEQUENCE (0x30), so the first Base64
	 *     byte is 'M' or, unlikely but legal, the URL encoding thereof.
	 * -   There should be no query string in OCSP GET requests.
	 * -   Encoded OCSP request ASN.1 blobs are longer than 32 bytes.
	 */
	if (buf_url[0] != 'M' && buf_url[0] != '%')
		return 0;
	if (strchr(uri, '?'))
		return 0;
	sz_url = strlen(buf_url);
	if (sz_url < 32)
		return 0;
	buf_b64 = url_dec(buf_url, sz_url, &sz_b64);
	if (!buf_b64) {
		ctx->enomem = 1;
		return 0;
	}
	buf_asn1 = base64_dec(buf_b64, sz_b64, &sz_asn1);
	if (!buf_asn1) {
		ctx->enomem = 1;
		free(buf_b64);
		return 0;
	}
	ret = ssl_is_ocspreq(buf_asn1, sz_asn1);
	free(buf_asn1);
	free(buf_b64);
	return ret;
}

/*
 * Called after a request header was completely read.
 * If the request is an OCSP request, deny the request by sending an
 * OCSP response of type tryLater and close the connection to the server.
 *
 * Reference:
 * RFC 2560: X.509 Internet PKI Online Certificate Status Protocol (OCSP)
 */
static void NONNULL(1,2)
protohttp_ocsp_deny(pxy_conn_ctx_t *ctx, protohttp_ctx_t *http_ctx)
{
	struct evbuffer *inbuf, *outbuf;
	static const char ocspresp[] =
		"HTTP/1.0 200 OK\r\n"
		"Content-Type: application/ocsp-response\r\n"
		"Content-Length: 5\r\n"
		"Connection: close\r\n"
		"\r\n"
		"\x30\x03"      /* OCSPResponse: SEQUENCE */
		"\x0a\x01"      /* OCSPResponseStatus: ENUMERATED */
		"\x03";         /* tryLater (3) */

	if (!http_ctx->http_method)
		return;
	if (!strncasecmp(http_ctx->http_method, "GET", 3) &&
	    protohttp_ocsp_is_valid_uri(http_ctx->http_uri, ctx))
		goto deny;
	if (!strncasecmp(http_ctx->http_method, "POST", 4) &&
	    http_ctx->http_content_type &&
	    !strncasecmp(http_ctx->http_content_type,
	                 "application/ocsp-request", 24))
		goto deny;
	return;

deny:
	inbuf = bufferevent_get_input(ctx->src.bev);
	outbuf = bufferevent_get_output(ctx->src.bev);

	if (evbuffer_get_length(inbuf) > 0) {
		evbuffer_drain(inbuf, evbuffer_get_length(inbuf));
	}

	// Do not send anything to the child conns
	struct evbuffer *dst_outbuf = bufferevent_get_output(ctx->dst.bev);
	if (evbuffer_get_length(dst_outbuf) > 0) {
		evbuffer_drain(dst_outbuf, evbuffer_get_length(dst_outbuf));
	}

	// Do not send duplicate OCSP denied responses
	if (http_ctx->ocsp_denied)
		return;
    printf("-------------------> OCSP 拦截\n");
	log_finer("Sending OCSP denied response");
	evbuffer_add_printf(outbuf, ocspresp);
	http_ctx->ocsp_denied = 1;
}

/*
 * Filter a single line of HTTP request headers.
 * Also fills in some context fields for logging.
 *
 * Returns NULL if the current line should be deleted from the request.
 * Returns a newly allocated string if the current line should be replaced.
 * Returns 'line' if the line should be kept.
 */
static char * NONNULL(1,2,4)
protohttp_filter_request_header_line(const char *line, protohttp_ctx_t *http_ctx, enum conn_type type, pxy_conn_ctx_t *ctx)
{
	/* parse information for connect log */
    conn_http_info_t *http_info = ctx->extra_info;
	if (!http_ctx->http_method) {
		/* first line */
		char *space1, *space2;

		space1 = strchr(line, ' ');
		space2 = space1 ? strchr(space1 + 1, ' ') : NULL;
		if (!space1) {
			/* not HTTP */
			http_ctx->seen_req_header = 1;
			http_ctx->not_valid = 1;
		} else {
			http_ctx->http_method = malloc(space1 - line + 1);
			if (http_ctx->http_method) {
				memcpy(http_ctx->http_method, line, space1 - line);
				http_ctx->http_method[space1 - line] = '\0';
                // http_info->method
                if (http_info->method) { // 释放之前的
                    free(http_info->method);
                    http_info->method = NULL;
                }
                http_info->method = malloc(space1 - line + 1);
                if(http_info->method){
                    memcpy(http_info->method, line, space1 - line);
                    http_info->method[space1 - line] = '\0';
                }else{
                    ctx->enomem = 1;
                    return NULL;
                }
                // http_info->req_line
                if (http_info->req_line) {
                    free(http_info->req_line);
                    http_info->req_line = NULL;
                }
                http_info->req_line = malloc(sizeof(char) * (strlen(line) + 1));
                memcpy(http_info->req_line, line, strlen(line) + 1);
			} else {
				ctx->enomem = 1;
				return NULL;
			}
			space1++;
			if (!space2) {
				/* HTTP/0.9 */
				http_ctx->seen_req_header = 1;
				space2 = space1 + strlen(space1);
			}
			http_ctx->http_uri = malloc(space2 - space1 + 1);
			if (http_ctx->http_uri) {
				memcpy(http_ctx->http_uri, space1, space2 - space1);
				http_ctx->http_uri[space2 - space1] = '\0';
                // http_info->uri
                if (http_info->uri) {
                    free(http_info->uri);
                    http_info->uri = NULL;
                }
                http_info->uri = malloc(space2 - space1 + 1);
                if(http_info->uri){
                    memcpy(http_info->uri, space1, space2 - space1);
                    http_info->uri[space2 - space1] = '\0';
                }else{
                    ctx->enomem = 1;
                    return NULL;
                }
			} else {
				ctx->enomem = 1;
				return NULL;
			}
		}
	} else {
		/* not first line */
		char *newhdr;

		if (!http_ctx->http_host && !strncasecmp(line, "Host:", 5)) {
			http_ctx->http_host = strdup(util_skipws(line + 5));
			if (!http_ctx->http_host) {
				ctx->enomem = 1;
				return NULL;
			}
            // http_info->host
            if (http_info->host) {
                free(http_info->host);
                http_info->host = NULL;
            }
            http_info->host = strdup(util_skipws(line + 5));
            if (!http_info->host) {
                ctx->enomem = 1;
                return NULL;
            }
			http_ctx->seen_keyword_count++;
		} else if (!strncasecmp(line, "Content-Type:", 13)) {
			http_ctx->http_content_type = strdup(util_skipws(line + 13));
			if (!http_ctx->http_content_type) {
				ctx->enomem = 1;
				return NULL;
			}
            // http_info->req_content_type
            http_info->req_content_type = strdup(util_skipws(line + 13));
            if (!http_info->req_content_type) {
                ctx->enomem = 1;
                return NULL;
            }
			http_ctx->seen_keyword_count++;
		/* Override Connection: keepalive and Connection: upgrade */
		} else if (!strncasecmp(line, "User-Agent:", 11)) {
            // http_info->req_target
            http_info->req_target = strdup(util_skipws(line + 11));
            if (!http_info->req_target) {
                ctx->enomem = 1;
                return NULL;
            }
        } else if (!strncasecmp(line, "Content-Encoding:", 17)) {
            // http_info->req_encode
            http_info->req_encode = strdup(util_skipws(line + 17));
            if (!http_info->req_encode) {
                ctx->enomem = 1;
                return NULL;
            }
        }else if (!strncasecmp(line, "Content-Length:", 15)) {
            // req_body_size
            http_info->req_body_size = strdup(util_skipws(line + 15));
            if (!http_info->req_body_size) {
              ctx->enomem = 1;
              return NULL;
            }
        } else if (!strncasecmp(line, "Connection:", 11)) {
			http_ctx->sent_http_conn_close = 1;
			if (!(newhdr = strdup("Connection: close"))) {
				ctx->enomem = 1;
				return NULL;
			}
			http_ctx->seen_keyword_count++;
			return newhdr;
		// @attention Always use conn ctx for opts, child ctx does not have opts, see the comments in pxy_conn_child_ctx
		} else if (ctx->conn_opts->remove_http_accept_encoding && !strncasecmp(line, "Accept-Encoding:", 16)) {
			http_ctx->seen_keyword_count++;
			return NULL;
		} else if (ctx->conn_opts->remove_http_referer && !strncasecmp(line, "Referer:", 8)) {
			http_ctx->seen_keyword_count++;
			return NULL;
		/* Suppress upgrading to SSL/TLS, WebSockets or HTTP/2 and keep-alive */
		} else if (!strncasecmp(line, "Upgrade:", 8) || !strncasecmp(line, "Keep-Alive:", 11)) {
			http_ctx->seen_keyword_count++;
			return NULL;
		} else if ((type == CONN_TYPE_CHILD) && (
				   // @attention flickr keeps redirecting to https with 301 unless we remove the Via line of squid
				   // Apparently flickr assumes the existence of Via header field or squid keyword a sign of plain http, even if we are using https
		           !strncasecmp(line, "Via:", 4) ||
				   // Also do not send the loopback address to the Internet
		           !strncasecmp(line, "X-Forwarded-For:", 16))) {
			http_ctx->seen_keyword_count++;
			return NULL;
		} else if (!strncasecmp(line, SSLPROXY_KEY, SSLPROXY_KEY_LEN)) {
			// Remove any SSLproxy line, parent or child
			return NULL;
		} else if (line[0] == '\0') {
			http_ctx->seen_req_header = 1;
			if (!http_ctx->sent_http_conn_close) {
				newhdr = strdup("Connection: close\r\n");
				if (!newhdr) {
					ctx->enomem = 1;
					return NULL;
				}
				return newhdr;
			}
		}
	}

	return (char*)line;
}

static filter_action_t * NONNULL(1,2)
protohttp_filter_match_host(pxy_conn_ctx_t *ctx, filter_list_t *list)
{
	protohttp_ctx_t *http_ctx = ctx->protoctx->arg;

	filter_site_t *site = filter_site_find(list->host_btree, list->host_acm, list->host_all, http_ctx->http_host);
	if (!site)
		return NULL;

//#ifndef WITHOUT_USERAUTH
//	log_fine_va("Found site (line=%d): %s for %s:%s, %s:%s, %s, %s, %s", site->action.line_num, site->site,
//		STRORDASH(ctx->srchost_str), STRORDASH(ctx->srcport_str), STRORDASH(ctx->dsthost_str), STRORDASH(ctx->dstport_str),
//		STRORDASH(ctx->user), STRORDASH(ctx->desc), STRORDASH(http_ctx->http_host));
//#else /* WITHOUT_USERAUTH */
//	log_fine_va("Found site (line=%d): %s for %s:%s, %s:%s, %s", site->action.line_num, site->site,
//		STRORDASH(ctx->srchost_str), STRORDASH(ctx->srcport_str), STRORDASH(ctx->dsthost_str), STRORDASH(ctx->dstport_str),
//		STRORDASH(http_ctx->http_host));
//#endif /* WITHOUT_USERAUTH */

	if (!site->port_btree && !site->port_acm && (site->action.precedence < ctx->filter_precedence)) {
		log_finest_va("Rule precedence lower than conn filter precedence %d < %d (line=%d): %s, %s", site->action.precedence, ctx->filter_precedence, site->action.line_num, site->site, http_ctx->http_host);
		return NULL;
	}

#ifdef DEBUG_PROXY
	if (site->all_sites)
		log_finest_va("Match all host (line=%d): %s, %s", site->action.line_num, site->site, http_ctx->http_host);
	else if (site->exact)
		log_finest_va("Match exact with host (line=%d): %s, %s", site->action.line_num, site->site, http_ctx->http_host);
	else
		log_finest_va("Match substring in host (line=%d): %s, %s", site->action.line_num, site->site, http_ctx->http_host);
#endif /* DEBUG_PROXY */

	filter_action_t *port_action = pxy_conn_filter_port(ctx, site);
	if (port_action)
		return port_action;

	return &site->action;
}

static filter_action_t * NONNULL(1,2)
protohttp_filter_match_uri(pxy_conn_ctx_t *ctx, filter_list_t *list)
{
	protohttp_ctx_t *http_ctx = ctx->protoctx->arg;

	filter_site_t *site = filter_site_find(list->uri_btree, list->uri_acm, list->uri_all, http_ctx->http_uri);
	if (!site)
		return NULL;

//#ifndef WITHOUT_USERAUTH
//	log_fine_va("Found site (line=%d): %s for %s:%s, %s:%s, %s, %s, %s", site->action.line_num, site->site,
//		STRORDASH(ctx->srchost_str), STRORDASH(ctx->srcport_str), STRORDASH(ctx->dsthost_str), STRORDASH(ctx->dstport_str),
//		STRORDASH(ctx->user), STRORDASH(ctx->desc), STRORDASH(http_ctx->http_uri));
//#else /* WITHOUT_USERAUTH */
//	log_fine_va("Found site (line=%d): %s for %s:%s, %s:%s, %s", site->action.line_num, site->site,
//		STRORDASH(ctx->srchost_str), STRORDASH(ctx->srcport_str), STRORDASH(ctx->dsthost_str), STRORDASH(ctx->dstport_str),
//		STRORDASH(http_ctx->http_uri));
//#endif /* WITHOUT_USERAUTH */

	if (!site->port_btree && !site->port_acm && (site->action.precedence < ctx->filter_precedence)) {
		log_finest_va("Rule precedence lower than conn filter precedence %d < %d (line=%d): %s, %s", site->action.precedence, ctx->filter_precedence, site->action.line_num, site->site, http_ctx->http_uri);
		return NULL;
	}

#ifdef DEBUG_PROXY
	if (site->all_sites)
		log_finest_va("Match all uri (line=%d): %s, %s", site->action.line_num, site->site, http_ctx->http_uri);
	else if (site->exact)
		log_finest_va("Match exact with uri (line=%d): %s, %s", site->action.line_num, site->site, http_ctx->http_uri);
	else
		log_finest_va("Match substring in uri (line=%d): %s, %s", site->action.line_num, site->site, http_ctx->http_uri);
#endif /* DEBUG_PROXY */

	filter_action_t *port_action = pxy_conn_filter_port(ctx, site);
	if (port_action)
		return port_action;

	return &site->action;
}

static filter_action_t * NONNULL(1,2)
protohttp_filter(pxy_conn_ctx_t *ctx, filter_list_t *list)
{
	protohttp_ctx_t *http_ctx = ctx->protoctx->arg;

	filter_action_t *action_host = NULL;
	filter_action_t *action_uri = NULL;

	if (http_ctx->http_host) {
		if (!(action_host = protohttp_filter_match_host(ctx, list))) {
//#ifndef WITHOUT_USERAUTH
//			log_finest_va("No filter match with host: %s:%s, %s:%s, %s, %s, %s, %s",
//				STRORDASH(ctx->srchost_str), STRORDASH(ctx->srcport_str), STRORDASH(ctx->dsthost_str), STRORDASH(ctx->dstport_str),
//				STRORDASH(ctx->user), STRORDASH(ctx->desc), STRORDASH(http_ctx->http_host), STRORDASH(http_ctx->http_uri));
//#else /* WITHOUT_USERAUTH */
			log_finest_va("No filter match with host: %s:%s, %s:%s, %s, %s",
				STRORDASH(ctx->srchost_str), STRORDASH(ctx->srcport_str), STRORDASH(ctx->dsthost_str), STRORDASH(ctx->dstport_str),
				STRORDASH(http_ctx->http_host), STRORDASH(http_ctx->http_uri));
//#endif /* !WITHOUT_USERAUTH */
		}
	}

	if (http_ctx->http_uri) {
		if (!(action_uri = protohttp_filter_match_uri(ctx, list))) {
//#ifndef WITHOUT_USERAUTH
//			log_finest_va("No filter match with uri: %s:%s, %s:%s, %s, %s, %s, %s",
//				STRORDASH(ctx->srchost_str), STRORDASH(ctx->srcport_str), STRORDASH(ctx->dsthost_str), STRORDASH(ctx->dstport_str),
//				STRORDASH(ctx->user), STRORDASH(ctx->desc), STRORDASH(http_ctx->http_host), STRORDASH(http_ctx->http_uri));
//#else /* WITHOUT_USERAUTH */
			log_finest_va("No filter match with uri: %s:%s, %s:%s, %s, %s",
				STRORDASH(ctx->srchost_str), STRORDASH(ctx->srcport_str), STRORDASH(ctx->dsthost_str), STRORDASH(ctx->dstport_str),
				STRORDASH(http_ctx->http_host), STRORDASH(http_ctx->http_uri));
//#endif /* !WITHOUT_USERAUTH */
		}
	}

	if (action_host ||  action_uri)
		return pxy_conn_set_filter_action(action_host, action_uri
#ifdef DEBUG_PROXY
				, ctx, http_ctx->http_host, http_ctx->http_uri
#endif /* DEBUG_PROXY */
				);

	return NULL;
}

static int
protohttp_apply_filter(pxy_conn_ctx_t *ctx)
{
	int rv = 0;
	filter_action_t *a;
	if ((a = pxy_conn_filter(ctx, protohttp_filter))) {
		unsigned int action = pxy_conn_translate_filter_action(ctx, a);

		ctx->filter_precedence = action & FILTER_PRECEDENCE;

		if (action & FILTER_ACTION_DIVERT) {
			if (ctx->divert) {
				// Override any deferred block action, if already in divert mode (keep divert mode)
				ctx->deferred_action = FILTER_ACTION_NONE;
			} else {
				log_fine("HTTP filter cannot enable divert mode");
			}
		}
		else if (action & FILTER_ACTION_SPLIT) {
			if (!ctx->divert) {
				// Override any deferred block action, if already in split mode (keep split mode)
				ctx->deferred_action = FILTER_ACTION_NONE;
			} else {
				log_fine("HTTP filter cannot enable split mode");
			}
		}
		else if (action & FILTER_ACTION_PASS) {
			log_fine("HTTP filter cannot take pass action");
		}
		else if (action & FILTER_ACTION_BLOCK) {
			ctx->deferred_action = FILTER_ACTION_NONE;
			pxy_conn_term(ctx, 1);
			rv = 1;
		}
		//else { /* FILTER_ACTION_MATCH */ }

		if (action & (FILTER_LOG_CONTENT | FILTER_LOG_PCAP)) {
			log_fine("HTTP filter cannot enable content or pcap logging");
		}

		// Note that connect, master, and cert logs have already been written by now
		// so enabling or disabling those logs here will not have any effect
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

		// content, pcap, and mirror logging can be disabled only
		// loggers will stop writing further contents
		if (action & FILTER_LOG_NOCONTENT)
			ctx->log_content = 0;
		if (action & FILTER_LOG_NOPCAP)
			ctx->log_pcap = 0;
		if (a->conn_opts)
			ctx->conn_opts = a->conn_opts;
	}

	// Cannot defer block action any longer
	// Match action should not override any deferred action, hence no 'else if'
	if (pxy_conn_apply_deferred_block_action(ctx))
		rv = 1;

	return rv;
}

static int WUNRES NONNULL(1,2,3,5)
protohttp_filter_request_header(struct evbuffer *inbuf, struct evbuffer *outbuf, protohttp_ctx_t *http_ctx, enum conn_type type, pxy_conn_ctx_t *ctx)
{
	char *line;
//    printf("------------- req \n");
	while (!http_ctx->seen_req_header && (line = evbuffer_readln(inbuf, NULL, EVBUFFER_EOL_CRLF))) {
		log_finest_va("%s", line);
//        printf("--------  %s\n", line);

		char *replace = protohttp_filter_request_header_line(line, http_ctx, type, ctx);
		if (replace == line) {
			evbuffer_add_printf(outbuf, "%s\r\n", line);
		} else if (replace) {
			log_finer_va("REPLACE= %s", replace);
			evbuffer_add_printf(outbuf, "%s\r\n", replace);
			free(replace);
		} else {
			log_finer_va("REMOVE= %s", line);
			if (ctx->enomem) {
				return -1;
			}
		}
		free(line);

		if ((type == CONN_TYPE_PARENT) && ctx->divert && !ctx->sent_sslproxy_header) {
			ctx->sent_sslproxy_header = 1;
			log_finer_va("INSERT= %s", ctx->sslproxy_header);
			evbuffer_add_printf(outbuf, "%s\r\n", ctx->sslproxy_header);
		}
	}

	if (http_ctx->seen_req_header) {
		if (type == CONN_TYPE_PARENT) {
			if (protohttp_apply_filter(ctx)) {
				return -1;
			}

			/* request header complete */
			if (ctx->conn_opts->deny_ocsp) {
				protohttp_ocsp_deny(ctx, http_ctx);
			}
		}

		if (ctx->enomem) {
			return -1;
		}

		/* no data left after parsing headers? */
		if (evbuffer_get_length(inbuf) == 0) {
			return 0;
		}
		evbuffer_add_buffer(outbuf, inbuf);
	}
	return 0;
}

//#ifndef WITHOUT_USERAUTH
//static char * NONNULL(1,2)
//protohttp_get_url(struct evbuffer *inbuf, pxy_conn_ctx_t *ctx)
//{
//	char *line;
//	char *path = NULL;
//	char *host = NULL;
//	char *url = NULL;
//
//	while ((!host || !path) && (line = evbuffer_readln(inbuf, NULL, EVBUFFER_EOL_CRLF))) {
//		log_finest_va("%s", line);
//
//		//GET / HTTP/1.1
//		if (!path && !strncasecmp(line, "GET ", 4)) {
//			path = strdup(util_skipws(line + 4));
//			if (!path) {
//				ctx->enomem = 1;
//				free(line);
//				goto memout;
//			}
//			path = strsep(&path, " \t");
//			log_finest_va("path=%s", path);
//		//Host: example.com
//		} else if (!host && !strncasecmp(line, "Host:", 5)) {
//			host = strdup(util_skipws(line + 5));
//			if (!host) {
//				ctx->enomem = 1;
//				free(line);
//				goto memout;
//			}
//			log_finest_va("host=%s", host);
//		}
//		free(line);
//	}
//
//	if (host && path) {
//		// Assume that path will always have a leading /, so do not insert an extra / in between host and path
//		// Don't care about computing the exact url size for plain or secure http (http or https)
//		// http  s   ://  example.com  + /            + NULL
//		// 4  +  1 + 3  + strlen(host) + strlen(path) + 1
//		size_t url_size = strlen(host) + strlen(path) + 9;
//		url = malloc(url_size);
//		if (!url) {
//			ctx->enomem = 1;
//			goto memout;
//		}
//
//		if (snprintf(url, url_size, "http%s://%s%s", ctx->spec->ssl ? "s": "", host, path) < 0) {
//			ctx->enomem = 1;
//			free(url);
//			url = NULL;
//			goto memout;
//		}
//		log_finest_va("url=%s", url);
//	}
//memout:
//	if (host)
//		free(host);
//	if (path)
//		free(path);
//	return url;
//}
//#endif /* !WITHOUT_USERAUTH */

// Size = 39
static char *http_methods[] = { "GET", "PUT", "ICY", "COPY", "HEAD", "LOCK", "MOVE", "POLL", "POST", "BCOPY", "BMOVE", "MKCOL", "TRACE", "LABEL", "MERGE", "DELETE",
	"SEARCH", "UNLOCK", "REPORT", "UPDATE", "NOTIFY", "BDELETE", "CONNECT", "OPTIONS", "CHECKIN", "PROPFIND", "CHECKOUT", "CCM_POST", "SUBSCRIBE",
	"PROPPATCH", "BPROPFIND", "BPROPPATCH", "UNCHECKOUT", "MKACTIVITY", "MKWORKSPACE", "UNSUBSCRIBE", "RPC_CONNECT", "VERSION-CONTROL", "BASELINE-CONTROL" };

static int NONNULL(1)
protohttp_validate_method(char *method
#ifdef DEBUG_PROXY
	, pxy_conn_ctx_t *ctx
#endif /* DEBUG_PROXY */
	)
{
	size_t method_len = strlen(method);

	unsigned int i;
	for (i = 0; i < sizeof(http_methods)/sizeof(char *); i++) {
		char *m = http_methods[i];
		if (strlen(m) == method_len && !strncasecmp(method, m, method_len)) {
			log_finest_va("Passed method validation: %s", method);
			return 0;
		}
	}
	return -1;
}

int
protohttp_validate(pxy_conn_ctx_t *ctx)
{
	protohttp_ctx_t *http_ctx = ctx->protoctx->arg;

	if (http_ctx->not_valid) {
		log_finest("Not http, validation failed previously");
		return -1;
	}
	if (http_ctx->http_method) {
		if (protohttp_validate_method(http_ctx->http_method
#ifdef DEBUG_PROXY
				, ctx
#endif /* DEBUG_PROXY */
				) == -1) {
			http_ctx->not_valid = 1;
			log_finest_va("Failed method validation: %s", http_ctx->http_method);
			return -1;
		}
	}
	if (http_ctx->seen_keyword_count) {
		// The first line has been processed successfully
		// Pass validation if we have seen at least one http keyword
		ctx->protoctx->is_valid = 1;
		log_finest("Passed validation");
		return 0;
	}
	if (http_ctx->seen_bytes > ctx->conn_opts->max_http_header_size) {
		// Fail validation if still cannot pass as http after reaching max header size
		http_ctx->not_valid = 1;
		log_finest_va("Reached max header size, size=%llu", http_ctx->seen_bytes);
		return -1;
	}
	return 0;
}

static void NONNULL(1,2)
protohttp_bev_readcb_src(struct bufferevent *bev, pxy_conn_ctx_t *ctx)
{
    if(ctx->send_s == 0){ ctx->send_s = current_time(); }
	static const char proto_error[] =
		"HTTP/1.1 400 Bad request\r\n"
		"Cache-Control: no-cache\r\n"
		"Connection: close\r\n"
		"Content-Type: text/html\r\n"
		"\r\n";

	log_finest_va("ENTER, size=%zu", evbuffer_get_length(bufferevent_get_input(bev)));

	if (ctx->dst.closed) {
		pxy_discard_inbuf(bev);
		return;
	}

	protohttp_ctx_t *http_ctx = ctx->protoctx->arg;
	struct evbuffer *inbuf = bufferevent_get_input(bev);
	struct evbuffer *outbuf = bufferevent_get_output(ctx->dst.bev);
    
//    if (ctx->src.first_packet_buf) {
//        evbuffer_add_buffer(inbuf, ctx->src.first_packet_buf);
//        evbuffer_free(ctx->src.first_packet_buf);
//        ctx->src.first_packet_buf = NULL;
//    }

	if (ctx->conn_opts->validate_proto && !ctx->protoctx->is_valid) {
		http_ctx->seen_bytes += evbuffer_get_length(inbuf);
	}

	// We insert our special header line to the first packet we get, e.g. right after the first \r\n in the case of http
	// @todo Should we look for GET/POST or Host header lines to detect the first packet?
	// But there is no guarantee that they will exist, due to fragmentation.
	// @attention We cannot append the ssl proxy address at the end of the packet or in between the header and the content,
	// because (1) the packet may be just the first fragment split somewhere not appropriate for appending a header,
	// and (2) there may not be any content.
	// And we are dealing with pop3 and smtp also, not just http.

	/* request header munging */
	if (!http_ctx->seen_req_header) {
		log_finest_va("HTTP Request Header, size=%zu", evbuffer_get_length(inbuf));
		if (protohttp_filter_request_header(inbuf, outbuf, http_ctx, ctx->type, ctx) == -1) {
			return;
		}
	} else {
		log_finest_va("HTTP Request Body, size=%zu", evbuffer_get_length(inbuf));
		evbuffer_add_buffer(outbuf, inbuf);
	}
    ctx->send_e = current_time();
	if (ctx->conn_opts->validate_proto && !ctx->protoctx->is_valid) {
		if (protohttp_validate(ctx) == -1) {
			evbuffer_add(bufferevent_get_output(bev), proto_error, strlen(proto_error));
			ctx->sent_protoerror_msg = 1;
			pxy_discard_inbuf(bev);
			evbuffer_drain(outbuf, evbuffer_get_length(outbuf));
			return;
		}
	}

	pxy_try_set_watermark(bev, ctx, ctx->dst.bev);
}

/*
 * Filter a single line of HTTP response headers.
 *
 * Returns NULL if the current line should be deleted from the response.
 * Returns a newly allocated string if the current line should be replaced.
 * Returns `line' if the line should be kept.
 */
static char * NONNULL(1,2,3)
protohttp_filter_response_header_line(const char *line, protohttp_ctx_t *http_ctx, pxy_conn_ctx_t *ctx)
{
    conn_http_info_t *http_info = ctx->extra_info;
	/* parse information for connect log */
	if (!http_ctx->http_status_code) {
		/* first line */
		char *space1, *space2;

		space1 = strchr(line, ' ');
		space2 = space1 ? strchr(space1 + 1, ' ') : NULL;
		if (!space1 || !!strncmp(line, "HTTP", 4)) {
			/* not HTTP or HTTP/0.9 */
			http_ctx->seen_resp_header = 1;
		} else {
			size_t len_code, len_text;

			if (space2) {
				len_code = space2 - space1 - 1;
				len_text = strlen(space2 + 1);
			} else {
				len_code = strlen(space1 + 1);
				len_text = 0;
			}
			http_ctx->http_status_code = malloc(len_code + 1);
			http_ctx->http_status_text = malloc(len_text + 1);
			if (!http_ctx->http_status_code || !http_ctx->http_status_text) {
				ctx->enomem = 1;
				return NULL;
			}
			memcpy(http_ctx->http_status_code, space1 + 1, len_code);
			http_ctx->http_status_code[len_code] = '\0';
			if (space2) {
				memcpy(http_ctx->http_status_text, space2 + 1, len_text);
			}
			http_ctx->http_status_text[len_text] = '\0';
            // rsp_state rsp_message
            http_info->rsp_state = malloc(len_code + 1);
            http_info->rsp_message = malloc(len_text + 1);
            if (!http_info->rsp_state || !http_info->rsp_message) {
                ctx->enomem = 1;
                return NULL;
            }
            memcpy(http_info->rsp_state, space1 + 1, len_code);
            http_info->rsp_state[len_code] = '\0';
            if (space2) {
                memcpy(http_info->rsp_message, space2 + 1, len_text);
            }
            http_info->rsp_message[len_text] = '\0';
            // rsp_line
            http_info->rsp_line = malloc(sizeof(char) * (strlen(line) + 1));
            memcpy(http_info->rsp_line, line, strlen(line) + 1);
		}
	} else {
		/* not first line */
		if (!http_ctx->http_content_length &&
		    !strncasecmp(line, "Content-Length:", 15)) {
			http_ctx->http_content_length =
				strdup(util_skipws(line + 15));
			if (!http_ctx->http_content_length) {
				ctx->enomem = 1;
				return NULL;
			}
            // rsp_body_size
            http_info->rsp_body_size = strdup(util_skipws(line + 15));
            if (!http_info->rsp_body_size) {
                ctx->enomem = 1;
                return NULL;
            }
		} else if (!strncasecmp(line, "Content-Type:", 13)) {
            // http_info->req_content_type
            http_info->rsp_content_type = strdup(util_skipws(line + 13));
            if (!http_info->rsp_content_type) {
                ctx->enomem = 1;
                return NULL;
            }
            http_ctx->seen_keyword_count++;
        } else if (!strncasecmp(line, "Content-Encoding:", 17)) {
            // http_info->rsp_encode
            http_info->rsp_encode = strdup(util_skipws(line + 17));
            if (!http_info->rsp_encode) {
                ctx->enomem = 1;
                return NULL;
            }
        } else if (
		    /* HPKP: Public Key Pinning Extension for HTTP
		     * (draft-ietf-websec-key-pinning)
		     * remove to prevent public key pinning */
		    !strncasecmp(line, "Public-Key-Pins:", 16) ||
		    !strncasecmp(line, "Public-Key-Pins-Report-Only:", 28) ||
		    /* HSTS: HTTP Strict Transport Security (RFC 6797)
		     * remove to allow users to accept bad certs */
		    !strncasecmp(line, "Strict-Transport-Security:", 26) ||
		    /* Expect-CT: Expect Certificate Transparency
		     * (draft-ietf-httpbis-expect-ct-latest)
		     * remove to prevent failed CT log lookups */
		    !strncasecmp(line, "Expect-CT:", 10) ||
		    /* Alternate Protocol
		     * remove to prevent switching to QUIC, SPDY et al */
		    !strncasecmp(line, "Alternate-Protocol:", 19) ||
		    /* Upgrade header
		     * remove to prevent upgrading to HTTPS in unhandled ways,
		     * and more importantly, WebSockets and HTTP/2 */
		    !strncasecmp(line, "Upgrade:", 8)) {
			return NULL;
		} else if (line[0] == '\0') {
			http_ctx->seen_resp_header = 1;
		}
	}

	return (char*)line;
}

static void NONNULL(1,2,3,4)
protohttp_filter_response_header(struct evbuffer *inbuf, struct evbuffer *outbuf, protohttp_ctx_t *http_ctx, pxy_conn_ctx_t *ctx)
{
	char *line;
//    printf("------------- rsp \n");
	while (!http_ctx->seen_resp_header && (line = evbuffer_readln(inbuf, NULL, EVBUFFER_EOL_CRLF))) {
		log_finest_va("%s", line);
//        printf("--------  %s\n",line);

		char *replace = protohttp_filter_response_header_line(line, http_ctx, ctx);
		if (replace == line) {
			evbuffer_add_printf(outbuf, "%s\r\n", line);
		} else if (replace) {
			log_finer_va("REPLACE= %s", replace);
			evbuffer_add_printf(outbuf, "%s\r\n", replace);
			free(replace);
		} else {
			log_finer_va("REMOVE= %s", line);
			if (ctx->enomem) {
				return;
			}
		}
		free(line);
	}
//    printf("-------------\n");

	if (http_ctx->seen_resp_header) {
		/* no data left after parsing headers? */
		if (evbuffer_get_length(inbuf) == 0) {
			return;
		}
		evbuffer_add_buffer(outbuf, inbuf);
	}
}

static void NONNULL(1)
protohttp_bev_readcb_dst(struct bufferevent *bev, pxy_conn_ctx_t *ctx)
{
	log_finest_va("ENTER, size=%zu", evbuffer_get_length(bufferevent_get_input(bev)));

	if (ctx->src.closed) {
		pxy_discard_inbuf(bev);
		return;
	}
    if(ctx->receive_s == 0){ ctx->receive_s = current_time(); }
	protohttp_ctx_t *http_ctx = ctx->protoctx->arg;
	struct evbuffer *inbuf = bufferevent_get_input(bev);
	struct evbuffer *outbuf = bufferevent_get_output(ctx->src.bev);

	if (!http_ctx->seen_resp_header) {
		log_finest_va("HTTP Response Header, size=%zu", evbuffer_get_length(inbuf));
		protohttp_filter_response_header(inbuf, outbuf, http_ctx, ctx);
		if (ctx->enomem) {
			return;
		}
	} else {
		log_finest_va("HTTP Response Body, size=%zu", evbuffer_get_length(inbuf));
		evbuffer_add_buffer(outbuf, inbuf);
	}
    ctx->receive_e = current_time();
	pxy_try_set_watermark(bev, ctx, ctx->src.bev);
}

static void NONNULL(1)
protohttp_bev_readcb_srvdst(UNUSED struct bufferevent *bev, UNUSED pxy_conn_ctx_t *ctx)
{
	log_err_level(LOG_ERR, "readcb called on srvdst");
}

static void NONNULL(1)
protohttp_bev_readcb_src_child(struct bufferevent *bev, pxy_conn_child_ctx_t *ctx)
{
	log_finest_va("ENTER, size=%zu", evbuffer_get_length(bufferevent_get_input(bev)));

	if (ctx->dst.closed) {
		pxy_discard_inbuf(bev);
		return;
	}

	protohttp_ctx_t *http_ctx = ctx->protoctx->arg;
	struct evbuffer *inbuf = bufferevent_get_input(bev);
	struct evbuffer *outbuf = bufferevent_get_output(ctx->dst.bev);

	if (!http_ctx->seen_req_header) {
		log_finest_va("HTTP Request Header, size=%zu", evbuffer_get_length(inbuf));
		// @todo Just remove SSLproxy line, do not filter request on the server side?
		if (protohttp_filter_request_header(inbuf, outbuf, http_ctx, ctx->type, ctx->conn) == -1) {
			return;
		}
	} else {
		log_finest_va("HTTP Request Body, size=%zu", evbuffer_get_length(inbuf));
		evbuffer_add_buffer(outbuf, inbuf);
	}
	pxy_try_set_watermark(bev, ctx->conn, ctx->dst.bev);
}

static void NONNULL(1)
protohttp_bev_readcb_dst_child(struct bufferevent *bev, pxy_conn_child_ctx_t *ctx)
{
	log_finest_va("ENTER, size=%zu", evbuffer_get_length(bufferevent_get_input(bev)));
		
	if (ctx->src.closed) {
		pxy_discard_inbuf(bev);
		return;
	}

	protohttp_ctx_t *http_ctx = ctx->protoctx->arg;
	struct evbuffer *inbuf = bufferevent_get_input(bev);
	struct evbuffer *outbuf = bufferevent_get_output(ctx->src.bev);

	if (!http_ctx->seen_resp_header) {
		log_finest_va("HTTP Response Header, size=%zu", evbuffer_get_length(inbuf));
		// @todo Do not filter response on the server side?
		protohttp_filter_response_header(inbuf, outbuf, http_ctx, ctx->conn);
		if (ctx->conn->enomem) {
			return;
		}
	} else {
		log_finest_va("HTTP Response Body, size=%zu", evbuffer_get_length(inbuf));
		evbuffer_add_buffer(outbuf, inbuf);
	}
	pxy_try_set_watermark(bev, ctx->conn, ctx->src.bev);
}

static void NONNULL(1)
protohttp_bev_readcb(struct bufferevent *bev, void *arg)
{
	pxy_conn_ctx_t *ctx = arg;
	protohttp_ctx_t *http_ctx = ctx->protoctx->arg;

	int seen_resp_header_on_entry = http_ctx->seen_resp_header;

	if (bev == ctx->src.bev) {
		protohttp_bev_readcb_src(bev, ctx);
	} else if (bev == ctx->dst.bev) {
		protohttp_bev_readcb_dst(bev, ctx);
	} else if (bev == ctx->srvdst.bev) {
		protohttp_bev_readcb_srvdst(bev, ctx);
	} else {
		log_err_printf("protohttp_bev_readcb: UNKWN conn end\n");
		return;
	}

	if (ctx->enomem) {
		return;
	}

	if (!seen_resp_header_on_entry && http_ctx->seen_resp_header) {
		/* response header complete: log connection */
		if (WANT_CONNECT_LOG(ctx->conn)) {
			protohttp_log_connect(ctx);
		}
    }
}

static void NONNULL(1)
protohttp_bev_readcb_child(struct bufferevent *bev, void *arg)
{
	pxy_conn_child_ctx_t *ctx = arg;

	if (bev == ctx->src.bev) {
		protohttp_bev_readcb_src_child(bev, ctx);
	} else if (bev == ctx->dst.bev) {
		protohttp_bev_readcb_dst_child(bev, ctx);
	} else {
		log_err_printf("protohttp_bev_readcb_child: UNKWN conn end\n");
	}
}

static void NONNULL(1)
protohttp_bev_writecb_src(struct bufferevent *bev, pxy_conn_ctx_t *ctx)
{
	log_finest("ENTER");

//#ifndef WITHOUT_USERAUTH
//	if (prototcp_try_close_unauth_conn(bev, ctx)) {
//		return;
//	}
//#endif /* !WITHOUT_USERAUTH */

	if (prototcp_try_close_protoerror_conn(bev, ctx)) {
		return;
	}

	protohttp_ctx_t *http_ctx = ctx->protoctx->arg;
	if (ctx->dst.closed || http_ctx->ocsp_denied) {
		if (pxy_try_close_conn_end(&ctx->src, ctx) == 1) {
			log_finest("dst.closed or ocsp_denied, terminate conn");
			pxy_conn_term(ctx, 1);
		}
		return;
	}
	pxy_try_unset_watermark(bev, ctx, &ctx->dst);
}

static void NONNULL(1)
protohttp_bev_writecb(struct bufferevent *bev, void *arg)
{
	pxy_conn_ctx_t *ctx = arg;

	if (bev == ctx->src.bev) {
		protohttp_bev_writecb_src(bev, ctx);
	} else if (bev == ctx->dst.bev) {
		prototcp_bev_writecb_dst(bev, ctx);
	} else {
		log_err_printf("protohttp_bev_writecb: UNKWN conn end\n");
	}
}

static void NONNULL(1)
protohttp_free_ctx(protohttp_ctx_t *http_ctx)
{
    if (http_ctx->http_req_line) {
        free(http_ctx->http_req_line);
    }
    if (http_ctx->http_rsp_line) {
        free(http_ctx->http_rsp_line);
    }
	if (http_ctx->http_method) {
		free(http_ctx->http_method);
	}
	if (http_ctx->http_uri) {
		free(http_ctx->http_uri);
	}
	if (http_ctx->http_host) {
		free(http_ctx->http_host);
	}
	if (http_ctx->http_content_type) {
		free(http_ctx->http_content_type);
	}
	if (http_ctx->http_status_code) {
		free(http_ctx->http_status_code);
	}
	if (http_ctx->http_status_text) {
		free(http_ctx->http_status_text);
	}
	if (http_ctx->http_content_length) {
		free(http_ctx->http_content_length);
	}
	free(http_ctx);
}

static void NONNULL(1)
protohttp_free_conn_info(conn_http_info_t *info)
{
//    if (info->schemes) { free(info->schemes); }
    if (info->method) { free(info->method); }
    if (info->uri) { free(info->uri); }
    if (info->host) { free(info->host); }
//    if (info->port) { free(info->port); }
    if (info->suffix) { free(info->suffix); }
    if (info->req_line) { free(info->req_line); }
//    if (info->req_version) { free(info->req_version); }
    if (info->req_content_type) { free(info->req_content_type); }
    if (info->req_type) { free(info->req_type); }
    if (info->req_encode) { free(info->req_encode); }
    if (info->req_body_size) { free(info->req_body_size); }
//    if (info->req_heads) { free(info->req_heads); }
    if (info->req_target) { free(info->req_target); }
    if (info->rsp_line) { free(info->rsp_line); }
//    if (info->rsp_version) { free(info->rsp_version); }
    if (info->rsp_state) { free(info->rsp_state); }
    if (info->rsp_message) { free(info->rsp_message); }
    if (info->rsp_content_type) { free(info->rsp_content_type); }
    if (info->rsp_encode) { free(info->rsp_encode); }
    if (info->rsp_body_size) { free(info->rsp_body_size); }
//    if (info->rsp_heads) { free(info->rsp_heads); }
    free(info);
}


static void NONNULL(1)
protohttp_free(pxy_conn_ctx_t *ctx)
{
	protohttp_ctx_t *http_ctx = ctx->protoctx->arg;
	protohttp_free_ctx(http_ctx);
    conn_http_info_t *info = ctx->extra_info;
    if(info){
        protohttp_free_conn_info(info);
    }
}

static void NONNULL(1)
protohttps_free(pxy_conn_ctx_t *ctx)
{
	protohttp_free(ctx);
	protossl_free(ctx);
}

static void NONNULL(1)
protohttp_free_child(pxy_conn_child_ctx_t *ctx)
{
	protohttp_ctx_t *http_ctx = ctx->protoctx->arg;
	protohttp_free_ctx(http_ctx);
}

// @attention Called by thrmgr thread
protocol_t
protohttp_setup(pxy_conn_ctx_t *ctx)
{
	ctx->protoctx->proto = PROTO_HTTP;
	
	ctx->protoctx->bev_readcb = protohttp_bev_readcb;
	ctx->protoctx->bev_writecb = protohttp_bev_writecb;
	ctx->protoctx->proto_free = protohttp_free;

	ctx->protoctx->arg = malloc(sizeof(protohttp_ctx_t));
	if (!ctx->protoctx->arg) {
		return PROTO_ERROR;
	}
	memset(ctx->protoctx->arg, 0, sizeof(protohttp_ctx_t));
    
    ctx->extra_info = malloc(sizeof(conn_http_info_t));
    if (!ctx->extra_info) {
        return PROTO_ERROR;
    }
    memset(ctx->extra_info, 0, sizeof(conn_http_info_t));
    
	return PROTO_HTTP;
}

// @attention Called by thrmgr thread
protocol_t
protohttps_setup(pxy_conn_ctx_t *ctx)
{
	ctx->protoctx->proto = PROTO_HTTPS;
	ctx->protoctx->connectcb = protossl_conn_connect;
	ctx->protoctx->init_conn = protossl_init_conn;

	ctx->protoctx->bev_readcb = protohttp_bev_readcb;
	ctx->protoctx->bev_writecb = protohttp_bev_writecb;
	ctx->protoctx->bev_eventcb = protossl_bev_eventcb;

	ctx->protoctx->proto_free = protohttps_free;

	ctx->protoctx->arg = malloc(sizeof(protohttp_ctx_t));
	if (!ctx->protoctx->arg) {
		return PROTO_ERROR;
	}
	memset(ctx->protoctx->arg, 0, sizeof(protohttp_ctx_t));

	ctx->sslctx = malloc(sizeof(ssl_ctx_t));
	if (!ctx->sslctx) {
		free(ctx->protoctx->arg);
		return PROTO_ERROR;
	}
	memset(ctx->sslctx, 0, sizeof(ssl_ctx_t));
    
    ctx->extra_info = malloc(sizeof(conn_http_info_t));
    if (!ctx->extra_info) {
        return PROTO_ERROR;
    }
    memset(ctx->extra_info, 0, sizeof(conn_http_info_t));

	return PROTO_HTTPS;
}

protocol_t
protohttp_setup_child(pxy_conn_child_ctx_t *ctx)
{
	ctx->protoctx->proto = PROTO_HTTP;

	// @todo Should HTTP child conns do any http related processing, so use tcp defaults instead?
	ctx->protoctx->bev_readcb = protohttp_bev_readcb_child;
	ctx->protoctx->proto_free = protohttp_free_child;

	ctx->protoctx->arg = malloc(sizeof(protohttp_ctx_t));
	if (!ctx->protoctx->arg) {
		return PROTO_ERROR;
	}
	memset(ctx->protoctx->arg, 0, sizeof(protohttp_ctx_t));

	return PROTO_HTTP;
}

protocol_t
protohttps_setup_child(pxy_conn_child_ctx_t *ctx)
{
	ctx->protoctx->proto = PROTO_HTTPS;
	ctx->protoctx->connectcb = protossl_connect_child;

	ctx->protoctx->bev_readcb = protohttp_bev_readcb_child;
	ctx->protoctx->bev_eventcb = protossl_bev_eventcb_child;

	ctx->protoctx->proto_free = protohttp_free_child;

	ctx->protoctx->arg = malloc(sizeof(protohttp_ctx_t));
	if (!ctx->protoctx->arg) {
		return PROTO_ERROR;
	}
	memset(ctx->protoctx->arg, 0, sizeof(protohttp_ctx_t));

	return PROTO_HTTPS;
}

/* vim: set noet ft=c: */
