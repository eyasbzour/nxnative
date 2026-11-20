#include "hle_net_diag.h"
#include "dm.h"
#include "net_socket.h"
#include <pthread.h>
#include <stdio.h>
#include <time.h>

dmnd_state g_dmnd;

static uint64_t dmnd_tick(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000000ull + (uint64_t)ts.tv_nsec;
}

static uint32_t dmnd_tid(void) {
    return (uint32_t)pthread_mach_thread_np(pthread_self());
}

void dmnd_record(uint16_t class_id, uint16_t op, int32_t a0, int32_t a1, int32_t result, int err, uint16_t flags, void *lr, uint64_t name) {
    uint32_t i = atomic_fetch_add_explicit(&g_dmnd.idx, 1, memory_order_relaxed) & (DMND_RING - 1);
    dmnd_entry *e = &g_dmnd.ring[i];
    atomic_store_explicit(&e->seq, atomic_load_explicit(&e->seq, memory_order_relaxed) + 1, memory_order_relaxed); /* odd */
    e->class_id = class_id; e->op = op;
    e->a0 = a0; e->a1 = a1; e->result = result;
    e->err = (int16_t)err; e->flags = flags;
    e->tid = dmnd_tid();
    e->tick = dmnd_tick();
    e->lr = (uint64_t)(uintptr_t)lr;
    e->name = name;
    atomic_store_explicit(&e->seq, atomic_load_explicit(&e->seq, memory_order_relaxed) + 1, memory_order_release); /* even */
}

static const char *dmnd_class(uint16_t c) {
    switch (c) {
        case DMND_SOCKET: return "socket";
        case DMND_EVENTFD: return "eventfd";
        case DMND_SSL: return "ssl";
        case DMND_NIFM: return "nifm";
        case DMND_SF: return "sf";
        default: return "?";
    }
}

void dmnd_dump(void) {
    dmnd_entry snap[DMND_RING];
    for (int i = 0; i < DMND_RING; i++) {
        dmnd_entry *e = &g_dmnd.ring[i];
        for (int tries = 0; tries < 8; tries++) {
            uint32_t s1 = atomic_load_explicit(&e->seq, memory_order_acquire);
            snap[i] = *e;
            atomic_thread_fence(memory_order_acquire);
            uint32_t s2 = atomic_load_explicit(&e->seq, memory_order_acquire);
            if ((s1 & 1) == 0 && s1 == s2) break;
            if (tries == 7) snap[i].seq = 1;
        }
    }
    uint64_t idle = atomic_load_explicit(&g_dmnd.idle_polls, memory_order_relaxed);
    LOG("net-diag: last %d HLE calls (idle_polls=%llu, eventfd_calls=%u, poll_select_eventfd=%u)",
        DMND_RING, (unsigned long long)idle,
        atomic_load_explicit(&g_dmnd.first_eventfd, memory_order_relaxed),
        atomic_load_explicit(&g_dmnd.first_poll_efd, memory_order_relaxed));
    for (int i = 0; i < DMND_RING; i++) {
        dmnd_entry *e = &snap[i];
        if (!e->seq || (e->seq & 1)) continue;
        char svc[9]; *(uint64_t *)svc = e->name; svc[8] = 0;
        if (e->class_id == DMND_SF && e->name)
            LOG("net-diag[%02d] seq=%u %s op=%u svc=%.8s a0=%d res=%d err=%d tid=%u lr=%#llx",
                i, e->seq, dmnd_class(e->class_id), e->op, svc, e->a0, e->result, e->err, e->tid, (unsigned long long)e->lr);
        else
            LOG("net-diag[%02d] seq=%u %s op=%u a0=%d a1=%d res=%d err=%d flags=%u tid=%u lr=%#llx",
                i, e->seq, dmnd_class(e->class_id), e->op, e->a0, e->a1, e->result, e->err, e->flags, e->tid, (unsigned long long)e->lr);
    }
}

void dmnd_log_net_mode_once(int mode) {
    uint32_t want = 0;
    if (atomic_compare_exchange_strong_explicit(&g_dmnd.net_mode_logged, &want, 1, memory_order_relaxed, memory_order_relaxed)) {
        const char *m = mode == DM_NET_OFFLINE ? "offline" : mode == DM_NET_LAN ? "lan" : mode == DM_NET_LDN ? "ldn" : mode == DM_NET_AUTO ? "auto" : "?";
        LOG("net-diag: network mode=%s (%d)", m, mode);
    }
}

void dmnd_log_nifm_once(int available) {
    uint32_t want = 0;
    if (atomic_compare_exchange_strong_explicit(&g_dmnd.nifm_logged, &want, 1, memory_order_relaxed, memory_order_relaxed))
        LOG("net-diag: NIFM available=%d", available);
}

typedef struct { int32_t fd; int16_t events, revents; } dmnd_pollfd;
int dmnd_poll_has_eventfd(const void *fds, uint64_t count, int nfds, const void *r, const void *w, const void *e) {
    (void)fds; (void)count; (void)nfds; (void)r; (void)w; (void)e;
    return 0; /* target branch has no eventfd implementation; Stage 2a records hooks only */
}
