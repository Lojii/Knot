/*-
 */

#ifndef DYNBUF_H
#define DYNBUF_H

#include "attrib.h"

#include <stdlib.h>

typedef struct dynbuf {
	unsigned char *buf;
	size_t sz;
} dynbuf_t;

dynbuf_t * dynbuf_new(unsigned char *, size_t) MALLOC;
dynbuf_t * dynbuf_new_alloc(size_t) MALLOC;
dynbuf_t * dynbuf_new_copy(const unsigned char *, const size_t) MALLOC;
dynbuf_t * dynbuf_new_file(const char *) MALLOC;
void dynbuf_free(dynbuf_t *) NONNULL(1);

#endif /* !DYNBUF_H */

/* vim: set noet ft=c: */
