#include "CMultitouchShim.h"

#ifdef __APPLE__
#include <ApplicationServices/ApplicationServices.h>
#include <CoreFoundation/CoreFoundation.h>
#include <stdatomic.h>

// Private WindowServer/Dock event types used by macOS trackpad gestures.
// See the open-source Instant Space Switcher / dockswipe implementations.
enum {
    kFWMGestureEvent = 29,
    kFWMDockControlEvent = 30,
};

static const CGEventField kFWMRealEventTypeField = (CGEventField)55;
static const CGEventField kFWMGestureHIDTypeField = (CGEventField)110;
static const int64_t kFWMIOHIDDockSwipeType = 23;

static CFMachPortRef gTap = NULL;
static CFRunLoopSourceRef gTapSource = NULL;
static _Atomic bool gEnabled = false;
static _Atomic bool gFourFingerActive = false;

static CGEventRef FWMGestureTapCallback(
    CGEventTapProxy proxy,
    CGEventType type,
    CGEventRef event,
    void *userInfo
) {
    (void)proxy;
    (void)userInfo;

    if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
        if (gTap != NULL) {
            CGEventTapEnable(gTap, true);
        }
        return event;
    }

    if (!atomic_load_explicit(&gEnabled, memory_order_relaxed) ||
        !atomic_load_explicit(&gFourFingerActive, memory_order_relaxed)) {
        return event;
    }

    // The callback type is normally already 29/30, but field 55 is the private
    // "real" type used by WindowServer and makes this robust across wrappers.
    int64_t realType = CGEventGetIntegerValueField(event, kFWMRealEventTypeField);
    if (realType == 0) {
        realType = (int64_t)type;
    }

    if (realType == kFWMDockControlEvent) {
        // Only suppress actual DockSwipe gestures, not unrelated private events.
        int64_t hidType = CGEventGetIntegerValueField(event, kFWMGestureHIDTypeField);
        if (hidType == kFWMIOHIDDockSwipeType || hidType == 0) {
            return NULL;
        }
    }

    if (realType == kFWMGestureEvent) {
        return NULL;
    }

    return event;
}

bool FWMGestureBlockerStart(void) {
    if (gTap != NULL) {
        return true;
    }

    CGEventMask mask = ((CGEventMask)1ULL << kFWMGestureEvent) |
                       ((CGEventMask)1ULL << kFWMDockControlEvent);

    gTap = CGEventTapCreate(
        kCGSessionEventTap,
        kCGHeadInsertEventTap,
        kCGEventTapOptionDefault,
        mask,
        FWMGestureTapCallback,
        NULL
    );

    if (gTap == NULL) {
        return false;
    }

    gTapSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, gTap, 0);
    if (gTapSource == NULL) {
        CFRelease(gTap);
        gTap = NULL;
        return false;
    }

    CFRunLoopAddSource(CFRunLoopGetMain(), gTapSource, kCFRunLoopCommonModes);
    CGEventTapEnable(gTap, true);
    return true;
}

void FWMGestureBlockerStop(void) {
    atomic_store_explicit(&gFourFingerActive, false, memory_order_relaxed);
    atomic_store_explicit(&gEnabled, false, memory_order_relaxed);

    if (gTap != NULL) {
        CGEventTapEnable(gTap, false);
    }
    if (gTapSource != NULL) {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), gTapSource, kCFRunLoopCommonModes);
        CFRelease(gTapSource);
        gTapSource = NULL;
    }
    if (gTap != NULL) {
        CFRelease(gTap);
        gTap = NULL;
    }
}

void FWMGestureBlockerSetEnabled(bool enabled) {
    atomic_store_explicit(&gEnabled, enabled, memory_order_relaxed);
    if (!enabled) {
        atomic_store_explicit(&gFourFingerActive, false, memory_order_relaxed);
    }
}

void FWMGestureBlockerSetFourFingerActive(bool active) {
    atomic_store_explicit(&gFourFingerActive, active, memory_order_relaxed);
}

bool FWMGestureBlockerIsRunning(void) {
    return gTap != NULL;
}

#else
bool FWMGestureBlockerStart(void) { return false; }
void FWMGestureBlockerStop(void) {}
void FWMGestureBlockerSetEnabled(bool enabled) { (void)enabled; }
void FWMGestureBlockerSetFourFingerActive(bool active) { (void)active; }
bool FWMGestureBlockerIsRunning(void) { return false; }
#endif
