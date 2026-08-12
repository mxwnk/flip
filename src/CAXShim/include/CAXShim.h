#pragma once

#include <ApplicationServices/ApplicationServices.h>
#include <stdbool.h>

// Private, and the only reliable way to match an AX window against
// CGWindowListCopyWindowInfo. `weak_import` matters: linked strongly, a system
// that does not export it kills the process before main runs.
extern AXError _AXUIElementGetWindow(AXUIElementRef element, CGWindowID *windowID)
    __attribute__((weak_import));

// Swift cannot compare an imported C function against NULL.
static inline bool FlipCanReadWindowIDs(void) {
    return _AXUIElementGetWindow != NULL;
}

// Absent symbol becomes a window without an id, not a dead app.
static inline AXError FlipReadWindowID(AXUIElementRef element, CGWindowID *windowID) {
    if (_AXUIElementGetWindow == NULL) { return kAXErrorFailure; }

    return _AXUIElementGetWindow(element, windowID);
}
