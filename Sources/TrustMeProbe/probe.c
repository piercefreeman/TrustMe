// Out-of-process TCC check.
//
// Some TCC answers go stale inside a running process: once
// TCCAccessPreflight reports Developer Tools as denied, the app keeps seeing
// that after the user turns it on. A fresh process sees the truth, so TrustMe
// re-executes the app's own binary with TRUSTME_TCC_PROBE set. This
// constructor runs before the app's main, answers through the exit code
// (0 granted, 1 denied, 2 unknown) and exits without starting the app.
#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <stdlib.h>
#include <unistd.h>

#include "TrustMeProbe.h"

void trustme_probe_anchor(void) {}

__attribute__((constructor)) static void trustme_probe(void) {
    const char *service = getenv("TRUSTME_TCC_PROBE");
    if (service == NULL) return;

    void *tcc = dlopen("/System/Library/PrivateFrameworks/TCC.framework/TCC", RTLD_LAZY);
    int (*preflight)(CFStringRef, CFDictionaryRef) = tcc ? dlsym(tcc, "TCCAccessPreflight") : NULL;
    if (preflight == NULL) _exit(2);

    CFStringRef name = CFStringCreateWithCString(NULL, service, kCFStringEncodingUTF8);
    int result = preflight(name, NULL);
    _exit(result == 0 ? 0 : result == 1 ? 1 : 2);
}
