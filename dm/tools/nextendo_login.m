// SPDX-License-Identifier: GPL-3.0-only
// nextendo_login: sign this Mac in to Nextendo for nxnative's online play (after Mush8's launcher/Nextendo.swift, c22dev/mush8 @ 9322831c).
//   nextendo_login sign-in    opens Nextendo's sign-in page in the browser and keeps the sign-in on this Mac (dm/host/nextendo_login_apple.inc says where)
//   nextendo_login status     says whether a game token can be had now, and for whom
//   nextendo_login sign-out   forgets the sign-in
// Build: clang -fobjc-arc -O1 -Wall -Wextra -o nextendo_login dm/tools/nextendo_login.m -framework Foundation -framework Security -framework AppKit
// It prints the account's name and PID, never a token.
#import <AppKit/AppKit.h>
#import "../host/nextendo_login_apple.inc"
#include <arpa/inet.h>
#include <netinet/in.h>
#include <poll.h>
#include <stdio.h>
#include <sys/socket.h>
#include <time.h>

static NSString *random_urlsafe(size_t count) {
    uint8_t bytes[64];
    if (count > sizeof bytes || SecRandomCopyBytes(kSecRandomDefault, count, bytes)) return nil;
    return nxl_b64url([NSData dataWithBytes:bytes length:count]);
}
// The loopback redirect's listener on 127.0.0.1: Mush8's port when it is free, any port otherwise. -1 on failure
static int listen_loopback(uint16_t *port) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return -1;
    int one = 1; setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
    struct sockaddr_in a = {.sin_len = sizeof a, .sin_family = AF_INET, .sin_port = htons(kNxCallbackPort), .sin_addr.s_addr = htonl(INADDR_LOOPBACK)};
    if (bind(fd, (struct sockaddr *)&a, sizeof a)) { a.sin_port = 0; if (bind(fd, (struct sockaddr *)&a, sizeof a)) { close(fd); return -1; } }
    socklen_t n = sizeof a;
    if (listen(fd, 4) || getsockname(fd, (struct sockaddr *)&a, &n)) { close(fd); return -1; }
    *port = ntohs(a.sin_port); return fd;
}
static void reply(int c, const char *status, const char *body) {
    char head[256]; int n = snprintf(head, sizeof head, "HTTP/1.1 %s\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: %zu\r\nConnection: close\r\n\r\n", status, strlen(body));
    (void)!write(c, head, (size_t)n); (void)!write(c, body, strlen(body));
}
// Waits for the browser's GET /callback carrying our state, answering anything else with 404. The query, or nil when the time runs out
static NSDictionary<NSString *, NSString *> *wait_callback(int fd, NSString *state, int seconds) {
    time_t end = time(NULL) + seconds;
    for (;;) {
        int left = (int)(end - time(NULL));
        if (left <= 0) return nil;
        struct pollfd p = {.fd = fd, .events = POLLIN};
        if (poll(&p, 1, left * 1000) <= 0) continue;
        int c = accept(fd, NULL, NULL);
        if (c < 0) continue;
        struct timeval tv = {5, 0}; setsockopt(c, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);
        char buf[16384]; size_t got = 0;
        while (got < sizeof buf - 1) { ssize_t n = read(c, buf + got, sizeof buf - 1 - got); if (n <= 0) break; got += (size_t)n; buf[got] = 0; if (strstr(buf, "\r\n")) break; }
        buf[got] = 0;
        NSString *line = [[[NSString alloc] initWithUTF8String:buf] componentsSeparatedByString:@"\r\n"].firstObject;
        NSArray<NSString *> *words = [line componentsSeparatedByString:@" "];
        NSURLComponents *url = words.count >= 2 && [words[0] isEqual:@"GET"] ? [NSURLComponents componentsWithString:[@"http://127.0.0.1" stringByAppendingString:words[1]]] : nil;
        NSMutableDictionary *query = [NSMutableDictionary new];
        for (NSURLQueryItem *item in url.queryItems) query[item.name] = item.value ?: @"";
        if (![url.path isEqual:@"/callback"] || ![query[@"state"] isEqual:state]) { reply(c, "404 Not Found", ""); close(c); continue; }
        reply(c, "200 OK", "<!doctype html><title>nxnative</title><p>Nextendo sign-in received. You can close this tab and go back to the terminal.</p>");
        close(c); return query;
    }
}
static int report(NSDictionary *record, NSString *error) {
    if (!record) { fprintf(stderr, "nextendo_login: %s\n", error.UTF8String); return 1; }
    NSDate *until = [NSDate dateWithTimeIntervalSince1970:[record[@"expires_at"] doubleValue]];
    printf("Signed in to Nextendo as %s (PID %s). A game token is available, valid until %s.\n", [record[@"identity"][@"username"] UTF8String],
           [[record[@"identity"][@"pid"] stringValue] UTF8String], [NSDateFormatter localizedStringFromDate:until dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterShortStyle].UTF8String);
    return 0;
}
static int sign_in(void) {
    NSString *verifier = random_urlsafe(32), *state = random_urlsafe(16);
    if (!verifier || !state) { fprintf(stderr, "nextendo_login: no random bytes\n"); return 1; }
    uint8_t digest[CC_SHA256_DIGEST_LENGTH]; NSData *v = [verifier dataUsingEncoding:NSUTF8StringEncoding];
    CC_SHA256(v.bytes, (CC_LONG)v.length, digest);
    NSString *challenge = nxl_b64url([NSData dataWithBytes:digest length:sizeof digest]);
    uint16_t port = 0; int fd = listen_loopback(&port);
    if (fd < 0) { perror("nextendo_login: loopback listener"); return 1; }
    NSString *redirect = [NSString stringWithFormat:@"http://127.0.0.1:%u/callback", port];
    NSURLComponents *c = [NSURLComponents componentsWithString:kNxAuthorize];
    c.queryItems = @[[NSURLQueryItem queryItemWithName:@"client_id" value:kNxClientID], [NSURLQueryItem queryItemWithName:@"redirect_uri" value:redirect],
                     [NSURLQueryItem queryItemWithName:@"response_type" value:@"code"], [NSURLQueryItem queryItemWithName:@"scope" value:kNxScopes],
                     [NSURLQueryItem queryItemWithName:@"state" value:state], [NSURLQueryItem queryItemWithName:@"code_challenge" value:challenge],
                     [NSURLQueryItem queryItemWithName:@"code_challenge_method" value:@"S256"]];
    printf("Opening Nextendo's sign-in page in your browser (waiting up to 5 minutes). If it does not open, visit:\n%s\n", c.URL.absoluteString.UTF8String);
    [NSWorkspace.sharedWorkspace openURL:c.URL];
    NSDictionary *query = wait_callback(fd, state, 300);
    close(fd);
    if (!query) { fprintf(stderr, "nextendo_login: no answer from the sign-in page in 5 minutes\n"); return 1; }
    if (query[@"error"]) { fprintf(stderr, "nextendo_login: Nextendo refused the sign-in (%s)\n", [query[@"error"] UTF8String]); return 1; }
    NSString *code = query[@"code"];
    if (!code.length) { fprintf(stderr, "nextendo_login: Nextendo sent no sign-in code\n"); return 1; }
    nxl_write_refresh(nil);
    NSString *error = nil;
    if (!nxl_token(@{@"grant_type": @"authorization_code", @"client_id": kNxClientID, @"code": code, @"code_verifier": verifier, @"redirect_uri": redirect}, &error)) return report(nil, error);
    if (!nxl_read_refresh()) return report(nil, @"Nextendo returned no refresh token, so the sign-in cannot be kept");
    return report(nxl_game_record(&error), error);   // proves the account can get a game token, as a game will
}
int main(int argc, char **argv) { @autoreleasepool {
    NSString *command = argc == 2 ? [NSString stringWithUTF8String:argv[1]] : @"";
    if ([command isEqual:@"sign-in"]) return sign_in();
    if ([command isEqual:@"status"]) { NSString *error = nil; return report(nxl_game_record(&error), error); }
    if ([command isEqual:@"sign-out"]) { if (!nxl_write_refresh(nil)) { perror("nextendo_login: sign-out"); return 1; } puts("Signed out of Nextendo on this Mac."); return 0; }
    fprintf(stderr, "usage: nextendo_login sign-in | status | sign-out\n"); return 2;
} }
