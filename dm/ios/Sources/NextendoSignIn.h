// SPDX-License-Identifier: GPL-3.0-only
// Nextendo sign-in on the iPhone, for the launcher's Nextendo section (Launcher.swift). The flow and the stored sign-in are the Mac's
// (dm/host/nextendo_login_apple.inc, after Mush8): Nextendo's page in an ASWebAuthenticationSession, its loopback redirect caught by a listener in the app,
// the refresh token in the app's own container. The host turns it into the game token when a game asks (hle_nextendo_login_apple.m).

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// YES when this app was built with --nextendo: its bundle holds the public service profile (dm/nextendo-services, build_ipa.sh).
BOOL dm_nextendo_built(void);

/// YES when a sign-in is stored (no network). The account itself is checked by dm_nextendo_check.
BOOL dm_nextendo_signed_in(void);

/// Asks Nextendo for a game token as a game will, off the main thread, and calls done on the main thread with the account
/// ("name (PID n)") or nil and the reason.
void dm_nextendo_check(void (^done)(NSString *_Nullable account, NSString *_Nullable error));

/// Opens Nextendo's sign-in page over the app and calls done on the main thread, as dm_nextendo_check does, once it is over.
void dm_nextendo_sign_in(void (^done)(NSString *_Nullable account, NSString *_Nullable error));

/// Forgets the sign-in.
void dm_nextendo_sign_out(void);

NS_ASSUME_NONNULL_END
