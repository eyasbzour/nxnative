// SPDX-License-Identifier: GPL-3.0-only
// The Mac host's Nextendo credential provider (dm_nextendo_set_credential_provider, hle_nextendo_apple.m): when a game in Nextendo mode needs its account, the
// sign-in stored by dm/tools/nextendo_login.m becomes a fresh game token (nextendo_login_apple.inc, after Mush8's launcher). The record is kept until two minutes
// before its token expires; a failed fetch waits 30 s before the next try and the game sees an account that is not available, never an invented one.
// Only the Mac: the iPhone app has no sign-in yet.
#include <TargetConditionals.h>
#if TARGET_OS_OSX
#import "nextendo_login_apple.inc"
#include "nextendo_account.h"
#include <pthread.h>
#include <stdio.h>
#include <string.h>

void dm_guest_host_wait_begin(void);
void dm_guest_host_wait_end(void);

static pthread_mutex_t g_login_lock = PTHREAD_MUTEX_INITIALIZER;
static NSData *g_record;
static NSTimeInterval g_record_until, g_retry_after;

static bool nextendo_login_provider(uint8_t *buffer, size_t capacity, size_t *size) { @autoreleasepool {
    pthread_mutex_lock(&g_login_lock);
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    if ((!g_record || g_record_until - now < 120) && now >= g_retry_after) {
        NSString *error = nil;
        dm_guest_host_wait_begin(); NSDictionary *record = nxl_game_record(&error); dm_guest_host_wait_end();
        NSData *data = record ? [NSJSONSerialization dataWithJSONObject:record options:0 error:nil] : nil;
        if (data) { g_record = data; g_record_until = [record[@"expires_at"] doubleValue]; g_retry_after = 0; fprintf(stderr, "[dm] nextendo: signed in as %s\n", [record[@"identity"][@"username"] UTF8String]); }
        else { g_record = nil; g_retry_after = now + 30; fprintf(stderr, "[dm] [RED] nextendo: no game credential: %s\n", (error ?: @"the record could not be encoded").UTF8String); }
    }
    bool ok = g_record && g_record.length <= capacity && g_record_until > now;
    if (ok) { memcpy(buffer, g_record.bytes, g_record.length); *size = g_record.length; }
    pthread_mutex_unlock(&g_login_lock);
    return ok;
} }
__attribute__((constructor)) static void nextendo_login_install(void) { dm_nextendo_set_credential_provider(nextendo_login_provider); }
#endif
