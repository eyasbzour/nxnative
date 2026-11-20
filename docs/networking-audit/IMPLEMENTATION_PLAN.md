# nxnative networking migration plan

Goal: Nextendo online play in nxnative, with Super Mario Bros. Wonder 1.2.1 friend rooms as the first end-to-end target. Rules: no fake success, correct error paths instead of crashes, keep the existing diagnostics, never weaken TLS verification globally, keep credentials out of logs.

## Baseline

- Branch: `integration/ldn-846` @ `2f86f640` (seedds `main` `2f131edc` merged in on 2026-11-10). Worktree `C:\Users\Eyasb\Documents\nx-ldn`.
- Last green CI before that merge: run `42309361525` on `fd04a3f7`, every job. The merge head is being checked in run `42855822064`.
- Diagnostics to keep: the Stage 2a ring, abort dump, EventFd/poll counters and NIFM once-loggers in `hle_net_diag.c`.

## Sources and licenses

| Source | Pin | License | Use |
|---|---|---|---|
| seedds/nxnative #846, #953, #956, #961 (RobiiAragon) | #961 head `4c7e43f1` | MIT | Primary code source: TLS, NSD routing, Nextendo account/social/routes, resolver, network clock. See `UPSTREAM_NETWORKING_PRS.md`. |
| RobiiAragon/NX-Port-Studio | `main`, pushed 2026-11-04 | MIT | Nextendo game catalog, NPLN patch tool (`dm/tools/nextendo_patches.py`), iOS Keychain/authorization flow. |
| seedds/nxnative #1283 (rastapasta) | `97e6a454` | MIT | EventFd implementation. |
| c22dev/mush8 | `9322831c` | GPL-3.0 | Second reference: single host/virtual descriptor table, Nextendo DNS redirect. |
| c22dev/nxhost | `1654434f` | GPL-3.0 | Older substrate reference. |

Licensing decision (2026-11-10, replaced by the update below): this work stays in the `eyasbzour/nxnative` fork, and no PRs go to seedds. Mush8 code can be ported, reused or translated wherever it helps. Files derived from Mush8 carry GPL-3.0 headers. A binary that contains them is GPL-3.0 as a whole, so each IPA build gets a tag pointing at its source in the public fork.

Updated 2026-11-14: the fork now holds no Mush8-derived code. The Nextendo sign-in (`dm/host/nextendo_login_apple.inc`, `hle_nextendo_login_apple.m`, `dm/ios/Sources/NextendoSignIn.{h,m}`, `dm/tools/nextendo_login.m`) was rewritten under MIT from Nextendo's public OAuth interface, so the online work can go to seedds. Mush8 stays a reference for facts (endpoints, token shapes, which calls a game makes), not a source of code.

## Architecture

```text
Nextendo layer (from #961, new files)
  routes and NSD answers, account bridge and id token, X.509 policy, social, BCAT

Networking compatibility layer
  guest BSD ABI
  one guest descriptor table for sockets and EventFds
  Poll/Select over mixed descriptors, bounded guest waits
  resolver (#956), NIFM state machine, network clock (#953)
  ssl service over the game's socket (#961)

nxnative platform layer (keep)
  hle_net_backend.c Apple sockets, guest waits and lifecycle, LDN and discovery, hle_net_diag.c
```

Nextendo rules stay out of the socket hot paths, apart from explicit, testable policy lookups. New online code goes in new files rather than `hle_net.c` and `hle_offline.c`, which conflict on every upstream sync.

## Stages

### Stage 1: audit (done)

`MUSH8_NETWORKING_AUDIT.md`, `NXNATIVE_NETWORKING_AUDIT.md`, `PORTING_MATRIX.md`, `UPSTREAM_NETWORKING_PRS.md` and this plan.

### Stage 2: bring in the MIT online stack

