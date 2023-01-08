//
//  preconn.c
//  NIO2022
//
//  Created by LiuJie on 2022/3/9.
//

#include "preconn.h"
#include "protohttp.h"
#include "prototcp.h"
#include "protossl.h"
#include "protopassthrough.h"
#include "util.h"
#include "sys.h"

void pre_bev_end(pxy_conn_ctx_t *ctx){
//    printf("---> pre_bev_end: %llu \n",ctx->id);
    // 初始化请求
    ctx->ev = event_new(ctx->thr->evbase, -1, 0, ctx->protoctx->init_conn, ctx);
    if (!ctx->ev) {
        log_err_level(LOG_CRIT, "Error creating initial event, aborting connection");
        return;
    }
    // 一次性事件
    if (event_add(ctx->ev, NULL) == -1){
        return;
    }
    event_active(ctx->ev, 0, 0);
}

void pre_bev_dnscb(int errcode, struct evutil_addrinfo *ai, void *arg)
{
    pxy_conn_ctx_t *ctx = arg;
    if (ctx->dnsed == 1) {
        printf("---> 又调用了一次，干哦 DNS thr:%d - conn:%llu \n", ctx->thr->id,ctx->id);
        return;
    }
    ctx->dnsed = 1;
//    printf("---> DNS thr:%d - conn:%llu \n", ctx->thr->id,ctx->id);
    if (errcode) {
//        log_err_printf("Cannot resolve SNI hostname '%s': %s\n", ctx->srchost_str, evutil_gai_strerror(errcode));
        evutil_closesocket(ctx->fd);
//        pxy_conn_ctx_free(ctx, 1);
        return;
    }
    
    memcpy(&ctx->dstaddr, ai->ai_addr, ai->ai_addrlen);
    ctx->dstaddrlen = ai->ai_addrlen;
    evutil_freeaddrinfo(ai);
    // 开始连接
    ctx->dns_time_e = current_time();
    pre_bev_end(ctx);
}

static char * NONNULL(1,2) http_request_parse_line(const char *line, protohttp_ctx_t *http_ctx)
{
    /* parse information for connect log */
    if (!http_ctx->http_method) {
        /* first line */
        char *space1, *space2;
        http_ctx->http_req_line = malloc(sizeof(char) * (strlen(line) + 1));
        memcpy(http_ctx->http_req_line, line, strlen(line) + 1);
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
            } else {
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
            } else {
                return NULL;
            }
        }
    } else {
        /* not first line */
        if (!http_ctx->http_host && !strncasecmp(line, "Host:", 5)) {
            http_ctx->http_host = strdup(util_skipws(line + 5));
            if (!http_ctx->http_host) {
                return NULL;
            }
            http_ctx->seen_keyword_count++;
        }
    }
    return (char*)line;
}

void NONNULL(1) pre_setup_proto(pxy_conn_ctx_t *ctx, protocol_t proto)
{
    ctx->protoctx = malloc(sizeof(proto_ctx_t));
    memset(ctx->protoctx, 0, sizeof(proto_ctx_t));
    prototcp_setup(ctx);

    if(proto == PROTO_HTTPS){
//        printf("---> pre_setup_proto: %llu HTTPS \n",ctx->id);
        protohttps_setup(ctx);
    }else if (proto == PROTO_HTTP){
//        printf("---> pre_setup_proto: %llu HTTP \n",ctx->id);
        protohttp_setup(ctx);
    }
}

static void NONNULL(1) prehttp_free_ctx(protohttp_ctx_t *http_ctx)
{
    if (http_ctx->http_method) {
        free(http_ctx->http_method);
        http_ctx->http_method = NULL;
    }
    if (http_ctx->http_uri) {
        free(http_ctx->http_uri);
        http_ctx->http_uri = NULL;
    }
    if (http_ctx->http_host) {
        free(http_ctx->http_host);
        http_ctx->http_host = NULL;
    }
    if (http_ctx->http_req_line){
        free(http_ctx->http_req_line);
        http_ctx->http_req_line = NULL;
    }
    free(http_ctx);
    http_ctx = NULL;
}

char *find_ip_address(char *uri, char *host){
    
    return "";
}

char *find_port(char *uri, char *host){
    
    return "";
}

