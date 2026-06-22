# Vendored TouchEvents

These files were copied from Hammerspoon revision
`08e93f679bb5d9b88d2e8bd493d964a133c89960`:

- <https://github.com/Hammerspoon/hammerspoon/tree/08e93f679bb5d9b88d2e8bd493d964a133c89960/extensions/eventtap>
- Upstream TouchEvents origin: Calf Trail Software, LLC, copyright 2010.

`TouchEvents.c`, `TouchEvents.h`, and the bundled `LICENSE.md` are distributed
under GPL version 2 or later. The IOHID headers retain Apple's license notices.
The code builds undocumented type-29 Quartz gesture events from serialized HID
data. It is isolated in the `CTouchEvents` SwiftPM target and is used only by
the explicit `touch-synthesis` private compatibility probe.

No compatibility with current or future macOS releases is claimed.
