# Mac Mouse Gestures

A macOS menu bar utility that maps mouse gestures to desktop navigation.

- Hold the right mouse button and drag left or right to switch Spaces with a
  live desktop transition.
- Hold the right mouse button and drag up or down to open Mission Control or
  Application Windows.
- Assign Mission Control actions to mouse buttons 3 and 4.
- Use the menu bar item to enable or disable gestures and toggle launch at
  login.
- Optionally hide the menu bar icon; opening the app temporarily restores the
  icon and opens its popup.

This is an experimental personal utility. It uses Accessibility event taps,
synthesized input, and undocumented Dock/gesture event behavior. It is not App
Store safe and may need updates when macOS changes its private event handling.

## Requirements

- macOS 13 or newer
- Xcode Command Line Tools
- Accessibility permission for the built app or for the terminal running it
- A mouse with a right button; mouse buttons 3 and 4 are optional for custom actions

## Build

Run from the repository root:

```bash
swift build
```

For local development:

```bash
./scripts/dev-app.sh
```

To create a launchable app bundle:

```bash
./scripts/build-app.sh
open "dist/Mac Mouse Gestures.app"
```

The bundle script builds release by default. Pass `debug` for a debug bundle:

```bash
./scripts/build-app.sh debug
```

The script signs with an Apple Development certificate by default so
Accessibility permission can persist across rebuilds. Override the identity when
needed:

```bash
CODE_SIGN_IDENTITY="-" ./scripts/build-app.sh
```

## First Run

1. Build and launch the app.
2. Open **System Settings > Privacy & Security > Accessibility**.
3. Enable permission for `Mac Mouse Gestures.app`, or for the terminal app if
   running through `swift run`.
4. Quit and launch the app again.

The app runs as a menu bar accessory. Click the mouse icon in the menu bar to
toggle gestures, assign actions to mouse buttons 3 and 4, launch at login,
hide the menu bar icon, or quit. When the icon is hidden, open the app to
temporarily show the icon and popup.

Click a Mouse button field and press the physical mouse button to detect the
button number reported by that device. Then choose Mission Control or
Application Windows from the action menu.

## Gestures

| Gesture | Action |
| --- | --- |
| Right-button drag left | Switch one Space left |
| Right-button drag right | Switch one Space right |
| Right-button drag up | Open Mission Control |
| Right-button drag down | Open Application Windows |
| Mouse button 3 | Configured action |
| Mouse button 4 | Configured action |

Short right-button clicks are replayed as normal right clicks.
Mouse buttons set to No Action keep their normal system behavior.

## Notes and Limits

- The Spaces animation path uses private gesture event fields. It is based on
  observed macOS behavior, not a public Apple contract.
- Mission Control uses a private Dock notification for the up/down gesture.
- Synthetic events are marked internally so the app does not process its own
  posted input.
- Behavior can vary by macOS version, desktop settings, display setup, and other
  mouse/gesture tools running at the same time.
- Disable competing right-button mappings in other utilities while testing.

See [docs/spec-private-spaces-drag.md](docs/spec-private-spaces-drag.md) for
the investigation notes behind the private Spaces gesture path.

## Project Layout

- `Sources/GestureCore`: deterministic gesture tracking and fluid gesture
  planning.
- `Sources/MacMouseGestures`: menu bar app, event tap, event posting, settings,
  and logging.
- `Assets`: app icon source.
- `scripts`: development and app-bundle build helpers.
- `docs`: implementation notes and private gesture investigation.

## Security and GitHub Publishing Check

Before publishing, this repository was checked for:

- committed secret patterns such as API keys, passwords, tokens, and private key
  headers;
- accidental local build output in `.build/` and `dist/`;
- macOS/editor noise such as `.DS_Store`;
- external runtime dependencies that need a package audit.

Current findings:

- No secret pattern was found in the working tree.
- The Swift package has no third-party package dependencies.
- `.build/`, `.swiftpm/`, `dist/`, logs, `.env` files, key/certificate files,
  and `.DS_Store` are ignored.
- The code intentionally uses Accessibility privileges, event taps, synthetic
  input, private `CGEventField` raw values, and `CoreDockSendNotification`.
  Documenting that risk is important for public release.

If a real signing identity, provisioning file, key, or token is ever committed,
rotate it before rewriting history or deleting it from the repo.
