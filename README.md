# MCAS

A free, open-source macOS clipboard manager that lives in the MacBook notch.
It remembers everything you copy, never stores passwords, and lets you paste one item or many.

> Status: proof of concept (POC). Capture, storage and the menu bar history work; the notch shelf is next.

## Build and run

Requirements: macOS 14 or later, Xcode 16 or later.

1. Open `MCAS.xcodeproj` in Xcode.
2. The first time, Xcode downloads the GRDB package (bottom-left progress bar). Wait for it to finish.
3. Press **⌘R** to run. MCAS has no Dock icon: look for the clipboard icon in the menu bar.
4. Press **⌘U** to run the tests.

If macOS asks whether MCAS may **paste from other apps**, choose **Allow**. A clipboard manager needs this to read what you copy.

## Project layout

| Folder | What it does |
| --- | --- |
| `MCAS/App` | App start, menu bar menu, `AppModel` (the app's state) |
| `MCAS/Capture` | Watches the clipboard, reads copies, filters out passwords |
| `MCAS/Storage` | SQLite history (via GRDB): save, load, delete, duplicates |
| `MCAS/Shelf` | The shelf UI (POC: day grouping logic; notch UI coming) |
| `MCAS/Paste` | Puts saved items back on the clipboard |
| `MCAS/Support` | Logging and small helpers |
| `MCASTests` | Automated tests, one file per feature |

New `.swift` files placed in these folders are picked up by Xcode automatically.
See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for how a copy travels through the app.

## Debugging

- **Logs:** open Console.app, press Start, and search `com.izaz.mcas`. Each feature logs under its own category (capture, storage, paste). Clipboard contents are never logged.
- **Debug menu** (debug builds): menu bar icon → Debug → *Simulate a copy* / *Open data folder*.
- **Database:** `~/Library/Application Support/MCAS/history.sqlite`, a plain SQLite file during the POC.
- **Breakpoints worth setting:** `PasteboardWatcher.checkForChanges`, `HistoryStore.save`, `AppModel.save`.

## Signing with your Apple ID (needed from the paste step)

Unsigned (ad-hoc) builds make macOS forget the Accessibility permission on every rebuild. To fix that for free, create `Config/Local.xcconfig` (git-ignored) containing:

```
CODE_SIGN_IDENTITY = Apple Development
DEVELOPMENT_TEAM = YOUR_TEAM_ID
```

## License

GPL-3.0. See [LICENSE](LICENSE).