1. Create `nextendo/wonder` from `integration/ldn-846`.
2. Merge #961 (`4c7e43f1`). The trial merge conflicts in 10 files and `hle_net.c` merges cleanly. Resolve the conflicts toward upstream `main`'s current code.
3. Run the #961 suites (`ssl`, `nsd`, `online-policy`, `nextendo-*`, `resolver-*`, with the sanitize targets) on CI with `GAME=010015100B514000`.
4. Check that offline, LAN and LDN behavior is unchanged with nothing configured.

Exit: CI green on the merge, no behavior change in default builds.

### Stage 3: trace Wonder

Run Wonder 1.2.1 on the Mac (or iPhone) with the #961 stack and a Nextendo credential, through to the online menu and a friend room attempt. Record the order of service calls (`ConnectToHipcService`, socket, ssl, nifm, account, NPLN) and the first failure, using the diagnostics ring and abort dump. That trace decides the rest of the work. Wonder 1.0.0 is tracked separately, since Nextendo only lists 1.2.1.

### Stage 4: one descriptor table for sockets and EventFds

Required for NPLN, which uses gRPC. gRPC wakes its pollers with EventFd and polls those alongside its sockets. Since the upstream merge, EventFds number from 0, the same range as the backend's socket slots (`NET_MAX=1024`), and `h_sk_EventFd` still fails whenever networking is on.

1. Start from #1283's `hle_socket_eventfd.c` (counter and semaphore modes, close/reuse safety, guest-releasing waits).
2. Give sockets and EventFds one table, with one numbering space and generation checks, in the style of Mush8's host/virtual table.
3. Make `dm_sk_poll` / `dm_sk_select` handle mixed sets in every mode, keeping the known game fixes (Pikmin 4 on-hold, Hades, Star Fox, Ocarina gRPC startup).
4. Tests: EventFd in every network mode, mixed poll/select, closed and invalid descriptors, timeouts, no waits that never end. Run under ASan, UBSan and TSan.

### Stage 5: Wonder online

1. Apply Wonder 1.2.1's signed NPLN patch through Port Studio's `nextendo_patches.py` flow (exact build only).
2. Fix what the Stage 3 trace showed, in order: DNS/NSD routing, TLS handshakes (scoped trust only), id token and BAAS login, NPLN matchmaking.
3. Friend room create and join, then a full session, then disconnect, reconnect and repeated launches.

For every failure capture the mode, Wonder version, service and operation, DNS host (redacted where needed), NIFM state, SSL result, socket/EventFd readiness, and the diagnostics ring and abort dump.

### Stage 6: iOS and stabilization

- Credentials in the iOS Keychain, set from the app, following Port Studio's authorization flow.
- IPA on device: multicast, DNS and TLS behavior, log capture per the existing workflow.
- Full CI: host unit tests, tool and docs tests, build check (Mac Vulkan/NVN/OpenGL, gfx compile, iOS source compile), sanitizers, coverage, unsigned iOS app.

## Keeping up with seedds

No PRs go to seedds. The fork keeps merging seedds `main` and the RobiiAragon PR heads as they move. New online code goes in new files to keep those merges small.

## Risks

| Risk | Mitigation |
|---|---|
| #961 is a draft, 288 commits behind main, and unvalidated on its current head | Merge it on our branch and validate with our CI before building on it. Re-sync with RobiiAragon's head when it moves. |
| No NPLN game has gone online on any of these stacks | Stage 3 trace before writing Wonder-specific code. |
| Mush8 code comes back into the fork | Write fixes from facts (Nextendo's interfaces, the game's calls), not by translating Mush8's code; every file stays MIT. |
| Offline, LAN or LDN titles regress | Nothing changes without configuration. Full CI after each stage. |
| Guest deadlock or spin | Keep bounded waits and the `dm_guest_*` integration. TSan coverage. |
| Insecure TLS shortcuts | #961's scoped trust only, exact leaf match, no system trust store changes. |
| Credential leaks | Redact tokens in logs and diagnostics. No secrets in committed files. |
| SecureTransport stops at TLS 1.2 | Check what Nextendo's NPLN endpoints accept during the Stage 3 trace. |

## Next action

Stage 2: create `nextendo/wonder`, merge #961, resolve the 10 conflicts, run CI.
