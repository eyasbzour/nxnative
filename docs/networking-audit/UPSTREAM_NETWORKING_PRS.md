# Networking work already open against seedds/nxnative

Surveyed 2026-11-10 against seedds `main` @ `2f131edc`. None of these PRs is merged. The upstream repository and every PR listed here are MIT. We merge them into the fork only; no PRs go back to seedds.

## The online stack: RobiiAragon (#846, #953, #956, #961)

RobiiAragon wrote #846, the base of our `integration/ldn-846`. They also maintain [NX Port Studio](https://github.com/RobiiAragon/NX-Port-Studio) (MIT, "Built on nxnative"), which ships an experimental Nextendo integration. Issue #951 is their scope proposal for moving that backend upstream as separate PRs. Nobody has replied to it yet.

| PR | Head | What it adds | Depends on |
|---|---|---|---|
| #846 | `63fffb94` | Opt-in native LAN sockets and an LDN IP bridge | |
| #953 | `5ee105f9` (clock part) | Network clock availability from the kernel's synchronization state instead of a fixed failure | |
| #956 | `2cf9c007` | Cancellable IPv4 DNSService resolver operations (445 lines over #846) | #846 |
| #961 | `4c7e43f1`, draft | The whole online backend: TLS, NSD routing, Nextendo account/social/routes/X.509, BCAT | #846, #956, #953 |

What #961 contains (88 files under `dm/host`, about 9,100 lines added):

- `hle_ssl.c`, `hle_ssl_apple.m`, `ssl_backend.h`, `ssl_trace.h`: the Horizon `ssl` service over the game's own socket. SecureTransport runs the TLS stream, SecTrust checks public PKI with network fetch turned off, and a static, hash-pinned libcrypto (`dm/tools/apple_crypto.py`) checks private PKI. Trust is scoped per context. An optional enrolled leaf certificate has to match one approved identity exactly.
- `hle_nsd.c`, `hle_nsd_backend.c`, `nsd.h`: explicit service routing and NSD answers.
- `hle_nextendo_routes.c`, `hle_nextendo_x509.c`, `hle_nextendo_apple.m`, `hle_nextendo_api_apple.m`, `hle_nextendo_social_apple.m`, `hle_nextendo_friends.c`: per-title routes, certificate checks, an account bridge that supplies the NSA id token (`LoadNetworkServiceAccountIdTokenCache`, `EnsureNetworkServiceAccountIdTokenCacheAsync`), BAAS identity, friends and presence.
- `hle_bcat.c`, `hle_bcat_apple.m`: optional signed BCAT delivery.
- Tests for each part (`t_ssl.m`, `t_nsd.c`, `t_online_policy.c`, `t_nextendo_*`, `t_bcat_*`, `t_resolver_*`), with ASan/UBSan targets.

The PR leaves out the frontend, credentials, enrolled certificates and the per-game patch tool. Those stay in Port Studio. With nothing configured, a build stays offline.

Reported results (Port Studio, Mac): one Mario Kart 8 Deluxe 4.0.1 Worldwide race on Nextendo, one Smash Ultimate 13.0.5 arena round, Splatoon 2 EUR 5.5.2 reaching the lobby and matchmaking queue. iOS online is untested. The PR says hosted CI has not validated its current head.

### Wonder in Port Studio

Port Studio's `docs/nextendo-coverage.md` lists Super Mario Bros. Wonder `010015100B514000` as an NPLN title, version 1.2.1, with one signed patch build, status "Unverified". The patches come from Nextendo's signed NPLN patch catalog (revision 9, 22 exact-build patches), applied by `dm/tools/nextendo_patches.py` as exact-build IPS32 plans. That answers where the Wonder 1.2.1 certificate/peer-name patches come from. The patch tool is in Port Studio, not in #961.

### How #961 fits our branch

A trial `git merge-tree` of #961 (`4c7e43f1`) into `integration/ldn-846` (`2f86f640`) conflicts in 10 files: `dm/host/Makefile`, `dm/host/hle_account.c`, `dm/host/hle_fs.c`, `dm/host/hle_offline.c`, `dm/host/tests/Makefile`, `dm/ios/tools/build_ipa.sh`, `dm/ios/tools/gen_build.py`, `docs/agents/symptoms.md`, `docs/env_switches.tsv`, `docs/reference/services.md`. `hle_net.c` merges cleanly. The PR is 288 commits behind seedds `main`.

## Other networking PRs

| PR | Author | State | What it does | Use to us |
|---|---|---|---|---|
| #1283 | rastapasta | open | EventFd as its own file (`hle_socket_eventfd.c`): counter and semaphore modes, blocking reads that release the guest core, close/reuse safety, 46 checks under ASan/UBSan/TSan | Better EventFd than main's 64-slot table. Still offline-only. Basis for the shared descriptor table. |
| #1651 | Haseenesss | closed | Event descriptors inside an fd_set, Select waits on them | Same change landed in main and is now in our merge. |
| #565 | oliverames | open, mergeable | `DM_NET=1` real IPv4 sockets, Linux errno from `GetLastErrno`, BSD `sin_len` address fix, `DM_NET_PEERS` unicast copies of broadcasts | Overlaps #846. The errno and `sin_len` fixes are worth checking against our backend. |
| #1321 | iMonZ | open, WIP | Mario Kart World LAN across subnets: native sockets, ICMP echo, NIFM, discovery relay to listed peers | Discovery relay idea. Says Nintendo online is unsupported. |
| #798 | SifatTaj | open | Stub `nn::ssl::Context::Create` offline | Superseded by #961's SSL service. |
| #1199 | keanu-stitch8 | open | Answer retail server environment queries without nsd | Overlaps #961's NSD. |
| #1968 | Haseenesss | open, mergeable | `nsd:a` / `nsd:u` as an offline retail console | Overlaps #961's NSD. |
| #1875 | varyform | open | `AdjustableNetworkSystemClock::Adjust` offline | Overlaps #953. |
| #1990 | Atomsk-debug | open | Notes no longer say the host refuses EventFd | Docs only. |

## What this changes for the plan

1. Base the online work on RobiiAragon's MIT stack instead of porting Mush8. It already covers TLS, routing, account tokens and NSD for NEX games, and it is written for this code base.
2. Wonder is an NPLN title, and none of these PRs has run an NPLN game online. NPLN uses gRPC, which wakes its pollers with EventFd while sockets are in the same Poll. Main's EventFd still fails whenever networking is on (`hle_net.c` `h_sk_EventFd`). That shared socket/EventFd descriptor table is the gap nobody has filled, and #1283 is the best starting point for it.
3. Mush8 (GPL-3.0) is still fair game to port or reuse, mainly its single host/virtual descriptor table and its Nextendo DNS redirect, and anything else that fills a gap #961 leaves.
