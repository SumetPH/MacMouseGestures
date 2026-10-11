#import "MacMouseGesturesBridge.h"
#import <Foundation/Foundation.h>
#import <dlfcn.h>

// Private HIDEvent interface and field IDs from Apple's HID event headers.
// macOS 27 consumes the embedded HID payload instead of CGEvent gesture fields.
@interface NSObject (MMGHIDEvent)
- (instancetype)initWithType:(uint32_t)type timestamp:(uint64_t)timestamp senderID:(uint64_t)senderID;
- (void)setOptions:(uint32_t)options;
- (void)setIntegerValue:(NSInteger)value forField:(uint32_t)field;
- (void)setDoubleValue:(double)value forField:(uint32_t)field;
- (void)appendEvent:(id)event;
@end

CGEventRef MMGCreateDockSwipe(uint32_t phase, double progress, double velocity,
                             int axis, CGPoint location) {
  if (!isfinite(progress) || !isfinite(velocity) || (axis != 1 && axis != 2)
      || (phase != 1 && phase != 2 && phase != 4 && phase != 8)) return NULL;
  static void (*attach)(CGEventRef, id);
  static Class eventClass;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    // Keep the framework loaded for the lifetime of its classes/function pointer.
    void *framework = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY);
    if (framework) attach = dlsym(framework, "SLEventSetIOHIDEvent");
    eventClass = NSClassFromString(@"HIDEvent");
  });
  if (!attach || !eventClass) return NULL;
  id swipe = [[eventClass alloc] initWithType:23 timestamp:0 senderID:0];
  if (!swipe) return NULL;
  const uint32_t dockSwipeBase = 23 << 16;
  [swipe setOptions:phase << 24];
  [swipe setIntegerValue:axis forField:dockSwipeBase | 1];
  [swipe setIntegerValue:3 forField:dockSwipeBase | 5]; // DockPrimary flavor
  [swipe setDoubleValue:progress forField:dockSwipeBase | 2];
  if (phase == 4 || phase == 8) {
    id exit = [[eventClass alloc] initWithType:9 timestamp:0 senderID:0];
    if (!exit) return NULL;
    const uint32_t velocityBase = 9 << 16;
    [exit setDoubleValue:velocity forField:velocityBase];
    [exit setDoubleValue:velocity forField:velocityBase | 1];
    [exit setDoubleValue:0 forField:velocityBase | 2];
    [swipe appendEvent:exit];
  }
  CGEventRef event = CGEventCreate(NULL);
  if (!event) return NULL;
  CGEventSetType(event, 30);
  CGEventSetLocation(event, location);
  attach(event, swipe);
  return event;
}
