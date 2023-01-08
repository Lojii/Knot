/*-
 */

#ifndef UTIL_H
#define UTIL_H

#include "attrib.h"

#include <string.h>

char * util_skipws(const char *) NONNULL(1) PURE;
size_t util_get_first_word_len(char *, size_t) NONNULL(1);

double current_time(void); // 时间，精确到微妙

#define util_max(a,b) ((a) > (b) ? (a) : (b))

#define equal(s1, s2) (strlen((s1)) == strlen((s2)) && !strcmp((s1), (s2)))

inline int INLINE WUNRES
max(int a, int b)
{
	return a > b ? a : b;
}

#endif /* !UTIL_H */

/* vim: set noet ft=c: */
