/*-
 */

#include "privsep.h"

#include "sys.h"
#include "util.h"
#include "log.h"
#include "attrib.h"
#include "defaults.h"

#include <sys/types.h>
#include <sys/socket.h>
#include <sys/select.h>
#include <sys/wait.h>
#include <netinet/in.h>
#include <signal.h>
#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <libgen.h>
#include <fcntl.h>


/*
 * Privilege separation functionality.
 *
 * The server code has limitations on the internal functionality that can be
 * used, namely only those that are initialized before forking.
 */

/* maximal message sizes */
#define PRIVSEP_MAX_REQ_SIZE	512	/* arbitrary limit */
#define PRIVSEP_MAX_ANS_SIZE	(1+sizeof(int))
/* command byte */
#define PRIVSEP_REQ_CLOSE	0	/* closing command socket */
#define PRIVSEP_REQ_OPENFILE	1	/* open content log file */
#define PRIVSEP_REQ_OPENFILE_P	2	/* open content log file w/mkpath */
#define PRIVSEP_REQ_OPENSOCK	3	/* open socket and pass fd */
#define PRIVSEP_REQ_CERTFILE	4	/* open cert file in certgendir */
//#ifndef WITHOUT_USERAUTH
//#define PRIVSEP_REQ_UPDATE_ATIME	5	/* update ip,user atime */
//#endif /* !WITHOUT_USERAUTH */
/* response byte */
#define PRIVSEP_ANS_SUCCESS	0	/* success */
#define PRIVSEP_ANS_UNK_CMD	1	/* unknown command */
#define PRIVSEP_ANS_INVALID	2	/* invalid message */
#define PRIVSEP_ANS_DENIED	3	/* request denied */
#define PRIVSEP_ANS_SYS_ERR	4	/* system error; arg=errno */

/* Whether we short-circuit calls to privsep_client_* directly to
 * privsep_server_* within the client process, bypassing the privilege
 * separation mechanism; this is a performance optimization for use cases
 * where the user chooses performance over security, especially with options
 * that require privsep operations for each connection passing through.
 * In the current implementation, for consistency, we still fork normally, but
 * will not actually send any privsep requests to the parent process. */
static int privsep_fastpath;

/* communication with signal handler */
static volatile sig_atomic_t received_sighup;
static volatile sig_atomic_t received_sigint;
static volatile sig_atomic_t received_sigquit;
static volatile sig_atomic_t received_sigterm;
static volatile sig_atomic_t received_sigchld;
static volatile sig_atomic_t received_sigusr1;
/* write end of pipe used for unblocking select */
static volatile sig_atomic_t selfpipe_wrfd;

static void privsep_server_signal_handler(int sig)
{
    printf("--> privsep_server_signal_handler:%d\n",sig);
	int saved_errno;

	saved_errno = errno;

#ifdef DEBUG_PRIVSEP_SERVER
	log_dbg_printf("privsep_server_signal_handler\n");
#endif /* DEBUG_PRIVSEP_SERVER */

	switch (sig) {
	case SIGHUP:
		received_sighup = 1;
		break;
	case SIGINT:
		received_sigint = 1;
		break;
	case SIGQUIT:
		received_sigquit = 1;
		break;
	case SIGTERM:
		received_sigterm = 1;
		break;
	case SIGCHLD:
		received_sigchld = 1;
		break;
	case SIGUSR1:
		received_sigusr1 = 1;
		break;
	}
	if (selfpipe_wrfd != -1) {
		ssize_t n;

#ifdef DEBUG_PRIVSEP_SERVER
		log_dbg_printf("writing to selfpipe_wrfd %i\n", selfpipe_wrfd);
#endif /* DEBUG_PRIVSEP_SERVER */
		do {
			n = write(selfpipe_wrfd, "!", 1);
		} while (n == -1 && errno == EINTR);
		if (n == -1) {
			log_err_level_printf(LOG_CRIT, "Failed to write from signal handler: "
			               "%s (%i)\n", strerror(errno), errno);
			/* ignore error */
		}
#ifdef DEBUG_PRIVSEP_SERVER
	} else {
		log_dbg_printf("selfpipe_wrfd is %i - not writing\n", selfpipe_wrfd);
#endif /* DEBUG_PRIVSEP_SERVER */
	}
	errno = saved_errno;
}

static int WUNRES
privsep_server_openfile_verify(global_t *global, const char *fn, UNUSED int mkpath)
{
	/* Prefix must match one of the active log files that use privsep. */
	do {
		if (global->contentlog) {
			if (strstr(fn, global->contentlog_isspec
			               ? global->contentlog_basedir
			               : global->contentlog) == fn)
				break;
		}
		if (global->pcaplog) {
			if (strstr(fn, global->pcaplog_isspec
			               ? global->pcaplog_basedir
			               : global->pcaplog) == fn)
				break;
		}
		if (global->connectlog) {
			if (strstr(fn, global->connectlog) == fn)
				break;
		}
		if (global->masterkeylog) {
			if (strstr(fn, global->masterkeylog) == fn)
				break;
		}
		return -1;
	} while (0);

	/* Path must not contain dot-dot to prevent escaping the prefix. */
	if (strstr(fn, "/../"))
		return -1;

	return 0;
}

