# Mush8 / nxhost networking audit (Phase 1, read-only)

Status: source audit only. No nxnative code changed.

## Scope and upstream references

| Repository | Branch | Commit (audited) | Date (UTC) | License | Notes |
|---|---|---|---|---|---|
| `c22dev/mush8` | `main` | `9322831c74f9ed36a002015b336b05f521bce5f4` | 2026-10-30T16:42:45Z | GPL-3.0 | Commit message: `nextendo online mode`. Source of Nextendo + virtual-network/BSD/NIFM/SSL integration inspected. |
| `c22dev/nxhost` | `main` | `1654434f57af84807dffd02cc04463eeafc2c269` | 2026-10-25T14:32:06Z | GPL-3.0 | Earlier toolkit state. BSD/NIFM/vnet/dnssd present; no `services/nextendo.rs` or `services/ssl.rs` in this tree. Mush8 carries the newer Nextendo/SSL pieces. |

License implication (decision input, not legal advice): mush8 and nxhost are GPL-3.0. nxnative is MIT (`LICENSE`: Copyright 2026 seedds). Direct code reuse or linking strategies that create a combined derivative can trigger GPL obligations. Before reusing code, confirm: exact files/commits used, whether integration is a separate process/library boundary, whether clean-room/behavioral reimplementation is preferred, and project licensing/distribution intent. **Do not copy GPL code into nxnative without an explicit license decision.**

## Component audit (mush8 @ `9322831`)

### 1) Nextendo policy and identity (`crates/nxhost/src/services/nextendo.rs`)

Observed behavior (from source):
- Enabled when `vnet::mode() == Mode::Nextendo` (`NX_NET=nextendo` path implied by mode naming in related code; verify full mode enum).
- Identity/config from environment: `NX_NEXTENDO_PID` (u64, default 0), `NX_NEXTENDO_TOKEN` (trimmed). Missing sign-in is logged but not fabricated.
- Fixed endpoints: `SERVER=51.178.29.194`, `NAT=164.132.111.120`, `BAAS=e0d67c509fb203858ebcb2fe3f88c2aa.baas.nintendo.com`.
- `nsd_resolve`: replaces `%` with `lp1`; maps `accounts.nintendo.com` / `api.accounts.nintendo.com` to BAAS; otherwise passes host through.
- `redirect`: wildcard host rules → `Ipv4Addr` (`nncs2-*.n.n.srv.nintendo.net` and `g2b309e01-lp1.s.n.srv.nintendo.net` → NAT; Nintendo domains → SERVER). Records last redirected host per destination IP in `LAST_HOST`.
- `host_for(addr)`: returns remembered original host for redirected server IP (used by SSL/SNI/verification path decisions).
- `id_token()`: caches RS256-shaped id token (header `kid=nextendo-baas-key-1`, `iss=https://<BAAS>`, `jku` to BAAS certificates, 3h lifetime, refreshed 10 min early). Claims include stable random `sub/di/did/jti`, Switch-like `sn`, `hm`, `tv` from `crate::game::version()`, and `nnex` when token present. Signature bytes are random (`base64url(&random::<256>())`) — **not a real cryptographic signature**; acceptance depends on Nextendo server behavior.
- `is_server(addr)` marks SERVER/NAT.

Porting concerns:
- Hardcoded IPs/BAAS host are compatibility-critical; treat as config/constants with provenance.
- `NX_NEXTENDO_TOKEN`/PID in env is simple but not a secure storage design for iOS; plan must define storage/transmission.
- Unsigned/forged JWT shape is a server-compatibility behavior to reproduce only if required and understood; never present as Nintendo-authentic.

### 2) BSD guest fd / socket dispatch (`crates/nxhost/src/services/bsd.rs`)

