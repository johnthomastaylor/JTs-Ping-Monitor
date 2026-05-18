# JT's Ping Monitor

A macOS app that continuously pings a list of hosts and shows their
status, current latency, and cumulative stats (sent count, success rate,
min / avg / max) in a sortable table.

- Standard dock app with a single main window
- Cumulative stats per host since the last reset (persisted across
  launches)
- Inline-edit any host's address or description (double-click a row)
- Drag column headers to reorder; right-click a header to hide/show
- Sort by any column (sort order is remembered)
- Optional "Launch at login"

Requires macOS 14+ and Xcode command-line tools (Swift 5.9+).

## Build

```sh
./scripts/build-app.sh         # produces build/JT's Ping Monitor.app
./scripts/run.sh               # build and launch
```

## Install

To make "Launch at login" durable and have the app live somewhere
permanent, copy the bundle into `/Applications`:

```sh
./scripts/build-app.sh
cp -R "build/JT's Ping Monitor.app" /Applications/
open "/Applications/JT's Ping Monitor.app"
```

Then open Settings (⌘,) and toggle **Launch at login**.

## Settings

Settings → General:

- **Appearance** — System / Light / Dark
- **Ping every N s** — background polling interval (1–300; default 5)
- **Show status icons** — toggles the leftmost ✓/✕ column
- **Latency decimals** — `3` / `3.1` / `3.11` / `3.111`
- **Push timeout hosts to bottom** — partition down hosts to the bottom
  on top of whatever column sort is active
- **Monochrome** — drops the green/red status tint and the red error
  text in favor of `.primary`
- **Dim** + **Dim level** slider — reduce the table's opacity for a
  lower-contrast read

Settings → Hosts → **Edit Host List…** — a free-text editor
(one host per line; `address` or `address, description`) that replaces
the entire list on save. Existing addresses keep their UUID and stats;
new addresses become new hosts; addresses absent from the text are
removed. Lines starting with `#` are ignored.

Settings → Layout → **Reset Columns** — clears the saved column order
and visibility back to defaults.

## Editing hosts

- **Add** — click the `+` in the toolbar; small popover with address +
  optional description
- **Edit** — double-click a row's Host or Description cell; Enter
  commits, Esc cancels, clicking outside the two fields also cancels
- **Delete** — select one or more rows and press ⌫, or use the toolbar
  Delete button, or right-click → Delete
- **Reset stats** — toolbar eraser button (resets all, or just the
  selection if any), or right-click a row's "Reset stats". Both ask
  for confirmation.

## Where state lives

- Hosts: `~/Library/Application Support/JTsPingMonitor/hosts.json`
- Stats: `~/Library/Application Support/JTsPingMonitor/stats.json`
  (rewritten on every change)
- Preferences (appearance, interval, decimals, all the toggles, sort
  column + direction, column layout JSON): `UserDefaults` under
  `com.jtt.PingMonitorDock`
- Login-at-launch registration: `SMAppService.mainApp` (system-level)

## Regenerating the app icon

The icon is rendered from an SF Symbol on a colored squircle by
`scripts/generate-icon.swift`. Edit the constants at the top of that
file (`symbolName`, `backgroundHex`, `symbolWeight`, `symbolScale`) and
run:

```sh
swift scripts/generate-icon.swift
./scripts/build-app.sh
killall Dock      # so macOS picks up the new icon immediately
```
