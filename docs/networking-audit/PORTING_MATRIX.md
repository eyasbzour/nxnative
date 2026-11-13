# Porting matrix

Where each networking piece comes from. Updated 2026-11-10 after the survey in `UPSTREAM_NETWORKING_PRS.md` and the decision that Mush8 code may be reused in the fork.

Decisions:
- **Take #961 / #1283**: merge the MIT code from the open seedds PRs.
- **Learn from Mush8**: take facts from it (what Nextendo expects, what a game calls) and write the C ourselves under MIT. Since 2026-11-14 no Mush8-derived code is in the fork (`IMPLEMENTATION_PLAN.md`).
- **Keep nxnative**: keep the current implementation and adapt its interfaces.
- **Gap**: nobody has built it yet.

| Component | MIT source (seedds PRs, Port Studio) | Mush8 / nxhost (GPL) | nxnative now (`ldn-846` @ `2f86f640`) | Decision |
|---|---|---|---|---|
| Guest descriptor table | none | `services/bsd.rs` `FDS` table with `Host`/`Virt` entries | Backend socket slots `NET_MAX=1024` from 0; separate EventFd table `EFD_MAX=64`, also from 0 since the upstream merge | **Gap**: one table for both. Port the shape from Mush8, keep nxnative's slot and generation checks. |
| EventFd | #1283 `hle_socket_eventfd.c`: counter/semaphore modes, guest-releasing waits, close/reuse safety | not separately audited | Works offline; `h_sk_EventFd` fails whenever networking is on | **Take #1283**, then extend to every network mode. Needed by gRPC (NPLN). |
| BSD socket ops | #846 (in our branch), #565 errno and `sin_len` fixes | `bsd.rs` host/virtual dispatch, errno mapping | `hle_net.c` hooks over `hle_net_backend.c` | **Keep nxnative**; check #565's two fixes against our backend. |
| Poll/Select | main's Select-as-Poll (#1651) is in our merge | `bsd.rs` | `dm_sk_poll` / `dm_sk_select` with transport branches and game-specific timeout fixes | **Keep nxnative**; add mixed socket/EventFd sets with the new table. |
| DNS resolver | #956 cancellable DNSService resolver | `sfdnsres.rs`, `dnssd.rs` | `dm_net_getaddrinfo*`, `gethostbyname` hooks | **Take #961** (contains #956). |
| NSD / service routing | #961 `hle_nsd.c`, `hle_nextendo_routes.c`; #1968, #1199 overlap | `nextendo.rs` hostname redirect to Nextendo IPs | none | **Take #961**. Use Mush8's redirect table only to cross-check hostnames. |
| NIFM | #846 | `nifm.rs` | Async request/on-hold model, Pikmin 4 timing kept | **Keep nxnative**. |
| Network clock | #953 (in #961) | | Fixed failure offline | **Take #961**. |
| SSL service | #961 `hle_ssl.c`, `hle_ssl_apple.m`: SecureTransport over the game's socket, SecTrust for public PKI, static libcrypto for private PKI, per-context trust | `ssl.rs` with rustls and a custom verifier | Context create works, connections fail | **Take #961**. Check TLS 1.3 needs (SecureTransport stops at 1.2). |
| Nextendo account / id token | #961 `hle_nextendo_apple.m`, `hle_nextendo_api_apple.m`; Port Studio Keychain and browser authorization | `nextendo.rs`: env `NX_NEXTENDO_PID` / `NX_NEXTENDO_TOKEN`, JWT-shaped id token | none | **Take #961**; iOS flow from Port Studio. |
| Social / friends / presence | #961 `hle_nextendo_social_apple.m`, `hle_nextendo_friends.c` | | Offline friends HLE | **Take #961**. |
| BCAT | #961 `hle_bcat.c` (optional, signed) | | none | **Take #961**, keep off unless Wonder needs it. |
| Wonder 1.2.1 NPLN patch | Nextendo's signed NPLN catalog (rev 9) through Port Studio `dm/tools/nextendo_patches.py`; Wonder listed with one patch build | not present (Mush8 targets Mario Kart 8 Deluxe) | none | **Take from Port Studio**: exact-build IPS32 plan only. |
| NPLN / gRPC online path | none qualified; Port Studio lists Wonder as "Unverified" | none | none | **Gap**: trace first (plan Stage 3). |
| Discovery / LDN | #846, #871, #1321 relay | `vnet`, `lan`, `wireless` | Mature LDN, protocol and discovery code with tests | **Keep nxnative**. |
| Threads and waits | | Rust Arc/Mutex/Condvar | pthreads plus `dm_guest_sleep_ns`, `dm_guest_cond_wait_ns` | **Keep nxnative**. |
| Shutdown / cleanup | #961 lifecycle tests | | `hle_lifecycle.c`, backend finalize | **Keep nxnative**; make sure SSL contexts and routes are released. |

## Layer boundary

1. Platform layer (keep): `hle_net_backend.c`, guest waits, lifecycle, diagnostics, LDN.
2. Networking compatibility layer: the descriptor table, EventFd, Poll/Select, resolver, NIFM, SSL service.
3. Nextendo layer (new files from #961): routes, account, X.509, social, BCAT. Reached from the socket paths only through explicit policy lookups.

## Rust FFI

Not needed. #961 already covers in C and Objective-C what Mush8 does in Rust, and a Rust library would add a toolchain to the iOS build. Port individual Mush8 pieces to C where they fill a gap.
