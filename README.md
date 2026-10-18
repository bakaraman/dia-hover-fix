# dia-hover-fix

On macOS, hover stops working in [Dia](https://www.diabrowser.com) after you leave fullscreen. A typical case: you watch a video fullscreen on X or YouTube, then press Esc. After that, video controls, volume sliders and menus only open when you click. Mission Control (F3) or switching Spaces brings hover back until the next time.

`dia-hover-fix` is a small background helper that brings hover back automatically.

## What's going on

- **Trigger:** leaving fullscreen (the player's exit button or Esc) while the cursor is over the window. Entering fullscreen is fine.
- **Effect:** the page receives no `mousemove` at all, so `:hover`, `mouseenter` and hover menus stop. Clicks still arrive.
- **Cause:** the AppKit bug described in [electron/electron#54816](https://github.com/electron/electron/issues/54816). After a window style change with the cursor over the window, an `NSTrackingArea` with `NSTrackingActiveInActiveApp` stops receiving mouse moves. Removing the area and adding it again fixes it. Chromium builds this area in `BridgedContentView`'s `updateCursorTrackingArea` and only rebuilds it in `viewDidMoveToWindow`.

## Measurements

Measured on 19 October 2026 on a MacBook Pro (M4 Pro), macOS 27.0.1 (26A434), Dia 1.52 (Chromium 155). A test page counted `mousemove` events while a separate process sampled the real cursor position every 50 ms.

| Action | Mouse moves reaching the page afterwards |
|---|---|
| Leave fullscreen with Esc or the exit button (4 tries) | 0 for 5 to 13 s while the cursor kept moving |
| Enter fullscreen | normal after the animation |
| Activate another app, then Dia again (same Space) | still 0 |
| Show a 40×40 px window from another process under the cursor for 150 ms | normal again |
| Notification banner, overlay window, context menu, system alert | normal |

## The workaround

While Dia is the active app, `dia-hover-fix` reads the bounds of Dia's windows on screen four times a second. A page entering or leaving fullscreen changes the layout of Dia's large windows. When the layout changes and settles with the cursor over Dia, the helper shows a 40×40 px, 4% grey window that accepts mouse events under the cursor for 150 ms. It does this twice, 1 second apart. The window server sees the cursor leave Dia's window and come back, and mouse moves resume.

- No permissions are needed: window bounds, cursor position and mouse button state are public.
- It does nothing while a mouse button is held or while Dia is in the background.
- Memory footprint is about 10 MB. It uses no CPU while Dia isn't the active app.

## Install

Needs the Xcode command line tools (`swiftc`).

```bash
git clone https://github.com/bakaraman/dia-hover-fix
cd dia-hover-fix
./install.sh
```

The helper starts at login. Each layout change and flash is logged to `~/Library/Logs/dia-hover-fix.log`.

## Uninstall

```bash
./uninstall.sh
```

## Limitations

- It only watches Dia (`company.thebrowser.dia`). Other Chromium based browsers may have the same bug. To try one, change `diaBundleID` in `dia-hover-fix.swift`.
- It has been tested on one Mac with macOS 27.0.1. In a quick automated test, Google Chrome 155 did not show the problem, so it may depend on how Dia handles fullscreen inside a window that is already fullscreen.
- This is a workaround. The real fix belongs in Chromium or Dia (rebuild the cursor tracking area after fullscreen transitions) or in AppKit.

## License

MIT
