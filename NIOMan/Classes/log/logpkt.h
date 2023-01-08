/*-
 */

#ifndef LOGPKT_H
#define LOGPKT_H

#include "attrib.h"

#include <sys/socket.h>
#include <stdint.h>
#include <time.h>

#define libnet_t void
#define ETHER_ADDR_LEN 6

typedef struct {
	libnet_t *libnet;
	uint8_t src_ether[ETHER_ADDR_LEN];
	uint8_t dst_ether[ETHER_ADDR_LEN];
	struct sockaddr_storage src_addr;
	struct sockaddr_storage dst_addr;
	uint32_t src_seq;
	uint32_t dst_seq;
	size_t mss;
} logpkt_ctx_t;

#define LOGPKT_REQUEST  0
#define LOGPKT_RESPONSE 1

int logpkt_pcap_open_fd(int fd) WUNRES;
void logpkt_ctx_init(logpkt_ctx_t *, libnet_t *, size_t,
                     const uint8_t *, const uint8_t *,
                     const struct sockaddr *, socklen_t,
                     const struct sockaddr *, socklen_t);
int logpkt_write_payload(logpkt_ctx_t *, int, int,
                         const unsigned char *, size_t) WUNRES;
int logpkt_write_close(logpkt_ctx_t *, int, int);
int logpkt_ether_lookup(libnet_t *, uint8_t *, uint8_t *,
                        const char *, const char *) WUNRES;

#endif /* !LOGPKT_H */
