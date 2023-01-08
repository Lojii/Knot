/*-
 */

#ifndef LOGBUF_H
#define LOGBUF_H

#include "attrib.h"

#include <stdlib.h>
#include <unistd.h>

typedef struct logbuf {
	int prio;
	unsigned char *buf;
	ssize_t sz;
	void *fh;
	unsigned long ctl;
	struct logbuf *next;
} logbuf_t;

typedef ssize_t (*writefunc_t)(int, void *, unsigned long, const void *, size_t);

logbuf_t * logbuf_new(int, void *, size_t, logbuf_t *) MALLOC;
logbuf_t * logbuf_new_alloc(size_t, logbuf_t *) MALLOC;
logbuf_t * logbuf_new_copy(const void *, size_t, logbuf_t *) MALLOC;
logbuf_t * logbuf_new_printf(logbuf_t *, const char *, ...) MALLOC PRINTF(2,3);
logbuf_t * logbuf_new_deepcopy(logbuf_t *, int) MALLOC;
logbuf_t * logbuf_make_contiguous(logbuf_t *) WUNRES;
ssize_t logbuf_size(logbuf_t *) NONNULL(1) WUNRES;
ssize_t logbuf_write_free(logbuf_t *, writefunc_t) NONNULL(1);
void logbuf_free(logbuf_t *) NONNULL(1);

#define logbuf_ctl_clear(x) (x)->ctl = 0
#define logbuf_ctl_set(x, y) (x)->ctl |= (y)
#define logbuf_ctl_unset(x, y) (x)->ctl &= ~(y)
#define logbuf_ctl_isset(x, y) (!!((x)->ctl & (y)))

#define LBFLAG_REOPEN   (1 << 0)        /* logger */
#define LBFLAG_OPEN     (1 << 1)        /* logger */
#define LBFLAG_CLOSE    (1 << 2)        /* logger */
#define LBFLAG_IS_REQ   (1 << 3)        /* pcap/mirror content log */
#define LBFLAG_IS_RESP  (1 << 4)        /* pcap/mirror content log */

#endif /* !LOGBUF_H */

/* vim: set noet ft=c: */