static int WUNRES
privsep_server_openfile(const char *fn, int mkpath)
{
	int fd, tmp;

	if (mkpath) {
		char *filedir, *fn2;

		fn2 = strdup(fn);
		if (!fn2) {
			tmp = errno;
			log_err_level_printf(LOG_CRIT, "Could not duplicate filname: %s (%i)\n",
			               strerror(errno), errno);
			errno = tmp;
			return -1;
		}
		filedir = dirname(fn2);
		if (!filedir) {
			tmp = errno;
			log_err_level_printf(LOG_CRIT, "Could not get dirname: %s (%i)\n",
			               strerror(errno), errno);
			free(fn2);
			errno = tmp;
			return -1;
		}
		if (sys_mkpath(filedir, DFLT_DIRMODE) == -1) {
			tmp = errno;
			log_err_level_printf(LOG_CRIT, "Could not create directory '%s': %s (%i)\n",
			               filedir, strerror(errno), errno);
			free(fn2);
			errno = tmp;
			return -1;
		}
		free(fn2);
	}

	fd = open(fn, O_RDWR|O_CREAT, DFLT_FILEMODE);
	if (fd == -1) {
		tmp = errno;
		log_err_level_printf(LOG_CRIT, "Failed to open '%s': %s (%i)\n",
		               fn, strerror(errno), errno);
		errno = tmp;
		return -1;
	}
	if (lseek(fd, 0, SEEK_END) == -1) {
		tmp = errno;
		log_err_level_printf(LOG_CRIT, "Failed to seek on '%s': %s (%i)\n",
		               fn, strerror(errno), errno);
		errno = tmp;
		return -1;
	}
	return fd;
}

static int WUNRES
privsep_server_opensock_verify(global_t *global, void *arg)
{
	/* This check is safe, because modifications of the spec in the child
	 * process do not affect the copy of the spec here in the parent. */
	for (proxyspec_t *spec = global->spec; spec; spec = spec->next) {
		if (spec == arg)
			return 0;
	}
	return 1;
}

static int WUNRES
privsep_server_opensock(const proxyspec_t *spec)
{
	evutil_socket_t fd;
	int on = 1;
	int rv;

	fd = socket(spec->listen_addr.ss_family, SOCK_STREAM, IPPROTO_TCP);
	if (fd == -1) {
		log_err_level_printf(LOG_CRIT, "Error from socket(): %s (%i)\n",
		               strerror(errno), errno);
		evutil_closesocket(fd);
		return -1;
	}

	rv = evutil_make_socket_nonblocking(fd);
	if (rv == -1) {
		log_err_level_printf(LOG_CRIT, "Error making socket nonblocking: %s (%i)\n",
		               strerror(errno), errno);
		evutil_closesocket(fd);
		return -1;
	}

	rv = setsockopt(fd, SOL_SOCKET, SO_KEEPALIVE, (void*)&on, sizeof(on));
	if (rv == -1) {
		log_err_level_printf(LOG_CRIT, "Error from setsockopt(SO_KEEPALIVE): %s (%i)\n",
		               strerror(errno), errno);
		evutil_closesocket(fd);
		return -1;
	}

	rv = evutil_make_listen_socket_reuseable(fd);
	if (rv == -1) {
		log_err_level_printf(LOG_CRIT, "Error from setsockopt(SO_REUSABLE): %s\n",
		               strerror(errno));
		evutil_closesocket(fd);
		return -1;
	}

//	if (spec->natsocket && (spec->natsocket(fd) == -1)) {
//		log_err_level_printf(LOG_CRIT, "Error from spec->natsocket()\n");
//		evutil_closesocket(fd);
//		return -1;
//	}

	rv = bind(fd, (struct sockaddr *)&spec->listen_addr,
	          spec->listen_addrlen);
	if (rv == -1) {
		log_err_level_printf(LOG_CRIT, "Error from bind(): %s\n", strerror(errno));
		evutil_closesocket(fd);
		return -1;
	}

	return fd;
}

static int WUNRES
privsep_server_certfile_verify(global_t *global, const char *fn)
{
	if (!global->certgendir)
		return -1;
	if (strstr(fn, global->certgendir) != fn || strstr(fn, "/../"))
		return -1;
	return 0;
}

static int WUNRES
privsep_server_certfile(const char *fn)
{
	int fd;

	fd = open(fn, O_WRONLY|O_CREAT|O_EXCL, DFLT_FILEMODE);
	if (fd == -1 && errno != EEXIST) {
		log_err_level_printf(LOG_CRIT, "Failed to open '%s': %s (%i)\n",
		               fn, strerror(errno), errno);
		return -1;
	}
	return fd;
}

