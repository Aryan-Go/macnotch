# MacNotch

A Dynamic-Island-style overlay for the MacBook notch. It hides in the notch,
drops down a live "now playing" card when your track changes, and expands into a
full music controller (plus a small system dashboard) when you hover over it.

Built from scratch with AppKit + SwiftUI. No Xcode project, no third-party app
frameworks — just Swift Package Manager.

---

## What it does

- **Hides in the notch.** When idle, the panel is exactly the size of the
  hardware notch and painted black, so it is invisible.
- **Live activity peek.** When the track changes, a compact card slides out below
  the notch with the album art, title, artist and an animated equalizer.
- **Two-stage hover.** A glance at the notch shows a compact peek card; push the
  cursor down onto it and the full panel springs open.
- **Music controls.** Album art, title/artist/album, a live scrubbable progress
  bar, play/pause, previous/next, shuffle, repeat, and system volume.
- **Works with any player.** Apple Music, Spotify, TIDAL, browsers — anything
  that reports to the system Now Playing interface.
- **Home tab.** Clock, date, battery ring, and quick actions for Dark Mode, Mute
  and Sleep.
- **Briefs tab.** At-a-glance weather, your Stocks watchlist, and recent
  notifications — read from the data the Weather, Stocks and Notification Center
  apps already keep on your Mac.
- **Menu bar item.** A small item to open the notch or quit.

---

## How it works

### 1. It's just a window pinned to the notch

macOS does not have a real "Dynamic Island" API. Every notch app is the same
trick: a borderless, transparent, non-activating `NSPanel` parked on top of the
screen at the notch, hosting a SwiftUI view.

- `Notch/NotchPanel.swift` — the panel. `styleMask: [.borderless,
  .nonactivatingPanel]`, `level = .screenSaver` (so it draws over the menu bar),
  `collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]`
  (so it follows you across Spaces and survives fullscreen).
- `Notch/NotchGeometry.swift` — finds the notch. macOS 12 added
  `NSScreen.safeAreaInsets.top` (the notch height) and
  `auxiliaryTopLeftArea` / `auxiliaryTopRightArea` (the free strips either side
  of the notch). Notch width = screen width − left area − right area. If those
  are `nil` there is no notch (external display), and it falls back to a
  centred bar under the menu bar.
- `Notch/NotchShape.swift` — draws the island silhouette: concave "ears" at the
  top that merge into the hardware notch, and convex rounded corners at the
  bottom. It's an animatable `Shape`, so the size change springs smoothly.

Because the panel's top edge sits exactly at the top of the screen and the shape
is filled black, the collapsed state is pixel-identical to the notch itself.

### 2. Hover, peek, expand

The panel is sized to the largest state it can ever reach, but while it is idle
it has `ignoresMouseEvents = true`, so clicks pass straight through to whatever
is underneath. Hover is detected with `NSEvent.addGlobalMonitorForEvents`
(`Notch/NotchController.swift`):

- Cursor enters the notch strip → show the compact **peek** card.
- Cursor pushed down onto the card → expand (`ignoresMouseEvents = false`).
- Cursor leaves it all → collapse.
- Click on the notch strip → pin it open; click away → close.

Splitting hover into two stages means a passing glance shows you what's playing
without the whole panel jumping open, while deliberately moving onto the card
opens the full player. On a track change the controller also shows the peek card
by itself and auto-dismisses it after a few seconds.

### 3. Music, without a public API

Reading Now Playing state from another app used to require the private
`MediaRemote.framework`. Since macOS 15.4, direct use of it from an app process
is blocked by an entitlement check.

