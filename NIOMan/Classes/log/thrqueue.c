/*-
 */

#include "thrqueue.h"

#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <stdio.h>
/*
 * Thread-safe, bounded-size queue based on pthreads mutex and conds.
 * Both enqueue and dequeue are available in a blocking and non-blocking
 * version.
 */

struct thrqueue {
	void **data;
	size_t sz, n;
	size_t in, out;
	unsigned int block_enqueue : 1;
	unsigned int block_dequeue : 1;
	pthread_mutex_t mutex;
	pthread_cond_t notempty;
	pthread_cond_t notfull;
};

/*
 * Create a new thread-safe queue of size sz.
 */
thrqueue_t *
thrqueue_new(size_t sz)
{
	thrqueue_t *queue;

	if (!(queue = malloc(sizeof(thrqueue_t))))
		goto out0;
	if (!(queue->data = malloc(sz * sizeof(void*))))
		goto out1;
	if (pthread_mutex_init(&queue->mutex, NULL))
		goto out2;
	if (pthread_cond_init(&queue->notempty, NULL))
		goto out3;
	if (pthread_cond_init(&queue->notfull, NULL))
		goto out4;
	queue->sz = sz;
	queue->n = 0;
	queue->in = 0;
	queue->out = 0;
	queue->block_enqueue = 1;
	queue->block_dequeue = 1;
	return queue;

out4:
	pthread_cond_destroy(&queue->notempty);
out3:
	pthread_mutex_destroy(&queue->mutex);
out2:
	free(queue->data);
out1:
	free(queue);
out0:
	return NULL;
}

/*
 * Free all resources associated with queue.
 * The caller must ensure that there are no threads still
 * using the queue when it is free'd.
 */
void
thrqueue_free(thrqueue_t *queue)
{
	free(queue->data);
	pthread_mutex_destroy(&queue->mutex);
	pthread_cond_destroy(&queue->notempty);
	pthread_cond_destroy(&queue->notfull);
	free(queue);
}

/*
 * Enqueue an item into the queue.  Will block if the queue is full.
 * If enqueue has been switched to non-blocking mode, never blocks
 * but instead returns NULL if queue is full.
 * Returns enqueued item on success.
 */
void *
thrqueue_enqueue(thrqueue_t *queue, void *item)
{
//    printf("添加写入！\n");
	pthread_mutex_lock(&queue->mutex);
	while (queue->n == queue->sz) {
		if (!queue->block_enqueue) {
			pthread_mutex_unlock(&queue->mutex);
			return NULL;
		}
		pthread_cond_wait(&queue->notfull, &queue->mutex);
	}
	queue->data[queue->in++] = item;
	queue->in %= queue->sz;
	queue->n++;
	pthread_mutex_unlock(&queue->mutex);
	pthread_cond_broadcast(&queue->notempty);
	return item;
}

/*
 * Non-blocking enqueue.  Never blocks.
 * Returns NULL if the queue is full.
 * Returns the enqueued item on success.
 */
void *
thrqueue_enqueue_nb(thrqueue_t *queue, void *item)
{
	pthread_mutex_lock(&queue->mutex);
	if (queue->n == queue->sz) {
		pthread_mutex_unlock(&queue->mutex);
		return NULL;
	}
	queue->data[queue->in++] = item;
	queue->in %= queue->sz;
	queue->n++;
	pthread_mutex_unlock(&queue->mutex);
	pthread_cond_signal(&queue->notempty);
	return item;
}

/*
 * Dequeue an item from the queue.  Will block if the queue is empty.
 * If dequeue has been switched to non-blocking mode, never blocks
 * but instead returns NULL if queue is empty.
 * Returns dequeued item on success.
 */
void *
thrqueue_dequeue(thrqueue_t *queue)
{
	void *item;

	pthread_mutex_lock(&queue->mutex);
	while (queue->n == 0) {
		if (!queue->block_dequeue) {
			pthread_mutex_unlock(&queue->mutex);
			return NULL;
		}
		pthread_cond_wait(&queue->notempty, &queue->mutex);
	}
	item = queue->data[queue->out++];
	queue->out %= queue->sz;
	queue->n--;
	pthread_mutex_unlock(&queue->mutex);
	pthread_cond_signal(&queue->notfull);
	return item;
}

/*
 * Non-blocking dequeue.  Never blocks.
 * Returns NULL if the queue is empty.
 * Returns the dequeued item on success.
 */
void *
thrqueue_dequeue_nb(thrqueue_t *queue)
{
	void *item;

	pthread_mutex_lock(&queue->mutex);
	if (queue->n == 0) {
		pthread_mutex_unlock(&queue->mutex);
		return NULL;
	}
	item = queue->data[queue->out++];
	queue->out %= queue->sz;
	queue->n--;
	pthread_mutex_unlock(&queue->mutex);
	pthread_cond_signal(&queue->notfull);
	return item;
}

/*
 * Permanently make all enqueue operations on queue non-blocking and wake
 * up all threads currently waiting for the queue to become not full.
 * This is to allow threads to finish their work on the queue on application
 * shutdown, but not be blocked forever.
 */
void
thrqueue_unblock_enqueue(thrqueue_t *queue)
{
	queue->block_enqueue = 0;
	pthread_cond_broadcast(&queue->notfull);
	sched_yield();
}

/*
 * Permanently make all dequeue operations on queue non-blocking and wake
 * up all threads currently waiting for the queue to become not empty.
 * This is to allow threads to finish their work on the queue on application
 * shutdown, but not be blocked forever.
 */
void
thrqueue_unblock_dequeue(thrqueue_t *queue)
{
	queue->block_dequeue = 0;
	pthread_cond_broadcast(&queue->notempty);
	sched_yield();
}

/* vim: set noet ft=c: */