//#ifndef WITHOUT_USERAUTH
//static int WUNRES
//privsep_server_update_atime(global_t *global, const userdbkeys_t *keys)
//{
//	time_t atime = time(NULL);
//	// @todo Do we really need to reset the stmt, as we always reset while returning?
//	sqlite3_reset(global->update_user_atime);
//	sqlite3_bind_int(global->update_user_atime, 1, atime);
//	sqlite3_bind_text(global->update_user_atime, 2, keys->ip, -1, NULL);
//	sqlite3_bind_text(global->update_user_atime, 3, keys->user, -1, NULL);
//	sqlite3_bind_text(global->update_user_atime, 4, keys->ether, -1, NULL);
//
//	int rc = sqlite3_step(global->update_user_atime);
//
//	// Do not retry in case we cannot acquire db file or database: SQLITE_BUSY or SQLITE_LOCKED respectively
//	// No need to waste resources, atime update is not so critical
//	if (rc == SQLITE_DONE) {
//		log_dbg_printf("privsep_server_update_atime: Updated atime of user %s=%lld\n", keys->user, (long long)atime);
//	} else {
//		log_err_printf("Error updating user atime: %s\n", sqlite3_errmsg(global->userdb));
//	}
//	sqlite3_reset(global->update_user_atime);
//	return 0;
//}
//#endif /* !WITHOUT_USERAUTH */

/*
 * Handle a single request on a readable server socket.
 * Returns 0 on success, 1 on EOF and -1 on error.
 */
