#ifndef CMultitouchShim_h
#define CMultitouchShim_h

#include <stdbool.h>
#include <stdint.h>

typedef struct {
    float x;
    float y;
} MTPoint;

typedef struct {
    MTPoint position;
    MTPoint velocity;
} MTVector;

typedef struct {
    int32_t frame;
    double timestamp;
    int32_t pathIndex;
    uint32_t state;
    int32_t fingerID;
    int32_t handID;
    MTVector normalizedVector;
    float zTotal;
    int32_t field9;
    float angle;
    float majorAxis;
    float minorAxis;
    MTVector absoluteVector;
    int32_t field14;
    int32_t field15;
    float zDensity;
} MTTouch;

// Runtime blocker for macOS' private Dock/WindowServer gesture events.
// This does not change the user's Trackpad preferences.
bool FWMGestureBlockerStart(void);
void FWMGestureBlockerStop(void);
void FWMGestureBlockerSetEnabled(bool enabled);
void FWMGestureBlockerSetFourFingerActive(bool active);
bool FWMGestureBlockerIsRunning(void);

#endif
