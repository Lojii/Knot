/*-
 */

#ifndef URL_H
#define URL_H

#include "attrib.h"

#include <stdlib.h>

char * url_dec(const char *, size_t, size_t *) NONNULL(1,3) MALLOC;

#endif /* !URL_H */

/* vim: set noet ft=c: */