static int WUNRES
privsep_server_handle_req(global_t *global, int srvsock)
{
	char req[PRIVSEP_MAX_REQ_SIZE];
	char ans[PRIVSEP_MAX_ANS_SIZE];
	ssize_t n;
	int mkpath = 0;

	if ((n = sys_recvmsgfd(srvsock, req, sizeof(req),
	                       NULL)) == -1) {
		if (errno == EPIPE || errno == ECONNRESET) {
			/* unfriendly EOF, leave server */
			return 1;
		}
		log_err_level_printf(LOG_CRIT, "Failed to receive msg: %s (%i)\n",
		               strerror(errno), errno);
		return -1;
	}
	if (n == 0) {
		/* EOF, leave server; will not happen for SOCK_DGRAM sockets */
		return 1;
	}
	log_dbg_printf("Received privsep req type %02x sz %zd on srvsock %i\n",
	               req[0], n, srvsock);
	switch (req[0]) {
	case PRIVSEP_REQ_CLOSE: {
		/* client indicates EOF through close message */
		return 1;
	}
	case PRIVSEP_REQ_OPENFILE_P:
		mkpath = 1;
		/* fall through */
	case PRIVSEP_REQ_OPENFILE: {
		char *fn;
		int fd;

		if (n < 2) {
			ans[0] = PRIVSEP_ANS_INVALID;
			if (sys_sendmsgfd(srvsock, ans, 1, -1) == -1) {
				log_err_level_printf(LOG_CRIT, "Sending message failed: %s (%i"
				               ")\n", strerror(errno), errno);
				return -1;
			}
		}
		if (!(fn = malloc(n))) {
			ans[0] = PRIVSEP_ANS_SYS_ERR;
			*((int*)&ans[1]) = errno;
			if (sys_sendmsgfd(srvsock, ans, 1 + sizeof(int),
			                  -1) == -1) {
				log_err_level_printf(LOG_CRIT, "Sending message failed: %s (%i"
				               ")\n", strerror(errno), errno);
				return -1;
			}
			return 0;
		}
		memcpy(fn, req + 1, n - 1);
		fn[n - 1] = '\0';
		if (privsep_server_openfile_verify(global, fn, mkpath) == -1) {
			free(fn);
			ans[0] = PRIVSEP_ANS_DENIED;
			if (sys_sendmsgfd(srvsock, ans, 1, -1) == -1) {
				log_err_level_printf(LOG_CRIT, "Sending message failed: %s (%i"
				               ")\n", strerror(errno), errno);
				return -1;
			}
			return 0;
		}
		if ((fd = privsep_server_openfile(fn, mkpath)) == -1) {
			free(fn);
			ans[0] = PRIVSEP_ANS_SYS_ERR;
			*((int*)&ans[1]) = errno;
			if (sys_sendmsgfd(srvsock, ans, 1 + sizeof(int),
			                  -1) == -1) {
				log_err_level_printf(LOG_CRIT, "Sending message failed: %s (%i"
				               ")\n", strerror(errno), errno);
				return -1;
			}
			return 0;
		} else {
			free(fn);
			ans[0] = PRIVSEP_ANS_SUCCESS;
			if (sys_sendmsgfd(srvsock, ans, 1, fd) == -1) {
				close(fd);
				log_err_level_printf(LOG_CRIT, "Sending message failed: %s (%i"
				               ")\n", strerror(errno), errno);
				return -1;
			}
			close(fd);
			return 0;
		}
		/* not reached */
		break;
	}
	case PRIVSEP_REQ_OPENSOCK: {
		proxyspec_t *arg;
		int s;

		if (n != sizeof(char) + sizeof(arg)) {
			ans[0] = PRIVSEP_ANS_INVALID;
			if (sys_sendmsgfd(srvsock, ans, 1, -1) == -1) {
				log_err_level_printf(LOG_CRIT, "Sending message failed: %s (%i"
				               ")\n", strerror(errno), errno);
				return -1;
			}
			return 0;
		}
		arg = *(proxyspec_t**)(&req[1]);
		if (privsep_server_opensock_verify(global, arg) == -1) {
			ans[0] = PRIVSEP_ANS_DENIED;
			if (sys_sendmsgfd(srvsock, ans, 1, -1) == -1) {
				log_err_level_printf(LOG_CRIT, "Sending message failed: %s (%i"
				               ")\n", strerror(errno), errno);
				return -1;
			}
			return 0;
		}
		if ((s = privsep_server_opensock(arg)) == -1) {
			ans[0] = PRIVSEP_ANS_SYS_ERR;
			*((int*)&ans[1]) = errno;
			if (sys_sendmsgfd(srvsock, ans, 1 + sizeof(int),
			                  -1) == -1) {
				log_err_level_printf(LOG_CRIT, "Sending message failed: %s (%i"
				               ")\n", strerror(errno), errno);
				return -1;
			}
			return 0;
		} else {
			ans[0] = PRIVSEP_ANS_SUCCESS;
			if (sys_sendmsgfd(srvsock, ans, 1, s) == -1) {
				evutil_closesocket(s);
				log_err_level_printf(LOG_CRIT, "Sending message failed: %s (%i"
				               ")\n", strerror(errno), errno);
				return -1;
			}
			evutil_closesocket(s);
			return 0;
		}
		/* not reached */
		break;
	}
//#ifndef WITHOUT_USERAUTH
//	case PRIVSEP_REQ_UPDATE_ATIME: {
//		userdbkeys_t arg;
//
//		if (n != sizeof(char) + sizeof(userdbkeys_t)) {
//			ans[0] = PRIVSEP_ANS_INVALID;
//			if (sys_sendmsgfd(srvsock, ans, 1, -1) == -1) {
//				log_err_level_printf(LOG_CRIT, "Sending message failed: %s (%i"
//				               ")\n", strerror(errno), errno);
//				return -1;
//			}
//			return 0;
//		}
//		arg = *(userdbkeys_t*)(&req[1]);
//		if (privsep_server_update_atime(global, &arg) == -1) {
//			ans[0] = PRIVSEP_ANS_SYS_ERR;
//			*((int*)&ans[1]) = errno;
//			if (sys_sendmsgfd(srvsock, ans, 1 + sizeof(int),
//			                  -1) == -1) {
//				log_err_level_printf(LOG_CRIT, "Sending message failed: %s (%i"
//				               ")\n", strerror(errno), errno);
//				return -1;
//			}
//			return 0;
//		} else {
//			ans[0] = PRIVSEP_ANS_SUCCESS;
//			// @attention Pass -1 as the 4th param, otherwise passing 0 opens an stdin (fd 0), causing fd leak
//			if (sys_sendmsgfd(srvsock, ans, 1, -1) == -1) {
//				log_err_level_printf(LOG_CRIT, "Sending message failed: %s (%i"
//				               ")\n", strerror(errno), errno);
//				return -1;
//			}
//			return 0;
//		}
//		/* not reached */
//		break;
//	}
//#endif /* !WITHOUT_USERAUTH */
	case PRIVSEP_REQ_CERTFILE: {
		char *fn;
		int fd;

		if (n < 2) {
			ans[0] = PRIVSEP_ANS_INVALID;
			if (sys_sendmsgfd(srvsock, ans, 1, -1) == -1) {
				log_err_level_printf(LOG_CRIT, "Sending message failed: %s (%i"
				               ")\n", strerror(errno), errno);
				return -1;
			}
		}
		if (!(fn = malloc(n))) {
			ans[0] = PRIVSEP_ANS_SYS_ERR;
			*((int*)&ans[1]) = errno;
			if (sys_sendmsgfd(srvsock, ans, 1 + sizeof(int),
			                  -1) == -1) {
				log_err_level_printf(LOG_CRIT, "Sending message failed: %s (%i"
				               ")\n", strerror(errno), errno);
				return -1;
			}
			return 0;
		}
		memcpy(fn, req + 1, n - 1);
		fn[n - 1] = '\0';
		if (privsep_server_certfile_verify(global, fn) == -1) {
			free(fn);
			ans[0] = PRIVSEP_ANS_DENIED;
			if (sys_sendmsgfd(srvsock, ans, 1, -1) == -1) {
				log_err_level_printf(LOG_CRIT, "Sending message failed: %s (%i"
				               ")\n", strerror(errno), errno);
				return -1;
			}
			return 0;
		}
		if ((fd = privsep_server_certfile(fn)) == -1) {
			free(fn);
			ans[0] = PRIVSEP_ANS_SYS_ERR;
			*((int*)&ans[1]) = errno;
			if (sys_sendmsgfd(srvsock, ans, 1 + sizeof(int),
			                  -1) == -1) {
				log_err_level_printf(LOG_CRIT, "Sending message failed: %s (%i"
				               ")\n", strerror(errno), errno);
				return -1;
			}
			return 0;
		} else {
			free(fn);
			ans[0] = PRIVSEP_ANS_SUCCESS;
			if (sys_sendmsgfd(srvsock, ans, 1, fd) == -1) {
				close(fd);
				log_err_level_printf(LOG_CRIT, "Sending message failed: %s (%i"
				               ")\n", strerror(errno), errno);
				return -1;
			}
			close(fd);
			return 0;
		}
		/* not reached */
		break;
	}
	default:
		ans[0] = PRIVSEP_ANS_UNK_CMD;
		if (sys_sendmsgfd(srvsock, ans, 1, -1) == -1) {
			log_err_level_printf(LOG_CRIT, "Sending message failed: %s (%i"
			               ")\n", strerror(errno), errno);
			return -1;
		}
	}
	return 0;
}