Observed behavior (from inspected sections):
- Unified guest fd table `FDS: Mutex<Vec<Option<Fd>>>` with variants `Host(i32)` (Darwin host fd) and `Virt(Arc<vnet::Socket>)` (userspace virtual socket). `adopt` reuses holes or appends; `release` takes slot.
- `call` dispatches to `virt_call` for virtual fds (cmds in 8..=22,24..=27 range shown) before host path — virtual networking can coexist with host-backed behavior.
- Helpers translate Horizon/Linux errno to guest-visible values (`linux_errno`), NX nonblock flag `NX_O_NONBLOCK=0x800`, `EBADF` handling.
- IPv4 sockaddr parsing/output helpers (`sockaddr_in`, `put_sockaddr`, `addr_str`).
- iOS multicast/broadcast entitlement gate: macOS `multicast_ok()=true`; iOS checks `entitlement::present()`. `note_lan` starts LAN service and logs broadcast mode.
- Broadcast/shout handling: detects subnet broadcast/multicast, can fan out to LAN unicast targets (`crate::services::lan::unicast_targets`) when native broadcast limited; `read_udp`/`send_to`/`deliver` paths shown.
- `NX_TRACE_BSD` env trace flag.

Not fully audited in this pass (need deeper read before implementation): full BSD command table, Poll/Select/EventFd mapping details, blocking/wakeup semantics, socket option translation completeness, `RecvMmsg`/`SendMmsg`, DNS/resolver integration points, close/shutdown interactions with virtual sockets, thread-safety under guest scheduler.

### 3) Userspace virtual network (`crates/nxhost/src/services/vnet.rs`)

Observed behavior:
- `Transport` trait sends raw packets (`send(&self, packet: &[u8])`).
- Modes: `Off`, `Lan`, `LanPlay`, `Wireless`; `NX_NET` selects mode (`lan|lanplay|wireless|off`; legacy `NX_LAN` fallback). `is_virtual` for LanPlay/Wireless.
- Virtual addressing: fixed mask `255.255.0.0`, gateway `10.13.37.1`, random local 10.13.x.y (1..254, not gateway). `network()` returns address/mask/gateway when link active.
- Transport startup: `lanplay` requires `NX_LANPLAY_SERVER=host[:port]` via `crate::services::lanplay::start`; `wireless` via `crate::services::wireless::start`.
- UDP-like socket state machine in userspace (`Socket`: local/peer/nonblock/timeout/queue/shut/closed; condvar wakeups; epoch/`wait_change` for pollers). Ports table holds weak refs. Supports bind/connect/send_to/recv_from/peek/dontwait semantics (partial view).
- Poll flags include `POLLIN|POLLOUT|POLLNVAL`. Linux/Horizon errno constants used (`EAGAIN=11`, `EBADF=9`, etc.).
- Broadcast/local helpers; packetization/MTU/queue bounds (`MTU=1500`, `QUEUE=512`).

Not fully audited: full TCP behavior (if any), ICMP/ARP emulation, LanPlay/Wireless wire formats, interaction with Nextendo redirect (Nextendo has `redirect`/`is_server`; check whether vnet or BSD consults it), timeout/wakeup correctness under nxhost threading model.

### 4) NIFM (`crates/nxhost/src/services/nifm.rs`)

Observed behavior:
- `lan()` returns local address/mask depending on mode: `Off` none, `Lan` probes host interfaces (`NX_LAN_IF` override, prefers `en0`), virtual modes use `vnet::network()`. Calls `bsd::note_lan` when found.
- `GeneralService`: offline returns `NO_INTERNET_CONNECTION` for network-dependent queries, can still provide request object; online/LAN returns local IP, netmask/gateway, DNS-like fields, and marks network available. Request service states: accepted/error, events, request handling.
- `RequestService` models async request states (`REQUEST_STATE_ERROR/ACCEPTED`, `NO_INTERNET_CONNECTION`).

Comparison note: nxnative already models NIFM async request/on-hold/settled behavior in `dm/host/hle_net.c` (`g_nifm_pending/g_nifm_hold`, `Submit/Cancel/IsNetworkRequestOnHold`, `dm_nifm_available`) and has LDN/discovery transport. Porting should preserve nxnative's Horizon timing/compat fixes (Pikmin 4/Hades cases) unless behavior is proven wrong.

### 5) SSL/TLS (`crates/nxhost/src/services/ssl.rs`, mush8)

Observed behavior (header/structure):
- Implements Horizon `ssl` service over guest socket fd using Rust `rustls` (`ClientConnection`, `ClientConfig`, custom `ServerCertVerifier` danger hook indicated by imports).
- Uses `nextendo` for server-aware behavior (`host_for`, likely redirect/SNI/cert policy decisions). Maps I/O/socket states to Horizon SSL result codes (`WOULD_BLOCK/TIMEOUT/CONNECTION_RESET/ABORT/NO_SOCKET/INVALID_SOCKET/ALREADY_IN_USE`).
- Supports blocking/nonblocking I/O modes and handshake timeout (`HANDSHAKE_TIMEOUT_MS=30s`), chunked writes.
- Interacts with BSD fd helpers (`bsd::{bytes, bytes_mut, in_buf, out_buf,...}`).

