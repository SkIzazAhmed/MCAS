# MCAS

A free, open-source macOS clipboard manager that lives in the MacBook notch.
It remembers everything you copy, never stores passwords, and lets you paste one item or many.

![CI](https://github.com/SkIzazAhmed/MCAS/actions/workflows/swift.yml/badge.svg)
![License: GPL-3.0](https://img.shields.io/badge/license-GPL--3.0-blue)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black)

> **Status: v0.3 (early but usable).** The notch shelf, search, pinning, multi-paste and the secret guard all work.
> There is no signed download yet, so for now you build it from source (see below).

<!-- Add a screenshot or GIF of the notch shelf here: ![MCAS shelf](docs/shelf.png) -->

## Features

**Capture**
- Saves text, rich text, links, images, files and screenshots to a history that survives restarts (SQLite).
- Screenshots taken with ⇧⌘3 / ⇧⌘4 / ⇧⌘5 are added automatically, even though macOS saves them as files.
- Copying the same thing again moves it to the top instead of making a duplicate.

**The notch shelf**
- Hover over the notch to peek, or click it to keep the shelf open.
- Press **⌥⌘V** (changeable) to open it with the cursor in search: **↑/↓** to move, **Return** to paste,
  **⇧Return** to paste as plain text, **⌘1–⌘9** to paste one of the first nine items.
- History is grouped by day. Smart types: links show the site and an *Open Link* action,
  colours show a swatch with *Copy as HEX/RGB*, emails get *New Email*, and code uses a code font.
  All of this is worked out on your Mac; MCAS makes no network requests.

**Pasting**
- Picking an item pastes it straight into the app you were using.
- **Paste together:** select several items and paste them as one, in the order you picked them.
- **Paste as queue:** select several items; each time you press ⌘V, the next one is pasted.
  Handy for filling in a form field by field.
- Right-click an item to pin it, paste it as plain text, copy it without pasting, or delete it.

**Privacy**
- Never saves anything a password manager marks as secret (the [nspasteboard.org](http://nspasteboard.org) markers),
  or anything copied while an ignored app is in front.
- Secret guard: API keys, tokens and card numbers (checked with the Luhn checksum) are never saved.
  One-time codes are saved but deleted after 60 seconds.
- Unpinned items older than 30 days are removed (choose 1 day to forever in Settings).
- Clipboard contents are never written to the logs.

**Settings:** shortcut, history length, launch at login, ignored apps, secret guard on/off,
the "Saved" flash beside the notch, and Accessibility permission status.

## Build and run

Requirements: macOS 14 or later, Xcode 16 or later.

1. Open `MCAS.xcodeproj` in Xcode.
2. The first time, Xcode downloads the GRDB package (bottom-left progress bar). Wait for it to finish.
3. Press **⌘R** to run. MCAS has no Dock icon: look for the clipboard icon in the menu bar, or hover over the notch.
4. Press **⌘U** to run the tests.

**Permissions**
- *Accessibility* lets MCAS paste into other apps for you (it sends ⌘V). Without it, the item is still put on
  the clipboard and you press ⌘V yourself.
- *Paste from other apps*: if macOS asks, choose **Allow**. A clipboard manager needs this to read what you copy.
- *Desktop folder*: asked once, so screenshots saved there can be added to history.

### Signing with your Apple ID

Unsigned (ad-hoc) builds make macOS forget the Accessibility permission on every rebuild. To fix that for free,
create `Config/Local.xcconfig` (git-ignored) containing:

```
CODE_SIGN_IDENTITY = Apple Development
DEVELOPMENT_TEAM = YOUR_TEAM_ID
```

## How it works

```
⌘C → PasteboardWatcher → SecretFilter / SecretGuard → ClipReader → HistoryStore (SQLite)
                                                                        │
          notch shelf (ShelfView) ◄── AppModel ◄────────────────────────┘
                │
                └─► PasteService → clipboard + ⌘V into the app you were using
```

macOS sends no event when the clipboard changes, so `PasteboardWatcher` checks `changeCount` every 0.5 s.
Everything MCAS writes to the clipboard carries its own marker type, so it is never saved twice.
See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the full path of a copy and the data model.

## Project layout

| Folder | What it does |
| --- | --- |
| `MCAS/App` | App start, menu bar menu, global shortcut, `AppModel` (the app's state) |
| `MCAS/Capture` | Watches the clipboard and screenshots, reads copies, filters out secrets |
| `MCAS/Storage` | SQLite history (via GRDB): save, load, search, pin, retention, duplicates |
| `MCAS/Notch` | Notch position, the floating panel, opening and closing the shelf |
| `MCAS/Shelf` | The shelf UI, selection order, day grouping, smart types |
| `MCAS/Paste` | Puts items back on the clipboard, paste together, paste queue |
| `MCAS/Settings` | Settings window and stored preferences |
| `MCAS/Support` | Logging and small helpers |
| `MCASTests` | 73 automated tests, one file per feature |

## Tests and CI

The tests use private named pasteboards and in-memory databases, so they never touch your real clipboard or history.
GitHub Actions builds the app and runs every test with `xcodebuild` on each push.

## Debugging

- **Logs:** open Console.app, press Start, and search `com.izaz.mcas`. Each feature logs under its own category
  (capture, storage, paste).
- **Debug actions** (debug builds): the shelf's ⋯ menu → *Simulate a copy* / *Open data folder*.
- **Database:** `~/Library/Application Support/MCAS/history.sqlite`, a plain SQLite file for now.
- **Breakpoints worth setting:** `PasteboardWatcher.checkForChanges`, `HistoryStore.save`, `AppModel.save`.

## Roadmap

- Signed and notarised `.dmg` on GitHub Releases
- Encrypted history (SQLCipher)
- Menu bar icons shown in the notch, opened on hover

## License

GPL-3.0. See [LICENSE](LICENSE).