/*
 * Privilege separation server (main privileged monitor loop)
 *
 * sigpipe is the self-pipe trick pipe used for communicating signals to the main event loop and break out of select() without race conditions.
 * srvsock[] is a dynamic array of connected privsep server sockets to serve.
 * Caller is responsible for freeing memory after returning, if necessary.
 * childpid is the pid of the child process to forward signals to.
 Sigpipe是一个自管道技巧管道，用于向主事件循环传递信号，并在没有竞争条件的情况下打破select()。
 Srvsock[]是一个要服务的privsep服务器套接字的动态数组。
 调用者负责在返回后释放内存(如果需要)。
 Childpid是要转发信号的子进程的pid。
 *
 * Returns 0 on a successful clean exit and -1 on errors.
 */
static int
privsep_server(global_t *global, int sigpipe, int srvsock[], size_t nsrvsock,
               pid_t childpid)
{
	int srveof[nsrvsock];
	size_t i = 0;

	for (i = 0; i < nsrvsock; i++) {
		srveof[i] = 0;
	}

	for (;;) {
		fd_set readfds;
		int maxfd, rv;

#ifdef DEBUG_PRIVSEP_SERVER
		log_dbg_printf("privsep_server select()\n");
#endif /* DEBUG_PRIVSEP_SERVER */
		do {
			FD_ZERO(&readfds);
			FD_SET(sigpipe, &readfds);
			maxfd = sigpipe;
			for (i = 0; i < nsrvsock; i++) {
				if (!srveof[i]) {
					FD_SET(srvsock[i], &readfds);
					maxfd = util_max(maxfd, srvsock[i]);
				}
			}
			rv = select(maxfd + 1, &readfds, NULL, NULL, NULL);
#ifdef DEBUG_PRIVSEP_SERVER
			log_dbg_printf("privsep_server woke up (1)\n");
#endif /* DEBUG_PRIVSEP_SERVER */
		} while (rv == -1 && errno == EINTR);
		if (rv == -1) {
			log_err_level_printf(LOG_CRIT, "select() failed: %s (%i)\n",
			               strerror(errno), errno);
			return -1;
		}
#ifdef DEBUG_PRIVSEP_SERVER
		log_dbg_printf("privsep_server woke up (2)\n");
#endif /* DEBUG_PRIVSEP_SERVER */

		if (FD_ISSET(sigpipe, &readfds)) {
			char buf[16];
			ssize_t n;
			/* first drain the signal pipe, then deal with
			 * all the individual signal flags */
			n = read(sigpipe, buf, sizeof(buf));
			if (n == -1) {
				log_err_level_printf(LOG_CRIT, "read(sigpipe) failed:"
				               " %s (%i)\n",
				               strerror(errno), errno);
				return -1;
			}
			if (received_sigquit) {
				if (kill(childpid, SIGQUIT) == -1) {
					log_err_level_printf(LOG_CRIT, "kill(%i,SIGQUIT) "
					               "failed: %s (%i)\n",
					               childpid,
					               strerror(errno), errno);
				}
				received_sigquit = 0;
			}
			if (received_sigterm) {
				if (kill(childpid, SIGTERM) == -1) {
					log_err_level_printf(LOG_CRIT, "kill(%i,SIGTERM) "
					               "failed: %s (%i)\n",
					               childpid,
					               strerror(errno), errno);
				}
				received_sigterm = 0;
			}
			if (received_sighup) {
				if (kill(childpid, SIGHUP) == -1) {
					log_err_level_printf(LOG_CRIT, "kill(%i,SIGHUP) "
					               "failed: %s (%i)\n",
					               childpid,
					               strerror(errno), errno);
				}
				received_sighup = 0;
			}
			if (received_sigusr1) {
				if (kill(childpid, SIGUSR1) == -1) {
					log_err_level_printf(LOG_CRIT, "kill(%i,SIGUSR1) "
					               "failed: %s (%i)\n",
					               childpid,
					               strerror(errno), errno);
				}
				received_sigusr1 = 0;
			}
			if (received_sigint) {
				/* if we don't detach from the TTY, the
				 * child process receives SIGINT directly */
				if (global->detach) {
					if (kill(childpid, SIGINT) == -1) {
						log_err_level_printf(LOG_CRIT, "kill(%i,SIGINT"
						               ") failed: "
						               "%s (%i)\n",
						               childpid,
						               strerror(errno),
						               errno);
					}
				}
				received_sigint = 0;
			}
			if (received_sigchld) {
				/* break the loop; because we are using
				 * SOCKET_DGRAM we don't get EOF conditions
				 * on the disconnected socket ends here
				 * unless we attempt to write or read, so
				 * we depend on SIGCHLD to notify us of
				 * our child erroring out or crashing */
				break;
			}
		}

		for (i = 0; i < nsrvsock; i++) {
			if (FD_ISSET(srvsock[i], &readfds)) {
				int rv = privsep_server_handle_req(global,
				                                   srvsock[i]);
				if (rv == -1) {
					log_err_level_printf(LOG_CRIT, "Failed to handle "
					               "privsep req "
					               "on srvsock %i\n",
					               srvsock[i]);
					return -1;
				}
				if (rv == 1) {
#ifdef DEBUG_PRIVSEP_SERVER
					log_dbg_printf("srveof[%zu]=1\n", i);
#endif /* DEBUG_PRIVSEP_SERVER */
					srveof[i] = 1;
				}
			}
		}

		/*
		 * We cannot exit as long as we need the signal handling,which is as long as the child process is running.
		 * The only way out of here is receiving SIGCHLD.
		 */
	}

	return 0;
}

