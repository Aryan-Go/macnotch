# MacNotch

A Dynamic-Island-style overlay for the MacBook notch. It hides in the notch, drops
down a live "now playing" card when your track changes, and expands into a full
music controller (plus a small system dashboard) when you hover over it.

## What it does

- **Hides in the notch.** When idle, it's exactly the size of the notch and painted
  black, so it's invisible.
- **Live activity peek.** When your track changes, a compact card slides out below
  the notch with album art, title, artist, and an animated equalizer.
- **Two-stage hover.** A glance at the notch shows the compact peek card; push the
  cursor down onto it and the full panel springs open.
- **Full music controls.** Album art, track details, a scrubbable progress bar,
  play/pause, previous/next, shuffle, repeat, and system volume.
- **Works with any player.** Apple Music, Spotify, TIDAL, browsers — anything that
  reports to the Mac's Now Playing system.
- **Home tab.** A clock, date, battery ring, and quick actions for Dark Mode, Mute,
  and Sleep.
- **Briefs tab.** At-a-glance weather, your Stocks watchlist, and recent
  notifications — pulled from the data the Weather, Stocks, and Notification Center
  apps already keep on your Mac.
- **Menu bar item.** A small item to open the notch or quit the app.

## Requirements

- macOS 13 or newer.
- A MacBook with a notch for the intended experience. On external displays or
  notchless Macs, it appears as a bar under the menu bar instead.
- No Dock icon — look for the music-note icon in the menu bar.

## Install

```bash
make run          # run from source for a quick try

make app          # build MacNotch.app into ./dist
open dist/MacNotch.app
```

To have it start automatically at every login:

```bash
make install      # builds, copies to /Applications, and adds a login item
make uninstall    # removes the app, login item, and everything else
```

Prefer to do it by hand? Drag `dist/MacNotch.app` into `/Applications`, then add
it under **System Settings → General → Login Items → Open at Login**.

## Using it

| Action | Result |
| --- | --- |
| Hover the notch | Shows the compact peek card |
| Push the cursor down onto the card | Opens the full panel |
| Move away | Closes it |
| Click the notch strip | Pins the panel open |
| Click outside the panel | Closes and unpins |
| Music tab | Full player: art, progress, transport, volume |
| Home tab | Clock, date, battery, and Dark Mode / Mute / Lock |
| Briefs tab | Weather, Stocks watchlist, and recent notifications |
| Menu bar music-note icon | Open the notch, or quit MacNotch |

## Troubleshooting

**Nothing shows in the notch.**
Make sure the app is running and you're on the built-in display. If your Mac has no
notch, the panel appears as a bar at the top-centre.

**Music never appears.**
Quit and relaunch the app, then play something in a supported player. If it still
stays on "Nothing playing", your player may not report to the Mac's Now Playing
system.

**The panel covers menu bar items while open.**
That's expected — the open panel is wider than the notch. It closes as soon as the
cursor leaves.

**The Dark Mode button does nothing the first time.**
macOS asks for permission to control your Mac. Approve it in
**System Settings → Privacy & Security → Automation**.

**Briefs shows "Grant Full Disk Access to see notifications".**
Open **System Settings → Privacy & Security → Full Disk Access** and enable MacNotch.
If MacNotch is *already* listed and switched on but the notch still asks, the stored
grant is stale: macOS ties each entry to the *exact* build it was approved for, so a
gently different build leaves the toggle on while reads are silently denied (you'll
see `Failed to match existing code requirement for subject com.macnotch.app` in
`log show --predicate 'process == "tccd"'`). Remove MacNotch with the **−** button,
add it back with **+**, then quit and reopen the app. Builds made with `make app` /
`make install` carry a stable signature, so the re-added grant survives later rebuilds.

**Briefs shows "Open the Weather app once to refresh".**
Open the Weather app (or add its widget) once to refresh the data, then reopen the
notch.

**Stocks shows "Open the Stocks app once to cache quotes".**
Open the Stocks app (or its widget) once so it has data to show, then reopen the
notch.

## Credits

- The MediaRemote access technique and the bundled `mediaremote-adapter` helper
  are by **Jonas van den Berg** and contributors, licensed **BSD-3-Clause** — see
  `Sources/MacNotch/Resources/MediaRemoteAdapter.LICENSE`.
  Upstream: <https://github.com/ungive/mediaremote-adapter>
