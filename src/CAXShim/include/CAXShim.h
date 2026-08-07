#pragma once

#include <ApplicationServices/ApplicationServices.h>

// Private, but present since the 10.x days and relied on by every window manager
// on macOS. It maps an accessibility element to the CGWindowID the WindowServer
// knows the window by, which is the only reliable way to line AX windows up with
// the output of CGWindowListCopyWindowInfo.
//
// Without it the two lists have to be matched on PID plus title plus bounds,
// which breaks the moment two windows of one app share a title.
extern AXError _AXUIElementGetWindow(AXUIElementRef element, CGWindowID *windowID);
