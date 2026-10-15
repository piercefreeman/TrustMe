# TrustMe demo videos

The two full-screen animations used to record TrustMe's demo videos. Both start from a
capture of your current wallpaper (no icons or windows) and cover the whole screen,
menu bar included.

```sh
./popups.sh   # the problem: system permission popups, faster and faster until the screen is buried
./drag.sh     # the fix: TrustMe's window, System Settings, and the drag into the list
```

Keys: **Esc** quits, **R** replays.

Options (both scripts):

- `--wallpaper <path>` use a specific image instead of capturing the desktop
- `--saved-wallpaper` skip capture and use `Assets/wallpaper.png` (the last capture)
- `--app <path.app>` / `--name <name>` the app shown (defaults to `../build/TrustMe.app`, from `Scripts/build-demo.sh`)
- `--hold <seconds>` (popups only) how long the bare desktop shows before the first popup; default 3.5
- `--once` (drag only) play one pass instead of looping

Capturing the wallpaper needs Screen Recording for your terminal; without it the last
saved capture in `Assets/` is used, then the system's desktop picture. `Assets/` is
not checked in.

## What each demo shows

**Popups** (`Sources/PopupStorm`). The bare desktop holds for a few seconds, then a
single Accessibility prompt appears in the center. More follow: two seconds apart at
first, shrinking by 20% each time until they arrive every few hundredths of a second.
There are 17 prompt types (screen recording, camera, microphone, automation, location,
local network, a keychain password prompt and so on), dealt from a shuffled deck so
they don't repeat in runs. It stops once the screen is fully covered plus a few more.

**Drag** (`Sources/DragDemo`). TrustMe's permissions window opens with nothing granted.
A scripted pointer clicks Allow on Accessibility; the window slides aside as System
Settings opens on Privacy & Security › Accessibility; TrustMe's glass band docks beneath
it. The pointer picks the app up from the band and drags it into the list (the list
highlights and the cursor gets its green "+"), a Touch ID prompt is accepted, TrustMe
appears in the list and its switch turns on. The band turns green, closes, and the
TrustMe window comes forward showing Accessibility granted. Then it loops.

## How the system side is simulated

Nothing touches real permissions or the real System Settings. Every piece of "system"
UI is drawn by the demo, so it looks the same and runs the same every time.

- **The desktop.** The Dock draws each display's wallpaper in its own desktop-level
  window. We find that window with `CGWindowListCopyWindowInfo` and capture just it with
  `screencapture -l <id>`, which gives the picture without icons or windows. A copy is
  saved to `Assets/wallpaper.png` as a fallback. A static menu bar is drawn on top,
  sized to the real one (taller on notched displays).

- **Covering the real screen.** All demo windows sit above `.screenSaver` level, so they
  cover the Dock, the menu bar and other apps. The app runs as an accessory (no Dock
  icon), and Esc is caught with a local key monitor on a borderless window that is
  allowed to become key.

- **System alerts** (`DemoSupport/SystemAlert.swift`). A SwiftUI recreation of a Sequoia
  alert: 260pt wide, 64pt icon with a small permission badge, bold centered title, small
  message, full-width rounded buttons (side by side when two short ones fit, stacked
  otherwise, like `NSAlert`). The background is a real `NSVisualEffectView` with a
  rounded mask, so it blurs whatever is underneath. The popup storm draws every alert in
  one full-screen window, blurring within the window; the Touch ID prompt in the drag
  demo is its own window, blurring what's behind it.

- **Placing the popups.** A coarse grid tracks which parts of the screen are already
  covered. Each new popup tries 24 random spots and takes the one that covers the most
  bare desktop. Early popups land scattered, later ones fill the gaps, and the screen
  ends up completely buried rather than piling up in the middle.

- **System Settings** (`DragDemo/SettingsPane.swift`). A real titled `NSWindow` (so it
  gets genuine traffic lights, shadow and corner radius) with SwiftUI content: a
  vibrant sidebar with search, your account name and the usual panes, and the
  Accessibility list with apps you actually have installed. The list switch, drop
  highlight and new-row animation are drawn by hand so they can be driven by the script.

- **TrustMe itself.** The glass band, drag chip, theme, buttons and placement logic are
  TrustMe's real code, pulled in from the parent package with `@testable import` (so this
  needs a debug build, which is what the scripts produce). The permissions window
  mirrors TrustMe's `PermissionsView` layout but reads from a scripted state instead of
  the live permission status, so we control what shows as granted.

- **The pointer.** The real cursor is hidden. A transparent full-screen window on top
  draws the system cursor images (arrow, open hand, closed hand, drag-copy), the
  dragged app chip and click ripples. Positions of the Allow button and the list come
  from SwiftUI geometry, converted to screen coordinates, so the pointer hits them
  wherever the windows end up.

- **The script.** The drag demo is one async sequence of moves, clicks and pauses
  (`Director.play()` in `DragDemo/main.swift`). Replaying cancels the task and starts
  from a clean state.

## Layout

```
Package.swift            depends on the TrustMe package one level up
popups.sh, drag.sh       build and launch
Assets/wallpaper.png     last wallpaper capture (gitignored)
Sources/DemoSupport      wallpaper capture, desktop + menu bar, system alert, windows and keys
Sources/PopupStorm       the popup storm
Sources/DragDemo         state, TrustMe window, System Settings, pointer overlay, script
```
