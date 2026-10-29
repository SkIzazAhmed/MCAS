# MCAS architecture

Updated with each feature. Last update: POC step 1 (capture + storage).

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

## Coming next (POC)

1. `Notch/NotchPanel.swift`, `Notch/NotchGeometry.swift`: the panel glued to the notch.
2. `Shelf/ShelfView.swift`, `Shelf/ClipCardView.swift`: cards grouped by day.
3. `Paste/`: send ⌘V via Accessibility; "Paste together".
