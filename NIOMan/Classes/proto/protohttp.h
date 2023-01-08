/*-
 */

#ifndef PROTOHTTP_H
#define PROTOHTTP_H

#include "pxyconn.h"

typedef struct conn_http_info conn_http_info_t;

typedef struct conn_http_info {
//    char *schemes; // https / http
    char *method; // get / post ...
    char *uri;    // xxx/xxx/xx
    char *host;   // www.xxx.com
//    char *port;   // 80
    char *suffix; // 后缀
    // req
    char *req_line;    // 请求行
//    char *req_version; // http 版本
    char *req_content_type; // json ...
    char *req_type;    //
    char *req_encode;  //
    char *req_body_size;
//    char *req_heads;   // 整个头
    char *req_target;  // safari / weixin ...
    // rsp
    char *rsp_line;     // 响应行
//    char *rsp_version;
    char *rsp_state;
    char *rsp_message;
    char *rsp_content_type;
    char *rsp_encode;
    char *rsp_body_size;
//    char *rsp_heads;
} conn_http_info_t;

typedef struct protohttp_ctx {
	unsigned int seen_req_header : 1; /* 0 until request header complete */
	unsigned int seen_resp_header : 1;  /* 0 until response hdr complete */
	unsigned int sent_http_conn_close : 1;   /* 0 until Conn: close sent */
	unsigned int ocsp_denied : 1;                /* 1 if OCSP was denied */
    
	/* log strings from HTTP request */
    char *http_req_line; // 请求行
	char *http_method;
	char *http_uri;
	char *http_host;
	char *http_content_type;

	/* log strings from HTTP response */
    char *http_rsp_line; // 响应行
	char *http_status_code;
	char *http_status_text;
	char *http_content_length;

	unsigned int not_valid : 1;    /* 1 if cannot find HTTP on first line */
	unsigned int seen_keyword_count;
	long long unsigned int seen_bytes;
} protohttp_ctx_t;

int protohttp_validate(pxy_conn_ctx_t *) NONNULL(1);

protocol_t protohttp_setup(pxy_conn_ctx_t *) NONNULL(1);
protocol_t protohttps_setup(pxy_conn_ctx_t *) NONNULL(1);

protocol_t protohttp_setup_child(pxy_conn_child_ctx_t *) NONNULL(1);
protocol_t protohttps_setup_child(pxy_conn_child_ctx_t *) NONNULL(1);

#endif /* !PROTOHTTP_H */

/* vim: set noet ft=c: */
