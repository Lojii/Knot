/*-
 */

#ifndef LOG_H
#define LOG_H

#include "defaults.h"
#include "opts.h"
#include "proxy.h"
#include "logger.h"
#include "attrib.h"

int log_err_printf(const char *, ...) PRINTF(1,2);
int log_err_level_printf(int, const char *, ...) PRINTF(2,3);
void log_err_mode(int);
#define LOG_ERR_MODE_STDERR 0
#define LOG_ERR_MODE_SYSLOG 1

int log_dbg_printf(const char *, ...) PRINTF(1,2);
int log_dbg_level_printf(int, const char *, int, long long unsigned int, evutil_socket_t, evutil_socket_t, const char *, ...) PRINTF(7,8);
int log_dbg_print_free(char *);
int log_dbg_write_free(void *, size_t);
void log_dbg_mode(int);

#define LOG_DBG_MODE_NONE 0
#define LOG_DBG_MODE_ERRLOG 1
#define LOG_DBG_MODE_FINE 2
#define LOG_DBG_MODE_FINER 3
#define LOG_DBG_MODE_FINEST 4

// Don't use the following __FUNCTION__ definition, because __PRETTY_FUNCTION__ prints a detailed function signature on OpenBSD
//#define __FUNCTION__ __extension__ __PRETTY_FUNCTION__
#if defined __STDC_VERSION__ && __STDC_VERSION__ >= 199901L
#define __FUNCTION__ __func__
#else
#define __FUNCTION__ ((const char *) 0)
#endif

// @attention We don't use ## __VA_ARGS__ to fix missing variable args,
// because it still gives warnings about ISO C99 requiring at least one argument for the "..." in a variadic macro
// Instead, we define two versions of the same macro, first for no args and second for variable args (*_va)
#ifdef DEBUG_PROXY
// FINE
#define log_fine_main_va(format_str, ...) \
		log_dbg_level_printf(LOG_DBG_MODE_FINE, __FUNCTION__, 0, 0, 0, 0, (format_str), __VA_ARGS__)
#define log_fine(str) \
		log_dbg_level_printf(LOG_DBG_MODE_FINE, __FUNCTION__, ctx->conn->thr ? ctx->conn->thr->id : 0, ctx->conn->id, ctx->conn->fd, ctx->conn->child_fd, (str))
#define log_fine_va(format_str, ...) \
		log_dbg_level_printf(LOG_DBG_MODE_FINE, __FUNCTION__, ctx->conn->thr ? ctx->conn->thr->id : 0, ctx->conn->id, ctx->conn->fd, ctx->conn->child_fd, (format_str), __VA_ARGS__)

// FINER
#define log_finer_main_va(format_str, ...) \
		log_dbg_level_printf(LOG_DBG_MODE_FINER, __FUNCTION__, 0, 0, 0, 0, (format_str), __VA_ARGS__)
#define log_finer(str) \
		log_dbg_level_printf(LOG_DBG_MODE_FINER, __FUNCTION__, ctx->conn->thr ? ctx->conn->thr->id : 0, ctx->conn->id, ctx->conn->fd, ctx->conn->child_fd, (str))
#define log_finer_va(format_str, ...) \
		log_dbg_level_printf(LOG_DBG_MODE_FINER, __FUNCTION__, ctx->conn->thr ? ctx->conn->thr->id : 0, ctx->conn->id, ctx->conn->fd, ctx->conn->child_fd, (format_str), __VA_ARGS__)

// FINEST
#define log_finest_main(str) \
		log_dbg_level_printf(LOG_DBG_MODE_FINEST, __FUNCTION__, 0, 0, 0, 0, (str))
#define log_finest_main_va(format_str, ...) \
		log_dbg_level_printf(LOG_DBG_MODE_FINEST, __FUNCTION__, 0, 0, 0, 0, (format_str), __VA_ARGS__)
