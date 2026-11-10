// SPDX-License-Identifier: GPL-3.0-only
// Nextendo sign-in for this fork on the Mac, shared by the host (hle_nextendo_login_mac.m) and the sign-in tool (dm/tools/nextendo_login.m).
// The flow is Mush8's (c22dev/mush8 launcher/Nextendo.swift @ 9322831c, GPL-3.0): OAuth 2 with PKCE in the browser and a loopback redirect, then a refresh
// token kept on this Mac, which turns into the game token (nx2) when a game needs one. This file is derived from that code, so it is GPL-3.0 (docs/networking-audit).
// The refresh token lives in a private file (0600, in a 0700 folder; nxl_dir below), not the Keychain: every rebuild of dmhost is a new program to the Keychain,
// which would ask again each time. No token is ever logged: the errors carry Nextendo's error codes and HTTP statuses only.
#import <Foundation/Foundation.h>
#import <Security/Security.h>
#include <CommonCrypto/CommonDigest.h>
#include <errno.h>
#include <fcntl.h>
#include <math.h>
#include <sys/stat.h>
#include <unistd.h>

// (Each user of this file uses some of these: unused is not a warning.)
// Mush8's registered public client, borrowed until this fork registers its own (nextendo.network/developers, a "Public application (desktop / mobile, PKCE)"
// with the redirect below): Nextendo's sign-in page names Mush8, and Mush8 or Nextendo can revoke it. Replace this one value with the fork's own ID
static NSString *const kNxClientID __attribute__((unused)) = @"nxc_PZv-XFn79sLo";
static NSString *const kNxScopes __attribute__((unused)) = @"identity friends game.matchmaking presence";
static NSString *const kNxAuthorize __attribute__((unused)) = @"https://nextendo.network/oauth/authorize";
static NSString *const kNxTokenEndpoint __attribute__((unused)) = @"https://nextendo.network/api/oauth/token";
static NSString *const kNxGameTokenEndpoint __attribute__((unused)) = @"https://nextendo.network/api/nex-token";
static const uint16_t kNxCallbackPort __attribute__((unused)) = 47823;   // http://127.0.0.1:<port>/callback, Mush8's port first, any free one otherwise (Nextendo allows dynamic loopback ports)
static const NSTimeInterval kNxTimeout __attribute__((unused)) = 12;

static NSString *nxl_dir(void) {
    const char *custom = getenv("DM_NEXTENDO_LOGIN_DIR");
    if (custom && *custom) return [NSString stringWithUTF8String:custom];
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/nxnative/nextendo"];
}
static NSString *nxl_refresh_path(void) { return [nxl_dir() stringByAppendingPathComponent:@"refresh_token"]; }

// The stored refresh token, or nil: a regular file of this user's, readable by no one else, no symbolic link
static NSString *nxl_read_refresh(void) {
    int fd = open(nxl_refresh_path().fileSystemRepresentation, O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
    if (fd < 0) return nil;
    struct stat st;
    if (fstat(fd, &st) || !S_ISREG(st.st_mode) || (st.st_mode & 077) || st.st_uid != geteuid() || st.st_size <= 0 || st.st_size > 8192) { close(fd); return nil; }
    NSMutableData *data = [NSMutableData dataWithLength:(NSUInteger)st.st_size];
    size_t done = 0;
    while (done < data.length) { ssize_t n = read(fd, (char *)data.mutableBytes + done, data.length - done); if (n <= 0) { close(fd); return nil; } done += (size_t)n; }
    close(fd);
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    text = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return text.length ? text : nil;
}
// Replaces the stored refresh token atomically (a nil token removes it). YES on success
static BOOL nxl_write_refresh(NSString *token) {
    NSString *path = nxl_refresh_path();
    if (!token) return !unlink(path.fileSystemRepresentation) || errno == ENOENT;
    NSString *dir = nxl_dir();
    if (![NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions: @0700} error:nil]) return NO;
    if (chmod(dir.fileSystemRepresentation, 0700)) return NO;
    NSString *temporary = [path stringByAppendingFormat:@".%d.tmp", getpid()];
    unlink(temporary.fileSystemRepresentation);
    int fd = open(temporary.fileSystemRepresentation, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0600);
    if (fd < 0) return NO;
    NSData *bytes = [token dataUsingEncoding:NSUTF8StringEncoding];
    BOOL ok = write(fd, bytes.bytes, bytes.length) == (ssize_t)bytes.length && !fsync(fd);
    ok = !close(fd) && ok;
    if (ok) ok = !rename(temporary.fileSystemRepresentation, path.fileSystemRepresentation);
    if (!ok) unlink(temporary.fileSystemRepresentation);
    return ok;
}

