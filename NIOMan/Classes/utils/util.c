/*-
 */

#include <string.h>
#include <sys/time.h>
#include <stdio.h>
#include <stdlib.h>
/*
 * Various utility functions.
 */

/*
 * Returns a pointer to the first non-whitespace character in s.
 * Only space and tab characters are considered whitespace.
 */
char *
util_skipws(const char *s)
{
	return (char*) s + strspn(s, " \t");
}

/*
 * Returns the length of the first word in a given memory area.
 * Memory area may not be null-terminated, hence we cannot use string
 * manipulation functions.
 */
size_t
util_get_first_word_len(char *mem, size_t size)
{
	char *end;
	// @attention The detection order of ws chars is important: space, tab, cr, and nl
	if ((end = memchr(mem, ' ', size)) ||
			(end = memchr(mem, '\t', size)) ||
			(end = memchr(mem, '\r', size)) ||
			(end = memchr(mem, '\n', size)) ||
			(end = memchr(mem, '\0', size))) {
		return (size_t)(end - mem);
	}
	return size;
}

double current_time(void){
    struct timeval time;
    gettimeofday( &time, NULL );
    double num;
    char *time_str;
    asprintf(&time_str, "%ld.%d", time.tv_sec, time.tv_usec);
    sscanf(time_str,"%lf",&num);
    free(time_str);
    return num;
}
/* vim: set noet ft=c: */
