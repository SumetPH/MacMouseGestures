# Spaces Gesture Probe

A macOS experiment for mapping right-button horizontal dragging to Spaces
navigation. Its public modes and opt-in private compatibility probes remain
intentionally separate:

- `probe`: posts pixel-based horizontal `CGEvent` scroll events with continuous,
  scroll-phase, momentum-phase, and scroll-count fields. It does **not** send a
  keyboard shortcut, so a live Spaces transition cannot be confused with the
  fallback.
- `fallback`: shows drag progress and sends Control-Left/Right on release.
  `hybrid` runs both behaviors for convenience after the experiment.

The default `probe`, `fallback`, and `hybrid` modes use no private framework,
undocumented event type, or symbol lookup. The explicitly named private modes
are compatibility experiments for personal use and are not App Store safe.

## Build and run

Requirements: macOS 13+, Xcode Command Line Tools, and Accessibility permission.

```bash
swift test
swift build
.build/debug/mac-mouse-gesture --mode probe
```

To build a launchable app bundle instead, run:

```bash
./scripts/build-app.sh
open ".build/app/Mac Mouse Gesture.app"
```

The script builds the release configuration by default. Pass `debug` as its
first argument for a debug bundle. It ad-hoc signs the app locally; set
`CODE_SIGN_IDENTITY` when a specific signing identity is required.

On first run, allow the executable or Terminal in **System Settings > Privacy &
Security > Accessibility**, then launch it again. Right-button clicks without a
qualifying horizontal drag are replayed as normal clicks.

Useful modes:

```bash
# Isolated public-API experiment: no fallback shortcut
.build/debug/mac-mouse-gesture --mode probe --scroll-scale 1

# Reliable fallback with the small progress overlay
.build/debug/mac-mouse-gesture --mode fallback

# Scroll experiment plus fallback on release
.build/debug/mac-mouse-gesture --mode hybrid --threshold 100
```

### Private live-drag investigation

The first private-API gate is passive capture only; it does not synthesize or
block any gesture:

```bash
.build/debug/mac-mouse-gesture --mode native-record | tee native-record.log
```

Grant Terminal both Accessibility and Input Monitoring, restart the command,
then perform one complete native three-finger Spaces swipe on each display and
stop with Control-C. Records named `native_gesture_raw` contain serialized
Quartz events for the next replay gate. See `docs/spec-private-spaces-drag.md`
for the constraints.

After a capture contains `native_gesture_raw`, replay that exact private event
stream once with:

```bash
.build/debug/mac-mouse-gesture --mode private-replay \
  --replay-file native-record.log
```

Replay starts after two seconds and exits when all events are posted. Put the
pointer on the display used for capture and ensure another Space exists in the
recorded direction. This is an undocumented compatibility experiment; stop if
the desktop enters an inconsistent transition state.

Serialized replay is rejected on macOS 26.5.1 even though Quartz reports that
every event was posted. A second risk gate creates a fresh private swipe event
using the vendored TouchEvents serializer:

```bash
.build/debug/mac-mouse-gesture --mode touch-synthesis --direction left
.build/debug/mac-mouse-gesture --mode touch-synthesis --direction right
```

The process waits two seconds, posts `began`, waits 150 ms, posts `ended`, then
exits. Put the pointer on a display that has another Space in the requested
direction. A successful run prints two `touch_synthesis_posted` records with
`cg_type` 29. Whether the desktop actually switches must still be observed;
posting successfully does not prove WindowServer accepted the gesture.

Runtime result on macOS 26.5.1 (Build 25F80): both directions created and posted
type-29 `began`/`ended` events, but Spaces did not move. This gate is therefore
rejected for the legacy TouchEvents swipe schema.

This does not reject every private in-process gesture path. Inspection of the
installed BetterMouse 1.6.8840 binary shows direct private SkyLight linkage,
IOHID event-system APIs, and embedded names for `FluidTouchGesture`,
`BoundaryScroll`, and `Virtual Gesture`. BetterMouse's working behavior is
therefore evidence that a newer private HID gesture schema may be accepted with
Accessibility alone. It is not equivalent to the 2010 TouchEvents serializer.

The accepted stream was identified as type 30, subtype `0x17`, with explicit
may-begin/began/changed/ended phases and signed progress. Run the interactive
mouse-driven implementation with:

```bash
.build/debug/mac-mouse-gesture --mode private-drag
```

Hold the right button and drag horizontally. Progress follows mouse displacement
at approximately 120 Hz and may reverse while held. A complete animation uses
52% of the width of the display where the drag began, calibrated from the
working BetterMouse capture. A slow release commits only after crossing half of
that distance. A coherent release faster than 900 pixels/second receives a
200 ms momentum projection and commits only when the projected position crosses
halfway; left-right shaking and moderate movement near the original Space
therefore cancel. Cancel always discards release momentum and settles with
smoothstep. A committed flick retains momentum and uses ease-out. A click or
tiny movement remains a normal right click. The event location stays on the
display where the gesture began.

