// SPDX-License-Identifier: GPL-3.0-only
// Nextendo sign-in on the iPhone (NextendoSignIn.h). Nextendo takes only a loopback redirect, which no custom-scheme or associated-domain callback represents:
// the session opens with no callback scheme and stays up until the listener here gets the redirect, then it is closed (as NX-Port-Studio does, MIT).
#import "NextendoSignIn.h"
#import "../../host/nextendo_login_apple.inc"
#import <AuthenticationServices/AuthenticationServices.h>
#import <UIKit/UIKit.h>

static NSString *account_text(NSDictionary *record) {
    return [NSString stringWithFormat:@"%@ (PID %@)", record[@"identity"][@"username"], record[@"identity"][@"pid"]];
}
static void finish(void (^done)(NSString *, NSString *), NSDictionary *record, NSString *error) {
    NSString *account = record ? account_text(record) : nil, *reason = record ? nil : (error ?: @"the sign-in failed");
    dispatch_async(dispatch_get_main_queue(), ^{ done(account, reason); });
}

BOOL dm_nextendo_built(void) {
    NSString *routes = [NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"dm/nextendo-services/routes.tsv"];
    return [NSFileManager.defaultManager fileExistsAtPath:routes];
}
BOOL dm_nextendo_signed_in(void) { return nxl_read_refresh() != nil; }
void dm_nextendo_check(void (^done)(NSString *, NSString *)) {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{ NSString *error = nil; NSDictionary *record = nxl_game_record(&error); finish(done, record, error); });
}
void dm_nextendo_sign_out(void) { nxl_write_refresh(nil); }

@interface DmNextendoAnchor : NSObject <ASWebAuthenticationPresentationContextProviding>
@end
@implementation DmNextendoAnchor
- (ASPresentationAnchor)presentationAnchorForWebAuthenticationSession:(ASWebAuthenticationSession *)session {
    (void)session;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes)
        if ([scene isKindOfClass:UIWindowScene.class]) for (UIWindow *w in ((UIWindowScene *)scene).windows) if (w.isKeyWindow) return w;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes)
        if ([scene isKindOfClass:UIWindowScene.class] && ((UIWindowScene *)scene).windows.count) return ((UIWindowScene *)scene).windows.firstObject;
    return [[UIWindow alloc] init];   // ASPresentationAnchor is UIWindow on iOS; the launcher's window is always there, so this is not reached
}
@end

void dm_nextendo_sign_in(void (^done)(NSString *, NSString *)) {
    static ASWebAuthenticationSession *session; static DmNextendoAnchor *anchor; static _Atomic int cancelled;
    NSString *verifier = nxl_random_urlsafe(32), *state = nxl_random_urlsafe(16);
    uint16_t port = 0; int fd = verifier && state ? nxl_listen_loopback(&port) : -1;
    if (fd < 0) { finish(done, nil, @"the sign-in could not start (no loopback listener)"); return; }
    NSString *redirect = [NSString stringWithFormat:@"http://127.0.0.1:%u/callback", port];
    [session cancel];
    atomic_store(&cancelled, 0);
    anchor = [DmNextendoAnchor new];
    session = [[ASWebAuthenticationSession alloc] initWithURL:nxl_authorize_url(redirect, state, verifier) callbackURLScheme:nil
                                            completionHandler:^(NSURL *url, NSError *error) { (void)url; (void)error; atomic_store(&cancelled, 1); }];   // only a cancel ends it this way
    session.presentationContextProvider = anchor;
    session.prefersEphemeralWebBrowserSession = NO;
    if (![session start]) { close(fd); session = nil; finish(done, nil, @"the sign-in page could not be shown"); return; }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSDictionary *query = nxl_wait_callback(fd, state, 300, &cancelled);
        close(fd);
        BOOL by_player = atomic_load(&cancelled);
        dispatch_async(dispatch_get_main_queue(), ^{ [session cancel]; session = nil; });
        NSString *error = nil;
        NSDictionary *record = query ? nxl_finish_sign_in(query, verifier, redirect, &error) : nil;
        finish(done, record, query ? error : by_player ? @"the sign-in was cancelled" : @"no answer from the sign-in page in 5 minutes");
    });
}
