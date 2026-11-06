#pragma once
#include <stdatomic.h>
#include <stdint.h>

enum {
    DMND_RING = 32,
    DMND_FIRST_EVENTFD = 32,
    DMND_FIRST_POLL_EFD = 32,
    DMND_SOCKET = 1,
    DMND_EVENTFD = 2,
    DMND_SSL = 3,
    DMND_NIFM = 4,
    DMND_SF = 5,
};
enum {
    DMND_OP_SOCKET = 1, DMND_OP_CLOSE, DMND_OP_BIND, DMND_OP_CONNECT, DMND_OP_LISTEN,
    DMND_OP_ACCEPT, DMND_OP_SHUTDOWN, DMND_OP_NAME, DMND_OP_FCNTL, DMND_OP_SOCKOPT,
    DMND_OP_RECV, DMND_OP_SEND, DMND_OP_POLL, DMND_OP_SELECT, DMND_OP_EVENTFD,
    DMND_OP_EVENTFD_RW, DMND_OP_READ, DMND_OP_WRITE, DMND_OP_ERRNO,
    DMND_OP_SSL_INIT, DMND_OP_SSL_CTX, DMND_OP_SSL_CONN, DMND_OP_SSL_HS, DMND_OP_SSL_IO,
    DMND_OP_NIFM_INIT, DMND_OP_NIFM_REQ, DMND_OP_NIFM_AVAIL, DMND_OP_NIFM_IP, DMND_OP_SF_CONNECT,
};

typedef struct {
    _Atomic uint32_t seq;      /* odd=writing, even=stable, 0=empty */
    uint16_t class_id, op;
    int32_t a0, a1, result;
    int16_t err, flags;
    uint32_t tid;
    uint64_t tick, lr;
    uint64_t name;             /* first 8 bytes of service name for SF_CONNECT */
} dmnd_entry;

typedef struct {
    _Atomic uint32_t idx;
    _Atomic uint64_t idle_polls;
    _Atomic uint32_t first_eventfd;
    _Atomic uint32_t first_poll_efd;
    _Atomic uint32_t net_mode_logged;
    _Atomic uint32_t nifm_logged;
    dmnd_entry ring[DMND_RING];
} dmnd_state;

extern dmnd_state g_dmnd;
void dmnd_record(uint16_t class_id, uint16_t op, int32_t a0, int32_t a1, int32_t result, int err, uint16_t flags, void *lr, uint64_t name);
void dmnd_dump(void); /* abort path: no locks, copies to stack */
void dmnd_log_net_mode_once(int mode);
void dmnd_log_nifm_once(int available);
int dmnd_poll_has_eventfd(const void *fds, uint64_t count, int nfds, const void *r, const void *w, const void *e);
