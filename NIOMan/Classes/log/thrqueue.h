/*-
 */

#ifndef THRQUEUE_H
#define THRQUEUE_H

#include "attrib.h"

#include <unistd.h>

typedef struct thrqueue thrqueue_t;

thrqueue_t * thrqueue_new(size_t) MALLOC;
void thrqueue_free(thrqueue_t *) NONNULL(1);

void * thrqueue_enqueue(thrqueue_t *, void *) NONNULL(1) WUNRES;
void * thrqueue_enqueue_nb(thrqueue_t *, void *) NONNULL(1) WUNRES;
void * thrqueue_dequeue(thrqueue_t *) NONNULL(1) WUNRES;
void * thrqueue_dequeue_nb(thrqueue_t *) NONNULL(1) WUNRES;
void thrqueue_unblock_enqueue(thrqueue_t *) NONNULL(1);
void thrqueue_unblock_dequeue(thrqueue_t *) NONNULL(1);

#endif /* !THRQUEUE_H */

/* vim: set noet ft=c: */
