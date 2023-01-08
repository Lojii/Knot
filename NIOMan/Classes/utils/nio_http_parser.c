//
//  nio_http_parser.c
//  NIOMan
//
//  Created by LiuJie on 2022/3/30.
//

#include <stdio.h>
#include "http_parser.h"
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

// 用于解析的回调函数
int onMessageBegin(http_parser* pParser);
int onHeaderComplete(http_parser* pParser);
int onMessageComplete(http_parser* pParser);
int onURL(http_parser* pParser, const char *at, size_t length);
int onStatus(http_parser* pParser, const char *at, size_t length);
int onHeaderField(http_parser* pParser, const char *at, size_t length);
int onHeaderValue(http_parser* pParser, const char *at, size_t length);
int onBody(http_parser* pParser, const char *at, size_t length);
int onChunkHeader(http_parser* p);
int onChunkComplete(http_parser* p);

typedef struct parser_ctx{
    int finish;             // 0:未结束   1:结束
    int headerComplete;     // 0:未结束  1:结束
    int messageComplete;    // 0:未结束  1:结束
    
    FILE *head_f;
    FILE *body_f;
} parser_ctx_t;

int parse_http(char *file_path){
    // line
    char *line_path = malloc(strlen(file_path) + strlen(".line"));
    asprintf(&line_path, "%s%s", file_path, ".line");
    FILE *line_fp = fopen(line_path,"w");
    if(!line_fp) { free(line_path); return 1; }
    char *line;
    size_t line_len;
    FILE *f;
    f = fopen(file_path, "r");
    if (!f) {
        fclose(line_fp);
        return -1;
    }
    line = NULL;
    if (getline(&line, &line_len, f) == -1) {
        fclose(line_fp);
        fclose(f);
        return -1;
    }
    if (line == NULL) {
        fclose(line_fp);
        fclose(f);
        return -1;
    }
    fprintf(line_fp,"%s",line);
    free(line);
    line = NULL;
    fclose(line_fp);
    fclose(f);
    
    // head and body
    char *head_path = malloc(strlen(file_path) + strlen(".head"));
    asprintf(&head_path, "%s%s", file_path, ".head");
    FILE *head_fp = fopen(head_path,"w");
    if(!head_fp) {
        printf("head_path创建失败!\n");
        free(head_path);
        return 1;
    }
    char *body_path = malloc(strlen(file_path) + strlen(".body"));
    asprintf(&body_path, "%s%s", file_path, ".body");
    FILE *body_fp = fopen(body_path,"w");
    if(!body_fp) {
        printf("body_path创建失败!\n");
        free(body_path);
        return 1;
    }
    // 解析head和body
    http_parser httpParser;
    http_parser_settings httpSettings;
    
    parser_ctx_t *ctx = malloc(sizeof(parser_ctx_t));
    ctx->finish = 0;
    ctx->headerComplete = 0;
    ctx->messageComplete = 0;
    ctx->head_f = head_fp;
    ctx->body_f = body_fp;
    httpParser.data = ctx;
    
    // 初使化解析器及回调函数
    http_parser_init(&httpParser, HTTP_BOTH);
    
    http_parser_settings_init(&httpSettings);
    httpSettings.on_message_begin = onMessageBegin;
    httpSettings.on_headers_complete = onHeaderComplete;
    httpSettings.on_message_complete = onMessageComplete;
    httpSettings.on_url = onURL;
    httpSettings.on_status = onStatus;
    httpSettings.on_header_field = onHeaderField;
    httpSettings.on_header_value = onHeaderValue;
    httpSettings.on_body = onBody;
    httpSettings.on_chunk_header = onChunkHeader;
    httpSettings.on_chunk_complete = onChunkComplete;

    // 一次性读取解析，逐行读取行不通
    FILE *http_f;
    long lSize;
    char * buffer;
    size_t result;

    http_f = fopen(file_path, "rb"); // 二进制的方式读取
    /* 获取文件大小 */
    fseek (http_f , 0 , SEEK_END);
    lSize = ftell (http_f);
    rewind (http_f);
    /* 分配内存存储整个文件 */
    buffer = (char*) malloc (sizeof(char)*lSize);
    if (buffer == NULL){
        printf ("parse_http Memory error");
        goto fail;
    }
    /* 将文件拷贝到buffer中 */
    result = fread (buffer,1,lSize,http_f);
    if (result != lSize){
        printf ("parse_http Reading error");
        goto fail;
    }
//    ctx->http_f = http_f;
    http_parser_execute(&httpParser, &httpSettings, buffer, lSize);

    // 资源释放
    free (buffer);
    fclose(http_f);
    fclose(ctx->head_f);
    fclose(ctx->body_f);
    free(ctx);
    return 1;
fail:
    fclose(http_f);
    if (buffer != NULL) {
        free (buffer);
    }
    fclose(ctx->head_f);
    fclose(ctx->body_f);
    free(ctx);
    return -1;
}

int onMessageBegin(http_parser* pParser)
{
    printf("@onMessageBegin call \n");
//    bParsed = false;
    return 0;
}

int onHeaderComplete(http_parser* pParser)
{
    printf("@onHeaderComplete call \n");
    return 0;
}

int onMessageComplete(http_parser* pParser)
{
    printf("@onMessageComplete call \n");
    printf("----------------------------------\n");
    return 0;
}

int onURL(http_parser* pParser, const char *at, size_t length)
{
    printf("onURL: %.*s\n", (int)length, at);
    return 0;
}

int onStatus(http_parser* pParser, const char *at, size_t length)
{
    printf("onStatus: %.*s\n", (int)length, at);
    return 0;
}

int onHeaderField(http_parser* pParser, const char *at, size_t length)
{
//    printf("onHeaderField: %.*s\n", (int)length, at);
    parser_ctx_t *ctx = pParser->data;
    fprintf(ctx->head_f,"%.*s", (int)length, at);
    return 0;
}

int onHeaderValue(http_parser* pParser, const char *at, size_t length)
{
//    printf("onHeaderValue: %.*s\n", (int)length, at);
    parser_ctx_t *ctx = pParser->data;
    fprintf(ctx->head_f,":%.*s\r\n", (int)length, at);
    return 0;
}

int onBody(http_parser* pParser, const char *at, size_t length)
{
//    printf("@onBody call, length:[%zu]\n", length);
    parser_ctx_t *ctx = pParser->data;
//    fprintf(ctx->body_f,"%.*s", (int)length, at);
    fwrite(at, length,  1, ctx->body_f);
    return 0;
}

int onChunkHeader(http_parser* p)
{
    printf("@onChunkHeader call\n");
    return 0;
}

int onChunkComplete(http_parser* p){
    printf("@onChunkComplete call\n");
    return 0;
}
