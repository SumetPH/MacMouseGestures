# Spec: Private Spaces Live Drag Probe

## Objective

Build a personal-use macOS 26.5.1 experiment that maps right-button horizontal
mouse dragging to the same interactive Spaces transition as a native
three-finger trackpad swipe. The desktop on the display containing the pointer
must follow drag progress continuously, then commit or cancel on release.

This is an opt-in private-API experiment. The existing public-API `probe` and
working shortcut `fallback` remain available.

## Success Criteria

1. Right-drag updates the Spaces transition continuously before mouse release.
2. Reversing the mouse reverses transition progress.
3. A slow release past halfway commits; release below it cancels. A coherent
   fast flick may commit before halfway.
4. The affected Space belongs to the display containing the pointer when the
   gesture begins.
5. The program runs without root and without disabling SIP, using only
   Accessibility and Input Monitoring approval.
6. If criteria 1–5 cannot be met, the experiment logs the exact failed boundary
   (capture, construction, posting, targeting, or system rejection) and leaves
   fallback behavior intact.

## Risk-First Implementation

1. `native-record`: observe a real three-finger Spaces swipe and log the raw
   Quartz/AppKit event types, phases, deltas, source fields, and pointer display.
2. `private-replay`: replay one recorded gesture without mouse mapping and
   confirm whether WindowServer/Dock accepts synthetic events.
3. `private-drag`: translate incremental mouse distance into begin/change/end or
   cancel events, retaining the display selected at gesture start.
4. Harden event-loop ordering, synthetic-event markers, cancellation, and event
   tap recovery. Keep `fallback` as the safe mode.

Each step is a gate. Do not implement the next step until the current step has
runtime evidence on the target machine.

### Gate observations on macOS 26.5.1

- Native capture produced type-29 serialized events.
- Reposting the captured bytes preserved timing and reported success, but
  Spaces did not respond. Event provenance or device identity is therefore part
  of the acceptance boundary.
- A separate `touch-synthesis` gate created fresh begin/end swipes in both
  directions using the GPL-2.0-or-later TouchEvents serializer. Quartz reported
  type 29 for both posted events, but Spaces did not move.
- The legacy TouchEvents construction/posting gate is rejected. This result
  does not cover newer IOHID `FluidTouchGesture` or Dock swipe schemas.

## Decision

Reopen the private in-process investigation using BetterMouse 1.6.8840 as a
runtime oracle. Its installed main binary links private SkyLight directly,
imports IOHID event-system APIs, and contains the names `FluidTouchGesture`,
`BoundaryScroll`, and `Virtual Gesture`. Its documented native swipe follows
the cursor while requiring Accessibility but not Input Monitoring.

The next gate is to capture one BetterMouse-generated left and right gesture
with the listen-only recorder and compare its serialized schema with the native
trackpad and legacy TouchEvents payloads. Do not infer a requirement for a
virtual driver or privileged helper unless this newer in-process path is also
rejected by runtime evidence.

### Type-30 gate result

- BetterMouse emitted 108 type-30 events across left and right gestures. Each
  serialized event was 232 bytes with subtype `0x17`, horizontal motion `1`,
  lifecycle phases `0x80/1/2/4`, and signed progress approaching `±4/3`.
- Replaying the stream moved Spaces in both directions.
- Constructing the same fields from scratch, without a replay file, also moved
  Spaces in both directions.
- `private-drag` maps right-button displacement into the accepted stream,
  throttles updates to approximately 120 Hz, locks routing to the start display,
  and always closes an active stream before another begins. By default a full
  transition uses 52% of the start display width, matching the working
  BetterMouse capture, and `--fluid-distance` can override that distance. A slow
  release commits after halfway. A coherent release above 900 pixels/second
  receives a 200 ms momentum projection and commits only when that projected
  position crosses halfway, rejecting left-right shaking and moderate movement
  near the original Space. Cancel discards momentum and uses smoothstep; a
  committed flick retains momentum and uses cubic ease-out. Gesture posting
  remains approximately 120 Hz, but
  diagnostic progress output is sampled at 10 Hz to keep terminal I/O out of
  the event-tap hot path.

## Tech Stack and Structure

- Swift 6.3 / Swift Package Manager
- AppKit, CoreGraphics, ApplicationServices
- Private symbols or raw event fields loaded only by the private modes
- `GestureCore`: deterministic direction/progress/commit logic
- `MacMouseGestures`: capture, event construction, posting, logs, and overlay
- `Tests`: pure sequence and gesture-state regression tests

No third-party binary dependency is planned for the capture slice. A small
source dependency may be proposed later only if its exact event schema and
license are reviewed first.

## Commands

```bash
swift test
swift build
.build/debug/MacMouseGestures --mode native-record
.build/debug/MacMouseGestures --mode private-replay
.build/debug/MacMouseGestures --mode private-drag
```

## Code Style and Testing

Use `swift format`. Keep raw/private constants behind named adapters rather than
scattering numeric fields through the controller. Pure gesture mapping and
event-sequence construction require unit tests. WindowServer acceptance needs a
manual runtime test and structured log because it cannot be asserted in SwiftPM
tests.

## Boundaries

### Always

- Preserve the public `probe` and `fallback` modes.
- Mark every private symbol/field and log the macOS build number.
- Provide a cancellation path so a failed experiment cannot leave modifiers,
  mouse buttons, or a partial transition active.
- Test on the display containing the pointer at gesture start.

### Ask first

- Add a third-party source or binary dependency.
- Require code signing entitlements beyond Accessibility/Input Monitoring.
- Change the experiment to inject at a lower HID/device layer.

### Never

- Disable SIP, run as root, install a privileged helper, or modify system files.
- Ship private mode as App Store/distributable functionality.
- Claim success from event-post logs alone; the desktop must visibly track.

## Known Risks

- Gesture event layouts are undocumented and may differ on macOS 26.5.1.
- Event taps may expose AppKit gesture summaries but not the underlying
  multi-touch contacts or display-routing metadata.
- Dock/WindowServer may reject synthetic gesture events based on provenance even
  when the process can construct and observe them.
- “Displays have separate Spaces” changes routing semantics; capture must retain
  the pointer display selected at gesture start.

## Open Questions Resolved by Runtime Evidence

- Which raw event types and fields represent begin/change/end/cancel?
- Does Input Monitoring expose the native stream at the session/HID tap?
- Does replay preserve provenance sufficiently for Dock/WindowServer?
- Is display targeting encoded in the event or inferred from pointer location?
