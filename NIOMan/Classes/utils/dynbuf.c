/*-
 */

#include "dynbuf.h"

#include <string.h>
#include <stdio.h>

/*
 * Simple dynamic buffer, consisting of internal buffer ptr plus length.
 * Dynbuf always owns the internal allocated buffer.
 */

/*
 * Allocate new dynbuf; will allocate sz bytes of memory in ->buf.
 */
dynbuf_t *
dynbuf_new_alloc(size_t sz)
{
	dynbuf_t *db;

	if (!(db = malloc(sizeof(dynbuf_t))))
		return NULL;
	if (!(db->buf = malloc(sz))) {
		free(db);
		return NULL;
	}
	db->sz = sz;
	return db;
}

/*
 * Create new dynbuf from provided buffer, which is copied.
 */
dynbuf_t *
dynbuf_new_copy(const unsigned char *buf, const size_t sz)
{
	dynbuf_t *db;

	if (!(db = malloc(sizeof(dynbuf_t))))
		return NULL;
	if (!(db->buf = malloc(sz))) {
		free(db);
		return NULL;
	}
	memcpy(db->buf, buf, sz);
	db->sz = sz;
	return db;
}

/*
 * Create new dynbuf by loading a file into a newly allocated internal buffer.
 * The provided buffer will be freed by dynbuf_free().
 */
dynbuf_t *
dynbuf_new_file(const char *filename)
{
	dynbuf_t *db;
	FILE *f;

	if (!(db = malloc(sizeof(dynbuf_t))))
		return NULL;

	f = fopen(filename, "rb");
	if (!f) {
		free(db);
		return NULL;
	}
	fseek(f, 0, SEEK_END);
	db->sz = ftell(f);
	fseek(f, 0, SEEK_SET);
	if (!(db->buf = malloc(db->sz))) {
		free(db);
		fclose(f);
		return NULL;
	}
	if (fread(db->buf, db->sz, 1, f) != 1) {
		free(db->buf);
		free(db);
		fclose(f);
		return NULL;
	}
	fclose(f);
	return db;
}

/*
 * Create new dynbuf from provided, pre-allocated buffer.
 * The provided buffer will be freed by dynbuf_free().
 */
dynbuf_t *
dynbuf_new(unsigned char *buf, size_t sz)
{
	dynbuf_t *db;

	if (!(db = malloc(sizeof(dynbuf_t))))
		return NULL;
	db->buf = buf;
	db->sz = sz;
	return db;
}

/*
 * Free dynbuf including internal buffer.
 */
void
dynbuf_free(dynbuf_t *db)
{
	free(db->buf);
	free(db);
}

/* vim: set noet ft=c: */
