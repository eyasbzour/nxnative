# Online play checklist

What online play through Nextendo needs, item by item, compared across three code bases: Mush8 (c22dev/mush8, GPL-3.0, a Mario Kart 8 Deluxe port), NX Port Studio (RobiiAragon, MIT, the source of seedds #961) and this fork. Written 2026-11-14 from the Mario Kart 8 Deluxe 4.0.1 imports (`main`, `subsdk0`), Super Mario Bros. Wonder 1.2.1 logs and the three source trees.

The fork's code is MIT. Mush8 is used for facts only (what Nextendo expects, what a game calls). Every item is written at the SDK level, so it applies to any game that makes the same calls, not only the two named here.

Status: **done** (in the fork), **verify** (written, waiting for a device log), **todo**, **not needed**.

## Sign-in and the account

| Item | Mush8 | Port Studio | This fork | Status |
|---|---|---|---|---|
| OAuth sign-in with PKCE and a loopback redirect | launcher (Swift) | iOS launcher (Swift), user-supplied client ID | `nextendo_login_apple.inc`, rewritten under MIT | done |
| Saved sign-in | Keychain | Keychain | private file (0600) in the app container | done; Keychain is optional |
| Game token (`/api/nex-token`, nx2) | yes | yes | yes | done |
| Why an account may not play (`/api/online-status`) | launcher | not checked | sign-in error text; the log at the first game sign-in and after a 2306-08xx error | done; not yet seen on a device |
| Own registered OAuth client ID | its own | user enters one | a build setting (`DM_NEXTENDO_CLIENT_ID`); the fork's workflow sets Mush8's, borrowed | todo: register one at nextendo.network/developers |
| BaaS id token with the `nnex` proof | yes | yes (#961) | yes | done (Wonder online works) |
| `GetNetworkServiceAccountId` = Nextendo PID | yes | yes | yes | done |
| Nickname, country, birthday from `/api/me` | nickname, country | country (#961) | all three, with the OAuth access token (`/api/me` refused the nx2 token with 401 until 2026-11-14) | done; the access token not yet seen on a device |
| Online membership (`hm`, license kind) | yes | `hm` (#961) | yes | done |

## Network plumbing

| Item | Mush8 | Port Studio | This fork | Status |
|---|---|---|---|---|
| Name routing to Nextendo's servers | hostname table | public service profile | public service profile (#961) | done |
| `nsd::ResolveEx` | yes | yes | yes | done |
| TLS (`nn::ssl` C++ and `nnssl*` C), Nextendo CA only | yes | yes | yes, all 19 C calls Mario Kart imports are hooked | done |
| Sockets, C and C++ (`nnsocket*`) | IPC level | yes | yes; Inet helpers run the SDK's own code | done |
| Game errno on failed socket calls | n/a (IPC) | not checked | yes (#2589) | done |
| RecvMsg / SendMsg, EventFd (gRPC games) | yes | yes | yes (#2589) | done |
| C resolver layout | n/a | not checked | yes (#2589) | done |
| Wi-Fi adapter chosen over cellular | n/a | not checked | yes | done |
| UDP port kept briefly after close, ICMP reports on UDP receives ignored | yes | not checked | yes, Nextendo mode only | verify |

## Social

| Item | Mush8 | Port Studio | This fork | Status |
|---|---|---|---|---|
| Friend list (`/api/friends`) | access token | nx2 token | nx2 token | verify: a refused request now logs its HTTP status |
| Presence (`/api/presence`) | access token, every 45 s | on commit | on commit, then every 45 s | verify the token, done the repeat |
| `UserPresence::SetDescription` | SDK code | cut | SDK code with Nextendo on | done |
| Play time on Nextendo's site (`/api/history`) | yes | not checked | the account's total for the game plus this run's time, sent every minute | done; not yet seen on a device |
| Play history registration key | n/a | from the firmware's friends module | local key | done |
| The player's Mii from Nextendo | yes (launcher) | not checked | the account's Mii joins the game's Mii database; nothing is uploaded, and Nextendo's site has no Mii maker | done; not yet seen on a device |
| What the player does, beside the game's name (presence `app_detail`) | from the game's play report | not checked | the game's own `UserPresence::SetDescription` text | done; not yet seen on a device |

## Matchmaking and peer-to-peer

| Item | Mush8 | Port Studio | This fork | Status |
|---|---|---|---|---|
| NPLN (gRPC) games, e.g. Wonder | n/a | yes | yes | done: sign-in, rooms, search |
| NEX games, e.g. Mario Kart | yes | yes | all calls covered | verify on a phone |
| Game patch from Nextendo's catalog | n/a | yes | yes (Wonder has one; Mario Kart needs none) | done |
| Mario Kart menu sites Mush8 patches (`main+0x4d8a04`, `0x4da738`) | its own menu mod | n/a | no | todo on a `kart` branch: check them in a stock 4.0.1 `main`; if needed, our own patch in the game's `patches.py` |
| Two players in one room (Pia NAT check, then direct UDP or relay) | yes | not checked | not tested | verify |
| Backgrounding the app | not checked | not checked | sockets drop; the game shows 2321-4992 | iOS limit |

## Local play

| Item | Mush8 | Port Studio | This fork | Status |
|---|---|---|---|---|
| Local wireless (LDN) bridge | yes | yes, plus a LAN relay (`dm/net/lan_relay.c`) | yes (#846), unicast sweep on UDP 11452 | verify between two phones |
| LAN mode | yes | yes | yes | done |

## Diagnostics

| Item | Mush8 | Port Studio | This fork | Status |
|---|---|---|---|---|
| gRPC's internal errors | n/a | not checked | yes | done |
| NEX packet trace (PRUDP) | yes | not checked | no | todo if NEX stalls |
| Credential and account traces | not checked | yes | partial | todo, optional |
