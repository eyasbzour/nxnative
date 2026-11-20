# nxnative networking audit (Phase 1, read-only)

Status: source audit only. Worktree `C:\Users\Eyasb\Documents\nx-ldn`, branch `integration/ldn-846`, head `fd04a3f7` (Stage 2a CI fixes). No new code changes in this audit.

## Repository/license context

- Repo: `eyasbzour/nxnative` (`origin`), upstream remote `seedds/nxnative`.
- License: MIT (`LICENSE`, Copyright 2026 seedds). Mush8/nxhost are GPL-3.0. Since 2026-11-14 the fork holds no Mush8-derived code; Mush8 is a reference for facts (see `IMPLEMENTATION_PLAN.md`).

## Networking/HLE files (current surface)

| Area | Files (representative) | Notes |
|---|---|---|
| Socket/BSD/NIFM/SSL/EventFd HLE | `dm/host/hle_net.c`, `dm/host/hle_offline.c`, `dm/host/net_socket.h` | Main nn::socket/nifm/ssl hooks, offline defaults, opt-in transport. `hle_offline.c` holds SDK4/offline socket variants; duplicate GetPeerName takeover removed in CI fix. |
| Native transport/backend | `dm/host/hle_net_backend.c` | Apple IPv4 TCP/UDP translation, guest fd slots (`NET_MAX=1024`), Horizon↔Darwin errno/flag/sockaddr conversion, bounded waits, discovery helpers, `dm_net_*` API. |
| LDN | `dm/host/hle_ldn.c`, `hle_ldn.h`, `hle_ldn_protocol.c`, `discovery_protocol.h`, `net_discovery*` | LDN service ABI + ldn_mitm-style LAN wire format, discovery/transport support, host tests `t_ldn*`, `t_net_discovery*`. |
| Diagnostics (Stage 2a) | `dm/host/hle_net_diag.h`, `hle_net_diag.c` | Lock-free 32-entry ring, `dmnd_record/dump`, once-loggers, EventFd/poll counters. Instrumented into socket/NIFM/SSL/SF paths without intended behavior/timing changes. |
| SF/HIPC | `dm/host/hle_sf.c` | Service connect/dispatch; records unserved `ConnectToHipcService` (Stage 2a). |
| Thread/lifecycle/OE | `dm/host/hle_thread.c`, `hle_lifecycle.c`, `hle_oe.c`, `hle_fdstat.c` | Guest waits/sleep/cond integration, shutdown, fd stats. Networking waits must respect pausable guest contexts/collector behavior. |
| Host tests | `dm/host/tests/t_net*.c`, `t_ldn*.c`, `t_pollwait.c` | Socket/EventFd/write-prepare/discovery/LDN/pollwait coverage present. |

## Implemented/observed behavior

### BSD sockets
- `dm/host/hle_net.c` gates behavior on `dm_net_enabled()`/network mode; offline defaults return failure/idle behavior consistent with existing comments (e.g. ENETDOWN semantics noted for Horizon). Explicit LAN/transport paths call `dm_net_*` backend operations.
- Backend `hle_net_backend.c` manages guest socket slots with native fd duplicates, generation checks, nonblocking mode (`NX_NONBLOCK=0x800`), bounded waits (`NET_SLICE_MS=100`), Darwin socket translation, and guest-memory safety hooks (`dm_guest_write_prepare`, host-wait begin/end).
- `net_socket.h` exposes modes `DM_NET_OFFLINE/LAN/LDN/AUTO` and APIs for socket ops, poll/select, DNS (`dm_net_getaddrinfo*`, `dm_net_gethostbyname`), freeaddrinfo, ipconfig, NIFM helpers, discovery prepare/supplement.