Gesture frames are posted at approximately 120 Hz, while diagnostic progress
logs are sampled at 10 Hz so terminal JSON encoding and flushing do not stall
the event tap. A slow release uses a smoothstep settle with zero initial
velocity; an actual flick keeps the faster ease-out settle.

The `fluid_drag_ended` log includes `release_delta_x`, `release_velocity_x`,
`projected_delta_x`, `directional_coherence`, and `settle_interrupted`. Every
started fluid gesture is explicitly ended, including when another gesture begins
during settling.

`--threshold` controls the public fallback/hybrid modes. To tune private-drag
animation sensitivity and its halfway point, pass an explicit full-transition
distance, for example `--fluid-distance 1200`. Larger values make the live
animation move more slowly.

Disable BetterMouse's competing right-button mapping while testing so both apps
do not emit gestures for the same physical drag.

Use `--no-overlay` to disable the overlay. A negative `--scroll-scale` reverses
the generated scroll direction.

## Reproducible live-animation check

1. Ensure macOS has at least two Spaces and that the trackpad's native
   three-finger swipe moves the desktop interactively.
2. Start `--mode probe`; this is important because it never sends Ctrl+Arrow.
3. Hold the right mouse button and drag horizontally past the displayed 100%.
4. While still holding, observe whether the current Space follows the pointer.
5. Release, then press `Y` if it moved live or `N` if it did not.
6. Save stdout and find `spaces_live_animation_observation`. Its `gesture_id`
   correlates with all `scroll_posted` records for that trial.

Example fields are `horizontal_pixels`, `is_continuous`, `scroll_phase`
(`1` began, `2` changed, `4` ended), `momentum_phase` (`0` none), and
`scroll_count`. This proves what the process posted and read back from each
event; it does not claim that WindowServer accepted it as a touch gesture.

## Finding

The public API surface can synthesize continuous scroll-wheel input, but it
does not provide a supported way to synthesize the device-level multi-touch
gesture stream that drives the system's interactive Spaces transition.
Accordingly, this prototype is expected to scroll the application under the
pointer (where horizontal scrolling is supported), not drag Spaces live.

This conclusion has two boundaries:

1. Core Graphics exposes construction/posting for `scrollWheel` Quartz events
   and fields that describe continuous pixel scrolling and phases. Its public
   Quartz event-type list has no begin-gesture, end-gesture, or swipe event type.
2. AppKit exposes incoming swipe events and lets an app track scroll events to
   implement fluid feedback **inside that app**. AppKit documents delivery to
   the relevant responder/view; it does not expose an API that asks Mission
   Control to begin, update, and commit/cancel a Spaces transition.

Setting `scrollWheelEventIsContinuous`, `scrollWheelEventScrollPhase`, or
`scrollWheelEventMomentumPhase` annotates a scroll event. Those values do not
add touch contacts, a gesture recognizer identity, or a privileged system
gesture target. Therefore they are worth testing, but they are not a public
contract for native Spaces dragging.

The actual observation remains machine/OS-setting dependent and must be
recorded with the procedure above. This repository's automated environment
could compile and test the event construction, but could not visually observe
a logged-in WindowServer session; it therefore does not fabricate a `Y`/`N`
result.

The target-machine observations show that public scroll fields and the legacy
TouchEvents swipe schema do not work. BetterMouse capture revealed an accepted
type-30 schema: both exact replay and events constructed from its raw fields
moved Spaces in both directions. `private-drag` applies that schema
interactively; `fallback` remains the stable public-path option.

## Public references

- [CGEvent overview and posting APIs](https://developer.apple.com/documentation/coregraphics/cgevent)
- [CGEventType public event list](https://developer.apple.com/documentation/coregraphics/cgeventtype)
- [Continuous scroll field](https://developer.apple.com/documentation/coregraphics/cgeventfield/scrollwheeleventiscontinuous)
- [CGEventField scroll and phase keys](https://developer.apple.com/documentation/coregraphics/cgeventfield)
- [AppKit fluid swipe tracking for an app's own UI](https://developer.apple.com/documentation/appkit/nsevent/trackswipeevent(options:dampenamountthresholdmin:max:usinghandler:))
- [NSEvent delivery model](https://developer.apple.com/documentation/appkit/nsevent)
- [Accessibility trust check](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions)

## Project layout

- `GestureCore`: deterministic right-drag recognition, covered by unit tests.
- `MacMouseGesture`: event tap, synthetic event posting, structured logs,
  shortcut fallback, and optional overlay.
- `Vendor/TouchEvents`: isolated GPL-2.0-or-later TouchEvents serializer plus
  Apple Public Source License headers imported from Hammerspoon; see its README.
