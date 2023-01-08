/*-
 */

#ifndef PRIVSEP_H
#define PRIVSEP_H

#include "attrib.h"
#include "opts.h"

int privsep_fork(global_t *, int[], size_t, int *);

int privsep_client_openfile(int, const char *, int);
int privsep_client_opensock(int, const proxyspec_t *spec);
int privsep_client_certfile(int, const char *);
int privsep_client_close(int);
//#ifndef WITHOUT_USERAUTH
//int privsep_client_update_atime(int, const userdbkeys_t *);
//#endif /* !WITHOUT_USERAUTH */
#endif /* !PRIVSEP_H */

/* vim: set noet ft=c: */
