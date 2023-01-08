/*-
 */

#ifndef LOGGER_H
#define LOGGER_H

#include "logbuf.h"
#include "attrib.h"

#include <unistd.h>
#include <pthread.h>

typedef int (*logger_reopen_func_t)(void);
typedef int (*logger_open_func_t)(void *);
typedef void (*logger_close_func_t)(void *, unsigned long);
typedef ssize_t (*logger_write_func_t)(int, void *, unsigned long,
                                       const void *, size_t);
typedef logbuf_t * (*logger_prep_func_t)(void *, unsigned long, logbuf_t *);
typedef void (*logger_except_func_t)(void);
typedef struct logger logger_t;

logger_t * logger_new(logger_reopen_func_t, logger_open_func_t,
                      logger_close_func_t, logger_write_func_t,
                      logger_prep_func_t, logger_except_func_t)
                      NONNULL(4,6) MALLOC;
void logger_free(logger_t *) NONNULL(1);
int logger_start(logger_t *) NONNULL(1) WUNRES;
void logger_leave(logger_t *) NONNULL(1);
int logger_join(logger_t *) NONNULL(1);
int logger_stop(logger_t *) NONNULL(1) WUNRES;
int logger_reopen(logger_t *) NONNULL(1) WUNRES;
int logger_open(logger_t *, void *) NONNULL(1,2) WUNRES;
int logger_close(logger_t *, void *, unsigned long) NONNULL(1,2) WUNRES;
int logger_submit(logger_t *, void *, unsigned long,
                  logbuf_t *) NONNULL(1) WUNRES;
int logger_printf(logger_t *, void *, unsigned long,
                  const char *, ...) PRINTF(4,5) NONNULL(1,4) WUNRES;
int logger_print(logger_t *, void *, unsigned long,
                 const char *) NONNULL(1,4) WUNRES;
int logger_write(logger_t *, void *, unsigned long,
                 const void *, size_t) NONNULL(1,4) WUNRES;
int logger_print_freebuf(logger_t *, void *, unsigned long,
                         char *) NONNULL(1,4) WUNRES;
int logger_write_freebuf(logger_t *, int, void *, unsigned long,
                         void *, size_t) NONNULL(1,5) WUNRES;

#endif /* !LOGGER_H */

/* vim: set noet ft=c: */