int
privsep_client_openfile(int clisock, const char *fn, int mkpath)
{
	char ans[PRIVSEP_MAX_ANS_SIZE];
	char req[1 + strlen(fn)];
	int fd = -1;
	ssize_t n;

	if (privsep_fastpath)
		return privsep_server_openfile(fn, mkpath);

	req[0] = mkpath ? PRIVSEP_REQ_OPENFILE_P : PRIVSEP_REQ_OPENFILE;
	memcpy(req + 1, fn, sizeof(req) - 1);

	if (sys_sendmsgfd(clisock, req, sizeof(req), -1) == -1) {
		return -1;
	}

	if ((n = sys_recvmsgfd(clisock, ans, sizeof(ans), &fd)) == -1) {
		return -1;
	}

	if (n < 1) {
		errno = EINVAL;
		return -1;
	}

	switch (ans[0]) {
	case PRIVSEP_ANS_SUCCESS:
		break;
	case PRIVSEP_ANS_DENIED:
		errno = EACCES;
		return -1;
	case PRIVSEP_ANS_SYS_ERR:
		if (n < (ssize_t)(1 + sizeof(int))) {
			errno = EINVAL;
			return -1;
		}
		errno = *((int*)&ans[1]);
		return -1;
	case PRIVSEP_ANS_UNK_CMD:
	case PRIVSEP_ANS_INVALID:
	default:
		errno = EINVAL;
		return -1;
	}

	return fd;
}

int
privsep_client_opensock(int clisock, const proxyspec_t *spec)
{
	char ans[PRIVSEP_MAX_ANS_SIZE];
	char req[1 + sizeof(spec)];
	int fd = -1;
	ssize_t n;

	if (privsep_fastpath)
		return privsep_server_opensock(spec);

	req[0] = PRIVSEP_REQ_OPENSOCK;
	*((const proxyspec_t **)&req[1]) = spec;

	if (sys_sendmsgfd(clisock, req, sizeof(req), -1) == -1) {
		return -1;
	}

	if ((n = sys_recvmsgfd(clisock, ans, sizeof(ans), &fd)) == -1) {
		return -1;
	}

	if (n < 1) {
		errno = EINVAL;
		return -1;
	}

	switch (ans[0]) {
	case PRIVSEP_ANS_SUCCESS:
		break;
	case PRIVSEP_ANS_DENIED:
		errno = EACCES;
		return -1;
	case PRIVSEP_ANS_SYS_ERR:
		if (n < (ssize_t)(1 + sizeof(int))) {
			errno = EINVAL;
			return -1;
		}
		errno = *((int*)&ans[1]);
		return -1;
	case PRIVSEP_ANS_UNK_CMD:
	case PRIVSEP_ANS_INVALID:
	default:
		errno = EINVAL;
		return -1;
	}

	return fd;
}

int
privsep_client_certfile(int clisock, const char *fn)
{
	char ans[PRIVSEP_MAX_ANS_SIZE];
	char req[1 + strlen(fn)];
	int fd = -1;
	ssize_t n;

	if (privsep_fastpath)
		return privsep_server_certfile(fn);

	req[0] = PRIVSEP_REQ_CERTFILE;
	memcpy(req + 1, fn, sizeof(req) - 1);

	if (sys_sendmsgfd(clisock, req, sizeof(req), -1) == -1) {
		return -1;
	}

	if ((n = sys_recvmsgfd(clisock, ans, sizeof(ans), &fd)) == -1) {
		return -1;
	}

	if (n < 1) {
		errno = EINVAL;
		return -1;
	}

	switch (ans[0]) {
	case PRIVSEP_ANS_SUCCESS:
		break;
	case PRIVSEP_ANS_DENIED:
		errno = EACCES;
		return -1;
	case PRIVSEP_ANS_SYS_ERR:
		if (n < (ssize_t)(1 + sizeof(int))) {
			errno = EINVAL;
			return -1;
		}
		errno = *((int*)&ans[1]);
		return -1;
	case PRIVSEP_ANS_UNK_CMD:
	case PRIVSEP_ANS_INVALID:
	default:
		errno = EINVAL;
		return -1;
	}

	return fd;
}