The workaround (pioneered by
[**ungive/mediaremote-adapter**](https://github.com/ungive/mediaremote-adapter))
exploits the fact that Apple's own binaries are entitled — `/usr/bin/perl` reports
the bundle id `com.apple.perl`, so it is allowed to talk to MediaRemote. A tiny
helper framework is `dlopen`ed by a Perl script, which streams now-playing
metadata to stdout as JSON and accepts playback commands.

That helper is **vendored into this repo** (BSD-3-Clause, see Credits):

- `Sources/MacNotch/Resources/mediaremote-adapter.pl` — the Perl shim.
- `Sources/MacNotch/Resources/MediaRemoteAdapter.framework` — the universal
  (arm64 + x86_64) helper it loads.

`Media/MediaRemoteAdapter.swift` spawns and talks to that script;
`Media/MusicManager.swift` merges the JSON stream into a `NowPlaying` model and
publishes it to the UI. Controls are media-remote commands (`send`, `seek`).

### 4. Everything else

- **Volume** — `System/SystemAudio.swift` reads/writes the default output device
  through CoreAudio, so the slider is instant and reflects changes made anywhere.
- **Battery / clock / dark mode / lock** — `System/SystemStats.swift` uses
  IOKit's power sources API. Locking has no public API, so it calls
  `SACLockScreenImmediate` from the private `login.framework` (resolved with
  `dlopen`/`dlsym` at runtime, since the binary lives in the dyld shared cache).
  That is the call the system's own UI uses, and it brings up the real lock
  screen rather than just blanking the display.

### 5. Briefs, from the apps you already have

The Briefs tab has no third-party services and no API keys. Each of its three
feeds reads data an Apple app has already put on this Mac:

- **Weather** — `Modules/WeatherProvider.swift`. WeatherKit needs a paid
  developer entitlement, and the Weather app's own on-disk cache is an
  undocumented binary format. So the tab reuses the short-lived WeatherKit token
  the Weather app and its widget keep in
  `~/Library/Containers/com.apple.weather[.widget]/Data/Library/Preferences`, plus
  a cached request URL from the Weather app's `Cache.db` (which already carries
  the coordinates, timezone and client metadata the service expects). It then
  calls Apple's own `weatherkit.apple.com` asking for JSON. If both stored tokens
  have expired, the card tells you to open the Weather app once.
- **Stocks** — `Modules/StocksProvider.swift`. The Stocks widget caches its
  watchlist quotes as JSON under its container's `fsCachedData` directory. The
  tab reads the most recent snapshot and shows the top few symbols. No network,
  no permission.
- **Notifications** — `Modules/NotificationsProvider.swift`. Reads the Notification
  Center database under `group.com.apple.usernoted`. macOS guards that path with
  Full Disk Access, so until it is granted the tab shows a button that opens the
  right System Settings pane.

---

## Requirements

- macOS 13 or newer (developed and tested on macOS 26).
- Xcode command line tools (`xcode-select --install`) for `swift build`.
- A MacBook with a notch for the intended experience. On external displays or
  notchless Macs it falls back to a bar under the menu bar.

---

## Build and run

```bash
# run from source (quick iteration)
make run

# build a real .app bundle into ./dist
make app
open dist/MacNotch.app
```

---

## Install so it stays running

```bash
make install
```

This builds `MacNotch.app`, copies it to `/Applications`, and registers a
per-user LaunchAgent (`~/Library/LaunchAgents/com.macnotch.app.plist`) so it
starts automatically at every login. It also launches it immediately.

To remove it (app, login item, everything):

```bash
make uninstall
```

### Manual alternative

If you'd rather not use a LaunchAgent: drag `dist/MacNotch.app` to
`/Applications`, then add it under **System Settings → General → Login Items →
Open at Login**. Because the app declares `LSUIElement`, it has no Dock icon —
look for the music-note icon in the menu bar.

---

## Using it
| Action | Result |
| --- | --- |
| Hover the notch | Shows the compact peek card |
| Push the cursor down onto the card | Opens the full panel |
| Move away | Closes it |
| Click the notch strip | Pins the panel open |
| Click outside the panel | Closes and unpins |
| Music tab | Full player: art, progress, transport, volume |
| Home tab | Clock, date, battery, Dark Mode / Mute / Lock |
| Briefs tab | Weather, Stocks watchlist, recent notifications |
| Menu bar music-note icon | Open the notch, or Quit MacNotch |

---

## Troubleshooting

**Nothing shows in the notch.**
Make sure the app is running (`pgrep -x MacNotch`) and you're on the built-in
display. If your Mac has no notch the panel appears as a bar at the top-centre.

**Music never appears / stays on "Nothing playing".**
The MediaRemote trick depends on `/usr/bin/perl` being entitled. Check it still
works:

```bash
/usr/bin/perl \
  dist/MacNotch.app/Contents/Resources/mediaremote-adapter.pl \
  dist/MacNotch.app/Contents/Resources/MediaRemoteAdapter.framework \
  get
```

A line of JSON (or `null` when nothing is playing) means the adapter is fine. If
it errors, Apple has broken the workaround and the bundled framework needs
updating from `ungive/mediaremote-adapter`.

**The panel covers menu bar items while open.**
That's expected — the open panel is wider than the notch. It closes as soon as
the cursor leaves.

**Dark Mode button does nothing the first time.**
macOS asks for permission to control System Events. Approve it in
**System Settings → Privacy & Security → Automation**.

**Briefs shows "Grant Full Disk Access to see notifications".**
Notification Center's database is protected. Open **System Settings → Privacy &
Security → Full Disk Access**, enable MacNotch, then reopen the notch. If you run
from source with `make run`, grant access to your terminal app instead.

**Briefs shows "Open the Weather app once to refresh".**
The tab borrows the Weather app's own WeatherKit token, and those tokens expire
after a few weeks. Open the Weather app (or add its widget) once to mint a fresh
one, then reopen the notch.

**Stocks shows "Open the Stocks app once to cache quotes".**
The quotes come from the Stocks widget's cache, which only fills after the Stocks
app or widget has run at least once on this Mac.

---

## Project layout

```
Package.swift                 SwiftPM executable target + resources
Resources/Info.plist          Bundle metadata (LSUIElement, etc.)
scripts/build-app.sh          Builds dist/MacNotch.app
scripts/install.sh            Install to /Applications + login item
scripts/uninstall.sh          Remove everything
Sources/MacNotch/
  App.swift                   @main entry point
  AppDelegate.swift           Wiring + menu bar item
  Notch/                      Panel, screen geometry, shape, hover controller
  Media/                      MediaRemote adapter client, NowPlaying model, music manager
  Modules/                    Briefs data sources: weather, stocks, notifications
  System/                     CoreAudio volume, battery / dark mode / lock
  State/                      NotchViewModel (visual state + sizes)
  Views/                      SwiftUI: root, peek, expanded, music, home, briefs, components
  Resources/                  Vendored MediaRemote helper + license
```

---

## Credits and license

- The MediaRemote access technique and the vendored `mediaremote-adapter`
  helper framework / Perl script are by **Jonas van den Berg** and contributors,
  licensed **BSD-3-Clause** — see
  `Sources/MacNotch/Resources/MediaRemoteAdapter.LICENSE`.
  Upstream: <https://github.com/ungive/mediaremote-adapter>
- Notch geometry math follows the approach in
  [DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit) (MIT).
- Everything else in this repository is original.