Not fully audited: certificate verification policy details, internal PKI registration, ALPN/SNI host selection, how Wonder 1.2.1 certificate/peer-name patches are applied, token/session cache behavior, whether verification is globally weakened or scoped to Nextendo-routed hosts. **This is security-sensitive; reproduce only scoped behavior required for compatibility.**

### 6) DNS / sfdnsres / dnssd

Files present in mush8: `sfdnsres.rs`, `dnssd.rs`. Not deeply read in this pass. nxhost also has `dnssd.rs`. Mush8 `nextendo::nsd_resolve` performs `%`→`lp1` and BAAS remap for specific hosts; BSD/vnet/resolver path must be traced to see where redirect/resolve are applied (getaddrinfo/gethostbyname/dnssd). Wonder/Nextendo may require specific Nintendo service hostnames and server routing.

### 7) Threading / shutdown / lifecycle

nxhost/mush8 are Rust services with Arc/Mutex/Condvar and transport threads implied by vnet/lanplay/wireless modules. nxnative is C with pthreads and guest-thread/HLE lifecycle constraints (`hle_thread.c`, `hle_lifecycle.c`, `hle_oe.c`, pausable waits, shutdown). Any port must map wakeups/timeouts to nxnative's guest wait/sleep/cond primitives and cleanup rules; direct Rust threading models cannot be dropped in unchanged.

### 8) Wonder-specific compatibility

Not found in the audited Nextendo/bsd/vnet snippets by game name. User-provided context states Nextendo identifies Wonder 1.2.1 as supported with certificate and peer-name compatibility patches. **Action:** locate exact Wonder patch sites and conditions in mush8/nxhost history and launcher/config before Phase 4/5; test 1.0.0 and 1.2.1 separately.

## nxhost @ `1654434` delta (relevant)

nxhost has `bsd.rs`, `nifm.rs`, `vnet.rs`, `dnssd.rs` and no `nextendo.rs`/`ssl.rs` in the inspected tree. Mush8 appears to be the active product integration carrying Nextendo online mode. Use mush8 as primary behavior reference for Nextendo; use nxhost for shared substrate/history only where helpful.

## Gaps / unknowns requiring follow-up reads

1. Full mush8 BSD command dispatch, Poll/Select/EventFd implementation, and errno/flag tables.
2. Full SSL verifier policy, certificate buffers, host/SNI selection, and Wonder-specific exceptions.
3. Full DNS path (`sfdnsres`, `dnssd`, getaddrinfo/gethostbyname integration with `nextendo::redirect/nsd_resolve`).
4. NPLN/account/friends/service objects beyond Nextendo token injection (search mush8 tree for `npln`, `nn::account`, `friends`, `aauth` equivalents).
5. `Mode::Nextendo` definition and configuration surface (CLI/launcher/env).
6. LanPlay/Wireless packet formats and whether Wonder/Nextendo use them.
7. Exact Wonder 1.2.1 cert/peer-name patch data and where applied.

## Reuse decision (2026-11-10)

- Reusing Mush8 code is allowed. The fork sends no PRs to seedds, so derived code can go on any fork branch, with GPL-3.0 headers on the derived files.
- Mush8 is now the second reference. The MIT stack in seedds #961 (RobiiAragon) already covers TLS, routing, NSD and the account id token in C and Objective-C, so it comes first (`UPSTREAM_NETWORKING_PRS.md`).
- What Mush8 still adds: its single host/virtual descriptor table (`bsd.rs` `FDS`) as the model for one socket/EventFd table, and its hostname redirect list to cross-check #961's routes.
- No Rust FFI: it would add a toolchain to the iOS build for pieces #961 already has.
- Question 7 above is answered: the Wonder 1.2.1 patch comes from Nextendo's signed NPLN patch catalog, applied by NX Port Studio's `dm/tools/nextendo_patches.py`. It is not in Mush8.