### Guest FD management
- Backend uses fixed `NET_MAX=1024` slot table under mutex; borrows duplicate fds with generation/liveness checks to avoid reuse races.
- `hle_net.c` keeps a local EventFd table (`EFD_MAX=64`) with condvar waits through `dm_guest_cond_wait_ns`. Since the seedds `main` merge of 2026-11-10 (`2f86f640`), EventFds number from 0, as Horizon does. That is the same range as the backend's socket slots, so the two tables can hand out the same number. `h_sk_EventFd` still returns `sk_fail()` whenever `dm_net_enabled()`, so the clash cannot happen yet, but EventFd in network modes (needed for gRPC/NPLN) has to come with one shared table. See `IMPLEMENTATION_PLAN.md` Stage 4.

### Poll / Select
- `dm_sk_poll`/`dm_sk_select` in `hle_net.c` have distinct offline and enabled paths. Offline path handles "nothing to wait on"/host-never-made descriptors carefully (returns no-ready/idle at timeout rather than fatal ENETDOWN patterns that caused game spin/abort cases). EventFd readiness is integrated for emulated descriptors. Enabled path delegates to backend and records diagnostics.
- Backend has `dm_net_poll`/`dm_net_select`/`dm_net_idle` (implementation details beyond inspected header/start require full read before changes).

### EventFd
- Implemented as local Horizon BSD-service descriptor emulation in `hle_net.c` (not Darwin eventfd). Needed for gRPC/poller wakeups (Ocarina of Time case cited). Diagnostics count first EventFd/poll interactions.
- Gap: behavior in explicit LAN/LDN/AUTO/online modes must be validated end-to-end; current code comments indicate enabled-mode EventFd transport limitations.

### DNS
- API exists in `net_socket.h` (`dm_net_getaddrinfo`, legacy variant, `dm_net_freeaddrinfo`, `dm_net_gethostbyname`). `hle_net.c` hooks nn::socket resolver calls to backend (`GetAddrInfo`/`FreeAddrInfo`/`GetHostEnt*`). No Nextendo hostname remap or Nintendo→server redirect policy observed in audited sections.

### NIFM
- `hle_net.c` implements async request semantics: `SubmitNetworkRequest` sets pending and 1-query hold; `IsNetworkRequestOnHold` consumes hold; `CancelNetworkRequest` clears; `IsNetworkAvailable` uses `dm_nifm_available()` (enabled + pending + not on hold + ipconfig success). This preserves Horizon timing fixes noted in comments (Pikmin 4, Hades). `dm_nifm_submit_wait` helper exists.
- No Nextendo-specific network policy or account linkage in NIFM path.

### SSL/TLS
- `hle_net.c` SSL hooks are mostly offline stubs/cut points: Initialize/Finalize/Context Create/Destroy succeed as local service operations; connections/handshake/I/O/cert operations fail (e.g. `Connection::Create` and `DoHandshake` return `RES_FAIL`, Read/Write return -1). Diagnostics record init/ctx/conn/hs/io.
- No real TLS transport, no certificate verification policy, no SNI/host routing, no Nextendo server trust scoping.

### Nextendo / NPLN / online account
- No `nextendo` implementation or `NX_NEXTENDO_*` handling found in `hle_net.c`/`hle_sf.c` by search. NPLN/gRPC wakeup need is mentioned only as EventFd motivation comment; no NPLN/BAAS service implementation found in audited networking files.
- This is the largest functional gap for Wonder online via Nextendo.

### Wonder-specific compatibility
- No Wonder-specific cert/peer-name patches found in audited networking files. Existing behavior is generic/offline-leaning unless a game path has separate patches elsewhere.

### Diagnostics / observability
- Stage 2a ring diagnostics are in place and CI-green after integration fixes (`fd04a3f7`). Keep them during migration.

## Risks / constraints

- Networking code interacts with guest-thread pausing, deterministic clock waits, and lifecycle/shutdown. Changes must preserve these invariants.
- EventFd namespace and mixed fd behavior are subtle; regressions can cause poll spin, deadlock, or gRPC aborts.
- SSL/NIFM/DNS changes can affect unrelated titles; keep offline behavior intact and gate new online behavior explicitly.
- iOS/macOS platform differences (entitlements, multicast, TLS APIs, sandbox/network permissions) need separate validation.