static NSString *nxl_b64url(NSData *data) {
    NSString *s = [[data base64EncodedStringWithOptions:0] stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
    return [[s stringByReplacingOccurrencesOfString:@"/" withString:@"_"] stringByReplacingOccurrencesOfString:@"=" withString:@""];
}
static NSData *nxl_unb64url(NSString *s) {
    NSString *n = [[s stringByReplacingOccurrencesOfString:@"-" withString:@"+"] stringByReplacingOccurrencesOfString:@"_" withString:@"/"];
    n = [n stringByPaddingToLength:(n.length + 3) & ~(NSUInteger)3 withString:@"=" startingAtIndex:0];
    return [[NSData alloc] initWithBase64EncodedString:n options:0];
}
static NSString *nxl_form(NSDictionary<NSString *, NSString *> *form) {
    NSMutableCharacterSet *allowed = [NSMutableCharacterSet alphanumericCharacterSet]; [allowed addCharactersInString:@"-._~"];
    NSMutableArray *pairs = [NSMutableArray new];
    for (NSString *key in form) [pairs addObject:[NSString stringWithFormat:@"%@=%@", key, [form[key] stringByAddingPercentEncodingWithAllowedCharacters:allowed]]];
    return [pairs componentsJoinedByString:@"&"];
}
static void nxl_fail(NSString **error, NSString *text) { if (error) *error = text; }

// One HTTPS request with a bounded wait: the JSON object of an HTTP 200, otherwise nil and Nextendo's error code (or the status) in *error
static NSDictionary *nxl_send(NSURLRequest *request, NSString **error) {
    __block NSData *body = nil; __block NSInteger status = 0; __block NSError *failure = nil;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    NSURLSession *session = [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.ephemeralSessionConfiguration];
    [[session dataTaskWithRequest:request completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
        body = d; failure = e; status = [r isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)r).statusCode : 0;
        dispatch_semaphore_signal(done);
    }] resume];
    dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);   // the request's own timeout ends the wait
    [session finishTasksAndInvalidate];
    id json = body.length ? [NSJSONSerialization JSONObjectWithData:body options:0 error:nil] : nil;
    NSDictionary *object = [json isKindOfClass:NSDictionary.class] ? json : nil;
    if (status != 200) {
        NSString *code = [object[@"error"] isKindOfClass:NSString.class] ? object[@"error"] : nil;
        nxl_fail(error, code ?: failure ? [NSString stringWithFormat:@"no answer from Nextendo (%@)", failure.localizedDescription] : [NSString stringWithFormat:@"Nextendo answered HTTP %ld", (long)status]);
        return nil;
    }
    if (!object) nxl_fail(error, @"Nextendo's answer was not JSON");
    return object;
}
// The token endpoint: returns the access token, and stores the refresh token Nextendo sends back (it rotates them)
static NSString *nxl_token(NSDictionary<NSString *, NSString *> *form, NSString **error) {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:kNxTokenEndpoint] cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:kNxTimeout];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    request.HTTPBody = [nxl_form(form) dataUsingEncoding:NSUTF8StringEncoding];
    NSString *failure = nil;
    NSDictionary *json = nxl_send(request, &failure);
    if (!json) {
        if ([failure isEqual:@"invalid_grant"] && [form[@"grant_type"] isEqual:@"refresh_token"]) { nxl_write_refresh(nil); failure = @"the Nextendo sign-in has expired: sign in again (nextendo_login sign-in)"; }
        nxl_fail(error, failure); return nil;
    }
    NSString *access = json[@"access_token"];
    if (![access isKindOfClass:NSString.class] || !access.length) { nxl_fail(error, @"Nextendo sent no access token"); return nil; }
    NSString *refresh = json[@"refresh_token"];
    if ([refresh isKindOfClass:NSString.class] && refresh.length && !nxl_write_refresh(refresh)) { nxl_fail(error, @"the renewed sign-in could not be stored"); return nil; }
    return access;
}

