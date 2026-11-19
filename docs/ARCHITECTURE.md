# MCAS architecture

Updated with each feature. Last update: v0.3 (keyboard control, paste queue, smart types, save flash).

## How a copy travels

```
you press ⌘C
   │
   ▼
PasteboardWatcher      checks NSPasteboard.changeCount every 0.5 s (macOS sends no event)
   │  changed?
   ├─ paused? ────────────────► ignored
   ├─ written by MCAS? ───────► ignored (marker type com.izaz.mcas.internal)
   ├─ SecretFilter says skip? ► ignored (password-manager markers, ignored apps)
   ▼
ClipReader             reads every type of every item, decides the kind,
   │                   makes a preview + thumbnail, fingerprint for duplicates
   ▼
AppModel.save          ──► HistoryStore.save  (SQLite; a duplicate replaces the old row)
   │
   ▼
AppModel.reload        recentItems / totalCount change → SwiftUI redraws the menu
```

Putting something back: `MenuBarMenu` → `AppModel.copyToClipboard` → `PasteService` rebuilds the
original pasteboard items from the stored data, adds the MCAS marker, and bumps the item to the top.

## Data model

- `clip` table (`ClipItem`): one row per copy: time, kind, preview, source app, fingerprint, size, thumbnail.
- `clipRepresentation` table (`ClipRepresentation`): the raw bytes, one row per (pasteboard item, type).
  Deleting a clip deletes its rows here too (foreign key with cascade).

The shelf only loads `clip` rows. Raw data is read only when pasting.

## Design rules

- Capture code doesn't know about the database, and storage doesn't know about AppKit, so each can be tested alone.
- Tests use private named pasteboards and in-memory databases, so they never touch your real clipboard or history.
- Clipboard contents are never written to logs.
- Schema changes are new migrations in `HistoryStore.migrator`; old ones are never edited.

## The notch shelf

```
AppDelegate (at launch)
   ├─ NotchController.start()
   │     ├─ trigger window: invisible, exactly over the notch (NotchGeometry)
   │     │     hover 150 ms ─► open(.hover)    click ─► open(.pinned)
   │     └─ shelf window: NotchShelfView ─► ShelfView (same view as the menu bar panel)
   │           hover mode: closes 300 ms after the mouse leaves
   │           pinned mode: closes on Esc / click outside / ⌥⌘V / picking an item
   └─ GlobalHotKey ⌥⌘V ─► NotchController.toggleFromHotKey()
```

Both windows are `NotchPanel`s: borderless, non-activating (the app you're in keeps focus,
so auto-paste lands there), above the menu bar, on every Space.

## Pasting

- Click a row → `AppModel.paste` → `PasteService.paste`: item on the clipboard, then ⌘V is
  sent to the front app (needs Accessibility; without it the user presses ⌘V).
- ⌘-click rows → `Selection` (keeps pick order) → "Paste together" → `PasteService.pasteTogether`
  joins the items' text with newline / space / comma. Images are skipped.

## Screenshots

`ScreenshotWatcher` listens (via Spotlight, `kMDItemIsScreenCapture`) for new screenshot files and
saves them as image items.

## v0.2 additions

- **Pin / search / retention** live in `HistoryStore` (migration "v2" added `isPinned` and `expiresAt`).
  `AppModel.runMaintenance` runs every 15 s: deletes expired one-time codes, and hourly removes
  unpinned items older than the retention setting.
- **Secret guard** (`Capture/SecretGuard.swift`) checks copied text in `PasteboardWatcher`:
  API keys and Luhn-valid card numbers are skipped; 6–8 digit codes get `expiresAt = now + 60 s`.
- **Settings** (`Settings/AppSettings.swift`, `Settings/SettingsView.swift`): saved in UserDefaults.
  Changes post `.mcasSettingsChanged`; `AppModel` re-applies the ignore list / secret guard and
  `AppDelegate` re-registers the shortcut.
- **Search focus**: clicking the search box makes the shelf key and activates MCAS so you can type;
  closing hands activation back to the app you came from (`NotchController.restoreFocusIfNeeded`),
  and `PasteService` waits until that app is in front before sending ⌘V.

## v0.3 additions

- **Keyboard control**: ⌥⌘V → `NotchController.open(.pinned, focusSearch: true)` makes the shelf key
  and bumps `AppModel.searchFocusRequest`; `ShelfView` focuses its search field. Arrow keys move
  `highlighted`, Return / ⇧Return / ⌘1–9 paste (handled with `onKeyPress` on the search field).
- **Paste queue** (`Paste/PasteQueue.swift` + `AppModel.startQueue`): first item goes on the clipboard
  (without reordering history); a global ⌘V key monitor swaps in the next item 0.25 s after each paste.
  Needs Accessibility. Progress shows in the shelf banner and the menu bar icon ("2/5").
- **Smart types** (`Shelf/SmartType.swift`): worked out from the text at display time (nothing stored,
  no network): link → host + Open Link; color → swatch + Copy as HEX/RGB; email → New Email; code → monospaced.
- **Save flash**: `AppModel.onSaved` → `NotchController.showSaveFlash()`, a click-through panel beside
  the notch for ~1 s. Can be turned off in Settings.