int
privsep_client_close(int clisock)
{
	char req[1];

	req[0] = PRIVSEP_REQ_CLOSE;

	if (sys_sendmsgfd(clisock, req, sizeof(req), -1) == -1) {
		close(clisock);
		return -1;
	}

	close(clisock);
	return 0;
}

//#ifndef WITHOUT_USERAUTH
//int
//privsep_client_update_atime(int clisock, const userdbkeys_t *keys)
//{
//	char ans[PRIVSEP_MAX_ANS_SIZE];
//	char req[1 + sizeof(userdbkeys_t)];
//	ssize_t n;
//
//	req[0] = PRIVSEP_REQ_UPDATE_ATIME;
//	// @attention Do not typecast, but memcpy
//	//*((const userdbkeys_t **)&req[1]) = keys;
//	memcpy(req + 1, keys, sizeof(req) - 1);
//
//	if (sys_sendmsgfd(clisock, req, sizeof(req), -1) == -1) {
//		return -1;
//	}
//
//	// @attention Pass NULL as the 4th param, otherwise other privsep calls cannot get the fds they request
//	if ((n = sys_recvmsgfd(clisock, ans, sizeof(ans), NULL)) == -1) {
//		return -1;
//	}
//
//	if (n < 1) {
//		errno = EINVAL;
//		return -1;
//	}
//
//	switch (ans[0]) {
//	case PRIVSEP_ANS_SUCCESS:
//		break;
//	case PRIVSEP_ANS_DENIED:
//		errno = EACCES;
//		return -1;
//	case PRIVSEP_ANS_SYS_ERR:
//		if (n < (ssize_t)(1 + sizeof(int))) {
//			errno = EINVAL;
//			return -1;
//		}
//		errno = *((int*)&ans[1]);
//		return -1;
//	case PRIVSEP_ANS_UNK_CMD:
//	case PRIVSEP_ANS_INVALID:
//	default:
//		errno = EINVAL;
//		return -1;
//	}
//	// Does not return an fd
//	return 0;
//}
//#endif /* !WITHOUT_USERAUTH */

/*
 * Fork and set up privilege separated monitor process.Fork并建立特权分离的监控进程。
 * Returns -1 on error before forking, 1 as parent, or 0 as child.
 * The array of clisock's will get filled with nclisock privsep client sockets only for the child; on error and in the parent process it will not be touched.
 */