// 协议匹配
void pre_bev_proto_match(char *packet, size_t packet_size, pxy_conn_ctx_t *ctx){
//    struct evbuffer *inbuf;
    struct evbuffer *first_packet_buf = NULL;
    first_packet_buf = evbuffer_new();
    evbuffer_add(first_packet_buf, packet, packet_size);
    // 尝试http request 解析
    char *line;
    protohttp_ctx_t *http_ctx = malloc(sizeof(protohttp_ctx_t));
    memset(http_ctx, 0, sizeof(protohttp_ctx_t));
    while ((line = evbuffer_readln(first_packet_buf, NULL, EVBUFFER_EOL_CRLF))) {
        log_finest_va("%s", line);
        http_request_parse_line(line, http_ctx);
//        printf("--> 读取内容 thr:%d - conn:%llu - %s\n",ctx->thr->id,ctx->id,line);
//        printf("%s\n",line);
        free(line);
    }
    evbuffer_free(first_packet_buf);
    
    if(!http_ctx->http_host){ // tcp
        printf("%d ---- 未知协议 : %s \n",ctx->fd, packet);
        evutil_closesocket(ctx->fd);
        free(ctx);
    }else{ // http or ...
//        printf("%d ---- \n",ctx->fd);
        // 通过方法名是不是connect来判断是否是https
        if(http_ctx->http_method && http_ctx->http_host){
            char *port = "80";
            char *host = http_ctx->http_host;
            if(http_ctx->http_uri){
                // 结合uri和host,返回端口号和host并判断host是否为ip地址
                host = findHost(http_ctx->http_host,http_ctx->http_uri);
                port = findPort(http_ctx->http_host,http_ctx->http_uri);
                printf("--> host:%s\t port:%s \n",host,port);
            }
            if(!strncmp(http_ctx->http_method, "CONNECT", 7)){// https
//                port = "443";
                struct evbuffer *srcInbuf = bufferevent_get_input(ctx->src.bev);
                struct evbuffer *srcOutbuf = bufferevent_get_output(ctx->src.bev);
                evbuffer_drain(srcInbuf, evbuffer_get_length(srcInbuf));
                char *connected_rsp = "HTTP/1.0 200 Connection established\r\n\r\n";
                evbuffer_add_printf(srcOutbuf, "%s", connected_rsp);
                
                ctx->proto = PROTO_HTTPS;
                pre_setup_proto(ctx,PROTO_HTTPS);
                
                conn_http_info_t *http_info = ctx->extra_info;
                http_info->method = http_ctx->http_method;
                http_info->uri = http_ctx->http_uri;
                http_info->host = http_ctx->http_host;
                http_info->req_line = http_ctx->http_req_line;
                
                bufferevent_disable(ctx->src.bev, EV_READ);
                
                pre_bev_end(ctx);
//                prehttp_free_ctx(http_ctx); // 不需要在这里释放，后面会由http_info释放
                return;
            }else{
                ctx->proto = PROTO_HTTP;
                pre_setup_proto(ctx,PROTO_HTTP);
                bufferevent_disable(ctx->src.bev, EV_READ);
                
                // http单独进行dns请求，http会从ssl握手信息里读取host并进行dns
//                printf("开始DNS请求 host:%s - thr:%d - conn:%llu \n",http_ctx->http_host, ctx->thr->id,ctx->id);
                ctx->dns_time_s = current_time();
                
                char sniport[6];
                struct evutil_addrinfo hints;
                memset(&hints, 0, sizeof(hints));
                hints.ai_family = AF_UNSPEC;
                hints.ai_flags = EVUTIL_AI_ADDRCONFIG;
                hints.ai_socktype = SOCK_STREAM;
                hints.ai_protocol = IPPROTO_TCP;
                snprintf(sniport, sizeof(sniport), "%s", port);// ctx->spec->sni_port
                evdns_getaddrinfo(ctx->thr->dnsbase, http_ctx->http_host, sniport, &hints, pre_bev_dnscb, ctx);
            }
        }
    }
    prehttp_free_ctx(http_ctx);
}

/*
 * 读取监督端口的数据，用于协议判断以及dns解析
 */
void pre_bev_readcb(struct bufferevent *bev, void *arg)
{
//    printf("pre_bev_readcb\n");
    pxy_conn_ctx_t *ctx = arg;
    
    struct evbuffer *inbuf = bufferevent_get_input(bev);
    // peer第一个包，用于协议判断，连通后发给dst
    ctx->src.ssl = NULL;
    
    
    size_t packet_size = evbuffer_get_length(inbuf);
    char *packet = (char *)pxy_malloc_packet(packet_size, ctx);
    if (!packet) {
        evutil_closesocket(ctx->fd);
//        printf("--> pre_bev_readcb thr 释放了:%d - conn:%llu \n",ctx->thr->id,ctx->id);
        free(ctx);
        return;
    }
    if (evbuffer_copyout(inbuf, packet, packet_size) == -1) {
        free(packet);
        evutil_closesocket(ctx->fd);
//        printf("--> pre_bev_readcb thr 释放了:%d - conn:%llu \n",ctx->thr->id,ctx->id);
        free(ctx);
        return;
    }
//    printf("--> pre_bev_readcb thr:%d - conn:%llu \n",ctx->thr->id,ctx->id);
    pre_bev_proto_match(packet, packet_size, ctx);
    free(packet);
}

void
pre_bev_writecb(struct bufferevent *bev, void *arg)
{
//    printf("pre_bev_writecb\n");
}

// pre期间如果出错，则直接销毁ctx
void pre_bev_eventcb(struct bufferevent *bev, short events, void *arg)
{
//    printf("pre_bev_eventcb：%hd \n", events);
    pxy_conn_ctx_t *ctx = arg;
    
    if (events & BEV_EVENT_ERROR) {
        log_err_printf("Client-side BEV_EVENT_ERROR\n");
        evutil_closesocket(ctx->fd);
        free(ctx);
    }
}

void pre_conn(evutil_socket_t fd, UNUSED short what, void *arg){
    
    pxy_conn_ctx_t *ctx = arg;
//    printf("pre_conn:%d - %d \n", fd, ctx->fd);
    event_free(ctx->ev);
    ctx->ev = NULL;

    struct bufferevent *prebev = bufferevent_socket_new(ctx->thr->evbase, ctx->fd, BEV_OPT_DEFER_CALLBACKS);
    ctx->src.bev = prebev;
    if (!prebev) {
        log_err_level(LOG_CRIT, "Error creating bufferevent socket");
        goto out;
    }
    bufferevent_setcb(prebev, pre_bev_readcb, pre_bev_writecb, NULL, ctx);
    bufferevent_enable(prebev, EV_READ|EV_WRITE);
    return;
out:
    evutil_closesocket(ctx->fd);
    free(ctx);
}
