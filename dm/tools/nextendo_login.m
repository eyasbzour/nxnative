// SPDX-License-Identifier: GPL-3.0-only
// nextendo_login: sign this Mac in to Nextendo for nxnative's online play (after Mush8's launcher/Nextendo.swift, c22dev/mush8 @ 9322831c).
//   nextendo_login sign-in    opens Nextendo's sign-in page in the browser and keeps the sign-in on this Mac (dm/host/nextendo_login_apple.inc says where)
//   nextendo_login status     says whether a game token can be had now, and for whom
//   nextendo_login sign-out   forgets the sign-in
// Build: clang -fobjc-arc -O1 -Wall -Wextra -o nextendo_login dm/tools/nextendo_login.m -framework Foundation -framework Security -framework AppKit
// It prints the account's name and PID, never a token. The iPhone app signs in from its settings screen instead (dm/ios/Sources/NextendoSignIn.m).
#import <AppKit/AppKit.h>
#import "../host/nextendo_login_apple.inc"
#include <stdio.h>

static int report(NSDictionary *record, NSString *error) {
    if (!record) { fprintf(stderr, "nextendo_login: %s\n", error.UTF8String); return 1; }
    NSDate *until = [NSDate dateWithTimeIntervalSince1970:[record[@"expires_at"] doubleValue]];
    printf("Signed in to Nextendo as %s (PID %s). A game token is available, valid until %s.\n", [record[@"identity"][@"username"] UTF8String],
           [[record[@"identity"][@"pid"] stringValue] UTF8String], [NSDateFormatter localizedStringFromDate:until dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterShortStyle].UTF8String);
    return 0;
}
static int sign_in(void) {
    NSString *verifier = nxl_random_urlsafe(32), *state = nxl_random_urlsafe(16);
    if (!verifier || !state) { fprintf(stderr, "nextendo_login: no random bytes\n"); return 1; }
    uint16_t port = 0; int fd = nxl_listen_loopback(&port);
    if (fd < 0) { perror("nextendo_login: loopback listener"); return 1; }
    NSString *redirect = [NSString stringWithFormat:@"http://127.0.0.1:%u/callback", port];
    NSURL *url = nxl_authorize_url(redirect, state, verifier);
    printf("Opening Nextendo's sign-in page in your browser (waiting up to 5 minutes). If it does not open, visit:\n%s\n", url.absoluteString.UTF8String);
    [NSWorkspace.sharedWorkspace openURL:url];
    NSDictionary *query = nxl_wait_callback(fd, state, 300, NULL);
    close(fd);
    NSString *error = nil;
    NSDictionary *record = nxl_finish_sign_in(query, verifier, redirect, &error);
    return report(record, query ? error : @"no answer from the sign-in page in 5 minutes");
}
int main(int argc, char **argv) { @autoreleasepool {
    NSString *command = argc == 2 ? [NSString stringWithUTF8String:argv[1]] : @"";
    if ([command isEqual:@"sign-in"]) return sign_in();
    if ([command isEqual:@"status"]) { NSString *error = nil; return report(nxl_game_record(&error), error); }
    if ([command isEqual:@"sign-out"]) { if (!nxl_write_refresh(nil)) { perror("nextendo_login: sign-out"); return 1; } puts("Signed out of Nextendo on this Mac."); return 0; }
    fprintf(stderr, "usage: nextendo_login sign-in | status | sign-out\n"); return 2;
} }
