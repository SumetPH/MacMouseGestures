#import <CoreGraphics/CoreGraphics.h>

// Creates an event only; does not inject input.
CGEventRef _Nullable MMGCreateDockSwipe(uint32_t phase, double progress,
                                       double velocity, int axis, CGPoint location)
    CF_RETURNS_RETAINED;
