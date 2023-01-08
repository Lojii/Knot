/*-
 */

#ifndef PROC_H
#define PROC_H

#include "attrib.h"

#include <sys/types.h>
#include <sys/socket.h>

#include <event2/util.h>

#if defined(HAVE_DARWIN_LIBPROC) || defined(__FreeBSD__)
#define HAVE_LOCAL_PROCINFO
#endif

#ifdef HAVE_DARWIN_LIBPROC
#ifndef LOCAL_PROCINFO_STR
#define LOCAL_PROCINFO_STR "Darwin libproc"
#define proc_pid_for_addr(a,b,c)	proc_darwin_pid_for_addr(a,b,c)
#define proc_get_info(a,b,c,d)		proc_darwin_get_info(a,b,c,d)
#endif /* LOCAL_PROCINFO_STR */
int proc_darwin_pid_for_addr(pid_t *, struct sockaddr *, socklen_t) WUNRES NONNULL(1,2);
int proc_darwin_get_info(pid_t, char **, uid_t *, gid_t *) WUNRES NONNULL(2,3,4);
#endif /* HAVE_DARWIN_LIBPROC */

#ifdef __FreeBSD__
#ifndef LOCAL_PROCINFO_STR
#define LOCAL_PROCINFO_STR "FreeBSD sysctl"
#define proc_pid_for_addr(a,b,c)	proc_freebsd_pid_for_addr(a,b,c)
#define proc_get_info(a,b,c,d)		proc_freebsd_get_info(a,b,c,d)
#endif /* LOCAL_PROCINFO_STR */
int proc_freebsd_pid_for_addr(pid_t *, struct sockaddr *, socklen_t) WUNRES NONNULL(1,2);
int proc_freebsd_get_info(pid_t, char **, uid_t *, gid_t *) WUNRES NONNULL(2,3,4);
#endif /* __FreeBSD__ */

#endif /* !PROC_H */

/* vim: set noet ft=c: */