int
privsep_fork(global_t *global, int clisock[], size_t nclisock, int *parent_rv)
{
	int selfpipev[2]; /* self-pipe trick: signal handler -> select */
	int chldpipev[2]; /* el cheapo interprocess sync early after fork */
	int sockcliv[nclisock][2];
//	pid_t pid;

	if (!global->dropuser) {
		log_dbg_printf("Privsep fastpath enabled\n");
		privsep_fastpath = 1;
	} else {
		log_dbg_printf("Privsep fastpath disabled\n");
		privsep_fastpath = 0;
	}

	received_sigquit = 0;
	received_sighup = 0;
	received_sigint = 0;
	received_sigchld = 0;
	received_sigusr1 = 0;

	if (pipe(selfpipev) == -1) {
		log_err_level_printf(LOG_CRIT, "Failed to create self-pipe: %s (%i)\n",
		               strerror(errno), errno);
		return -1;
	}
	log_dbg_printf("Created self-pipe [r=%i,w=%i]\n",
	               selfpipev[0], selfpipev[1]);

	if (pipe(chldpipev) == -1) {
		log_err_level_printf(LOG_CRIT, "Failed to create chld-pipe: %s (%i)\n",
		               strerror(errno), errno);
		return -1;
	}
	log_dbg_printf("Created chld-pipe [r=%i,w=%i]\n",
	               chldpipev[0], chldpipev[1]);

	for (size_t i = 0; i < nclisock; i++) {
		if (socketpair(AF_UNIX, SOCK_DGRAM, 0, sockcliv[i]) == -1) {
			log_err_level_printf(LOG_CRIT, "Failed to create socket pair %zu: "
			               "%s (%i)\n", i, strerror(errno), errno);
			return -1;
		}
		log_dbg_printf("Created socketpair %zu [p=%i,c=%i]\n",
		               i, sockcliv[i][0], sockcliv[i][1]);
	}

	log_dbg_printf("Privsep parent pid %i\n", getpid());
//	pid = fork();
//	if (pid == -1) {
//		log_err_level_printf(LOG_CRIT, "Failed to fork: %s (%i)\n",
//		               strerror(errno), errno);
//		close(selfpipev[0]);
//		close(selfpipev[1]);
//		close(chldpipev[0]);
//		close(chldpipev[1]);
//		for (size_t i = 0; i < nclisock; i++) {
//			close(sockcliv[i][0]);
//			close(sockcliv[i][1]);
//		}
//		return -1;
//	} else if (pid == 0) {
		/* child 子进程 */
		close(selfpipev[0]);
		close(selfpipev[1]);
		for (size_t i = 0; i < nclisock; i++)
			close(sockcliv[i][0]);
		/* wait until parent has installed signal handlers, intentionally ignoring errors */
		char buf[1];
		ssize_t n;
		close(chldpipev[1]);
		do {
			n = read(chldpipev[0], buf, sizeof(buf));
		} while (n == -1 && errno == EINTR);
		close(chldpipev[0]);
		/* return the privsep client sockets */
		for (size_t i = 0; i < nclisock; i++)
			clisock[i] = sockcliv[i][1];
//		return 0;
//	}
//	/* parent */
//	for (size_t i = 0; i < nclisock; i++)
//		close(sockcliv[i][1]);
//	selfpipe_wrfd = selfpipev[1];
//
//	/* close file descriptors opened by preinit's only needed in client; we still call the preinit's before forking in order to provide better user feedback and less privsep complexity
//       关闭由preinit打开的文件描述符只需要在客户端;我们仍然在fork之前调用preinit，以提供更好的用户反馈和更少的privsep复杂性
//     */
////	nat_preinit_undo();
//	log_preinit_undo();
//
	/* If the child exits before the parent installs the signal handler here, we have a race condition; this is solved by the client blocking on the reading end of a pipe (chldpipev[0]).
       如果子进程在父进程安装信号处理程序之前退出，则有一个竞态条件;这是通过客户端阻塞管道的读取端(chldpipev[0])来解决的。
     */
//	if (signal(SIGHUP, privsep_server_signal_handler) == SIG_ERR) {
//		log_err_level_printf(LOG_CRIT, "Failed to install SIGHUP handler: %s (%i)\n",
//		               strerror(errno), errno);
//		return -1;
//	}
//	if (signal(SIGINT, privsep_server_signal_handler) == SIG_ERR) {
//		log_err_level_printf(LOG_CRIT, "Failed to install SIGINT handler: %s (%i)\n",
//		               strerror(errno), errno);
//		return -1;
//	}
//	if (signal(SIGTERM, privsep_server_signal_handler) == SIG_ERR) {
//		log_err_level_printf(LOG_CRIT, "Failed to install SIGTERM handler: %s (%i)\n",
//		               strerror(errno), errno);
//		return -1;
//	}
//	if (signal(SIGQUIT, privsep_server_signal_handler) == SIG_ERR) {
//		log_err_level_printf(LOG_CRIT, "Failed to install SIGQUIT handler: %s (%i)\n",
//		               strerror(errno), errno);
//		return -1;
//	}
//	if (signal(SIGUSR1, privsep_server_signal_handler) == SIG_ERR) {
//		log_err_level_printf(LOG_CRIT, "Failed to install SIGUSR1 handler: %s (%i)\n",
//		               strerror(errno), errno);
//		return -1;
//	}
//	if (signal(SIGCHLD, privsep_server_signal_handler) == SIG_ERR) {
//		log_err_level_printf(LOG_CRIT, "Failed to install SIGCHLD handler: %s (%i)\n",
//		               strerror(errno), errno);
//		return -1;
//	}
//
//	/* unblock the child */
//	close(chldpipev[0]);
//	close(chldpipev[1]);
//
//	int socksrv[nclisock];
//	for (size_t i = 0; i < nclisock; i++)
//		socksrv[i] = sockcliv[i][0];
//	if (privsep_server(global, selfpipev[0], socksrv, nclisock, pid) == -1) {
//		log_err_level_printf(LOG_CRIT, "Privsep server failed: %s (%i)\n",
//		               strerror(errno), errno);
//		/* fall through */
//	}
//#ifdef DEBUG_PRIVSEP_SERVER
//	log_dbg_printf("privsep_server exited\n");
//#endif /* DEBUG_PRIVSEP_SERVER */
//
//	for (size_t i = 0; i < nclisock; i++)
//		close(sockcliv[i][0]);
//	selfpipe_wrfd = -1; /* tell signal handler not to write anymore */
//	close(selfpipev[0]);
//	close(selfpipev[1]);
//
//	int status;
//	pid_t wpid;
//	wpid = wait(&status);
//	if (wpid != pid) {
//		/* should never happen, warn if it does anyway */
//		log_err_printf("Child pid %lld != expected %lld from wait(2)\n",
//		               (long long)wpid, (long long)pid);
//	}
//	if (WIFEXITED(status)) {
//		if (WEXITSTATUS(status) != 0) {
//			log_err_level_printf(LOG_CRIT, "Child pid %lld exited with status %d\n",
//			               (long long)wpid, WEXITSTATUS(status));
//		} else {
//			log_dbg_printf("Child pid %lld exited with status %d\n",
//			               (long long)wpid, WEXITSTATUS(status));
//		}
//		*parent_rv = WEXITSTATUS(status);
//	} else if (WIFSIGNALED(status)) {
//		log_err_level_printf(LOG_CRIT, "Child pid %lld killed by signal %d\n",
//		               (long long)wpid, WTERMSIG(status));
//		*parent_rv = 128 + WTERMSIG(status);
//	} else {
//		/* can only happen with WUNTRACED option or active tracing */
//		log_err_level_printf(LOG_CRIT, "Child pid %lld neither exited nor killed\n",
//		               (long long)wpid);
//	}
//
	return 0;
}

/* vim: set noet ft=c: */