// The credential record hle_nextendo_apple.m's decode_credential accepts, from the nx2 game token Nextendo issued: the identity is the token's own payload
// (pid.username.expiry, the expiry in seconds), never a second source that could disagree with it. nil and a reason when the token is not one
static NSDictionary *nxl_record(NSString *token, NSTimeInterval now, NSString **error) {
    NSArray<NSString *> *parts = [token componentsSeparatedByString:@"."];
    if (parts.count != 3 || ![parts[0] isEqual:@"nx2"]) { nxl_fail(error, @"Nextendo's game token is not an nx2 token"); return nil; }
    NSData *payload = nxl_unb64url(parts[1]);
    NSString *text = payload ? [[NSString alloc] initWithData:payload encoding:NSUTF8StringEncoding] : nil;
    NSArray<NSString *> *claims = [text componentsSeparatedByString:@"."];
    if (claims.count < 3) { nxl_fail(error, @"Nextendo's game token names no identity"); return nil; }
    unsigned long long pid = 0, expiry = 0;
    NSScanner *p = [NSScanner scannerWithString:claims.firstObject], *x = [NSScanner scannerWithString:claims.lastObject];
    if (![p scanUnsignedLongLong:&pid] || !p.isAtEnd || !pid || ![x scanUnsignedLongLong:&expiry] || !x.isAtEnd) { nxl_fail(error, @"Nextendo's game token names no identity"); return nil; }
    NSString *username = [[claims subarrayWithRange:NSMakeRange(1, claims.count - 2)] componentsJoinedByString:@"."];
    if (!username.length || (double)expiry <= now) { nxl_fail(error, @"Nextendo's game token has already expired"); return nil; }
    return @{@"schema_version": @1, @"token_kind": @"nex", @"token": token,
             @"identity": @{@"pid": @(pid), @"username": username},
             @"created_at": @(floor(now)), @"expires_at": @(expiry),
             @"scopes": [kNxScopes componentsSeparatedByString:@" "]};
}
// The stored sign-in → a fresh access token → the game token → its record. nil and a reason when any step fails
static NSDictionary *nxl_game_record(NSString **error) {
    NSString *refresh = nxl_read_refresh();
    if (!refresh) { nxl_fail(error, @"this Mac is not signed in to Nextendo: run nextendo_login sign-in"); return nil; }
    NSString *access = nxl_token(@{@"grant_type": @"refresh_token", @"client_id": kNxClientID, @"refresh_token": refresh}, error);
    if (!access) return nil;
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:kNxGameTokenEndpoint] cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:kNxTimeout];
    [request setValue:[@"Bearer " stringByAppendingString:access] forHTTPHeaderField:@"Authorization"];
    NSDictionary *json = nxl_send(request, error);
    if (!json) return nil;
    NSString *token = json[@"nex_token"];
    if (![token isKindOfClass:NSString.class] || !token.length) { nxl_fail(error, @"Nextendo gave no game token: the account needs a confirmed e-mail and a linked Discord account"); return nil; }
    return nxl_record(token, NSDate.date.timeIntervalSince1970, error);
}
