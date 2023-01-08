/*-
 */

#ifndef BASE64_H
#define BASE64_H

#include "attrib.h"

#include <stdlib.h>

unsigned char * base64_dec(const char *, size_t, size_t *) NONNULL(1,3) MALLOC;
char * base64_enc(const unsigned char *, size_t, size_t *) NONNULL(1,3) MALLOC;

#endif /* !BASE64_H */

/* vim: set noet ft=c: */
