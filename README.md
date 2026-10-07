# Fling

A four-finger window manager for macOS.

Move, resize, and restore windows from your trackpad.

## Install

[Download Fling](https://github.com/jafupy/fling/releases/latest), unzip it, and move **Fling.app** to Applications. Open it and allow Accessibility access.

The download is for Apple silicon Macs running macOS 14 or later. It is ad hoc signed, but not notarized. If macOS blocks it, use **System Settings → Privacy & Security → Open Anyway**.

## Use

Point at a window, then use four fingers:

- Fling towards an edge to snap there.
- Pause, reverse, or fling again to step through thirds, halves, and centre positions.
- Pinch or stretch to change size.
- Scrub left–right–left to restore the previous size and position.
- Pinch past the smallest size, then lift to send the window to the Stage Manager sidebar.

Open Fling again for Settings. **General → Open at login** starts it when you sign in. There is no menu bar item.

## Build

With Xcode installed:

```sh
./scripts/package-app.sh
open .build/Fling.app
```

The app and a zip are written to `.build/`. Raw trackpad input uses macOS’ private MultitouchSupport framework.

## License

[GPL-3.0-or-later](LICENSE).