#define log_finest(str) \
		log_dbg_level_printf(LOG_DBG_MODE_FINEST, __FUNCTION__, ctx->conn->thr ? ctx->conn->thr->id : 0, ctx->conn->id, ctx->conn->fd, ctx->conn->child_fd, (str))
#define log_finest_va(format_str, ...) \
		log_dbg_level_printf(LOG_DBG_MODE_FINEST, __FUNCTION__, ctx->conn->thr ? ctx->conn->thr->id : 0, ctx->conn->id, ctx->conn->fd, ctx->conn->child_fd, (format_str), __VA_ARGS__)
#else /* !DEBUG_PROXY */
#define log_fine_main_va(format_str, ...) ((void)0)
#define log_fine(str) ((void)0)
#define log_fine_va(format_str, ...) ((void)0)

#define log_finer_main_va(format_str, ...) ((void)0)
#define log_finer(str) ((void)0)
#define log_finer_va(format_str, ...) ((void)0)

#define log_finest_main(str) ((void)0)
#define log_finest_main_va(format_str, ...) ((void)0)
#define log_finest(str) ((void)0)
#define log_finest_va(format_str, ...) ((void)0)
#endif /* !DEBUG_PROXY */

#define log_err_level(level, str) { log_err_level_printf((level), (str"\n")); log_fine((str)); }

extern logger_t *masterkey_log;
#define log_masterkey_printf(fmt, ...) \
        logger_printf(masterkey_log, NULL, 0, (fmt), __VA_ARGS__)
#define log_masterkey_print(s) \
        logger_print(masterkey_log, NULL, 0, (s))
#define log_masterkey_write(buf, sz) \
        logger_write(masterkey_log, NULL, 0, (buf), (sz))
#define log_masterkey_print_free(s) \
        logger_print_freebuf(masterkey_log, NULL, 0, (s))
#define log_masterkey_write_free(buf, sz) \
        logger_write_freebuf(masterkey_log, NULL, 0, (buf), (sz))

extern logger_t *connect_log;
#define log_connect_printf(fmt, ...) \
        logger_printf(connect_log, NULL, 0, (fmt), __VA_ARGS__)
#define log_connect_print(s) \
        logger_print(connect_log, NULL, 0, (s))
#define log_connect_write(buf, sz) \
        logger_write(connect_log, NULL, 0, (buf), (sz))
#define log_connect_print_free(s) \
        logger_print_freebuf(connect_log, NULL, 0, (s))
#define log_connect_write_free(buf, sz) \
        logger_write_freebuf(connect_log, NULL, 0, (buf), (sz))

int log_stats(const char *);
int log_conn(const char *);

typedef struct log_content_ctx log_content_ctx_t;
struct log_content_file_ctx;
struct log_content_pcap_ctx;
struct log_content_ctx {
	struct log_content_file_ctx *file;
	struct log_content_pcap_ctx *pcap;
};
int log_content_open(log_content_ctx_t *, global_t *,
                     const struct sockaddr *, socklen_t,
                     const struct sockaddr *, socklen_t,
                     char *, char *, char *, char *,
                     char *, char *, char *, int, int,
                     char *, long long unsigned int) NONNULL(1,2,3) WUNRES;
int log_content_submit(log_content_ctx_t *, logbuf_t *, int, int, int) NONNULL(1,2) WUNRES;
int log_content_close(log_content_ctx_t *, int) NONNULL(1) WUNRES;
int log_content_split_pathspec(const char *, char **,
                               char **) NONNULL(1,2,3) WUNRES;

int log_cert_submit(const char *, X509 *) NONNULL(1,2) WUNRES;

int log_preinit(global_t *) NONNULL(1) WUNRES;
void log_preinit_undo(void);
int log_init(global_t *, proxy_ctx_t *, int[3]) NONNULL(1,2) WUNRES;
void log_fini(void);
int log_reopen(void) WUNRES;
void log_exceptcb(void);

#endif /* !LOG_H */

/* vim: set noet ft=c: */
