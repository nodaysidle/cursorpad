# CursorPad User Guide

CursorPad is a native, local-first macOS writing app for people who live in a dark editor.
One window, one note at a time, an SF Mono editor styled after the Cursor IDE, a compact
library sidebar and a keyboard-first command palette. Everything is stored on your Mac.

- **Bundle identifier:** `com.cursorpad.app`
- **Version:** 1.0.0 (build 1)
- **Requirements:** macOS 14.0 or later on Apple Silicon (arm64)

---

## 1. Install

1. Open `dist/CursorPad.dmg` (double-click, or `open dist/CursorPad.dmg`).
2. Drag **CursorPad** onto the **Applications** shortcut inside the disk image.
3. Eject the disk image, then launch CursorPad from Applications.

The DMG also contains the app itself, so you can run it straight from the mounted volume for
a quick look before installing.

### First launch and Gatekeeper

Local builds are **ad-hoc signed** — they are signed, verified, but not notarized by Apple.
On first launch macOS may report that it cannot check the app for malicious software. To open
it anyway, use one of these:

- Right-click (or Control-click) **CursorPad** in Applications and choose **Open**, then confirm.
- Or open **System Settings → Privacy & Security**, scroll to the security notice for CursorPad
  and choose **Open Anyway**.

You only have to do this once per copy.

### Verify what you are running

```sh
codesign --verify --deep --strict --verbose=2 /Applications/CursorPad.app
/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" /Applications/CursorPad.app/Contents/Info.plist
```

The first command must report a valid signature; the second must print `com.cursorpad.app`.

---

## 2. The window

CursorPad opens one window with three regions:

| Region | What it shows |
| --- | --- |
| Library sidebar | Every note, newest first, with title, relative timestamp and character count |
| Editor | The note you are writing, with a line-number gutter |
| Status line | Startup, storage, permission and save state — always honest, never silent |

### First run

An empty library shows **“No notes yet — Press ⌘N to create your first note.”**
Press **⌘N** and start typing; there is nothing else to set up.

---

## 3. Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| **⌘N** | New note |
| **⌘P** | Open the command palette |
| **⌘K** | Open the command palette (quick open) |
| **⌘B** | Show or hide the library sidebar |
| **↑ / ↓** | Move through palette results |
| **Return** | Open the highlighted note in the palette |
| **Esc** | Close the palette and return focus to the editor |
| **⌘Q** | Quit (pending text is flushed first) |

---

## 4. The editor

- **SF Mono 13 pt** on a **#181818** background, line height 1.45 — the Cursor dark palette.
- Selection tint **#264f78**, current-line highlight **#222222**, caret **#80bfff**.
- Gutter line numbers in muted **#6e7681**, recalculated as lines are added or removed.
- If SF Mono cannot be resolved, the editor falls back to the system monospaced font and says so
  in the status line instead of failing.

---

## 5. The library sidebar

- Notes are ordered by **last updated**, with title, relative time and character count.
- Clicking a row switches the editor to that note immediately.
- **Move to Trash** on a note sends the note file to the macOS **Trash** — the standard,
  recoverable delete. Nothing is erased behind your back.
- If a delete fails, the note stays exactly where it was and the status line explains why.

---

## 6. Saving, storage and data location

You never press Save. CursorPad autosaves:

- typing is debounced by **250 ms**, and the write commits atomically within **300 ms** of you
  stopping;
- writes happen off the main thread, so typing never blocks on the disk;
- a normal quit (⌘Q) flushes pending text before the app exits;
- an interrupted write leaves the previous version of the file intact — no truncated notes.

Your data lives only in Application Support:

```
~/Library/Application Support/CursorPad/
├── CursorPad.sqlite3      # library index (note metadata)
└── Notes/                 # note bodies as plain UTF-8 text files
```

Because note bodies are plain text, you can read, back up or move them with any tool you like.
There is no cloud account, no sync service and no “save as” step.

---

## 7. Permissions

CursorPad asks for nothing it does not need at the moment it needs it.

- **External files and folders:** access is always a deliberate transaction. CursorPad shows the
  standard macOS open panel, and only what you pick is granted, through a security-scoped
  bookmark. Releasing the location releases the access scope. Denying or cancelling leaves the
  previous selection untouched and you can simply choose again.
- **Microphone:** the bundle declares `NSMicrophoneUsageDescription` so macOS can present the
  standard microphone prompt if audio capture is ever explicitly requested. CursorPad never
  starts audio capture on its own, and this version does not record dictation.

---

## 8. Privacy

- **No telemetry, no analytics, no accounts, no network calls.** Packaging sources contain no
  endpoints, tokens or identifiers.
- Notes and editor settings are treated as personal data: they are never written to logs or
  diagnostics.
- Everything CursorPad keeps stays inside `~/Library/Application Support/CursorPad`.

---

## 9. Troubleshooting

| Symptom | What it means / what to do |
| --- | --- |
| Status line: **“Storage unavailable — …”** | The Application Support store could not be opened. Fix the described reason, then use **Retry** in the app; nothing was overwritten. |
| Palette: **“No matching notes found”** | The query matched nothing. Keep typing, or clear the field — the search input stays active. |
| macOS refuses to open the app | It is an ad-hoc signed local build — see [First launch and Gatekeeper](#first-launch-and-gatekeeper). |
| Nothing happens on ⌘N before the app is ready | The status line reports storage startup; a note is only created once storage can hold it. |

---

## 10. Uninstall

1. Quit CursorPad (⌘Q).
2. Move `/Applications/CursorPad.app` to the Trash.
3. Optional — remove your notes and index: delete `~/Library/Application Support/CursorPad`.

Deleting the Application Support folder deletes your notes; move its contents somewhere else
first if you want to keep them.

---

## 11. For reviewers and builders

Packaging is owned by one script:

```sh
Scripts/package_app.sh          # release build, app assembly, signing, verification, DMG
```

It builds `swift build -c release --arch arm64`, assembles `dist/CursorPad.app`, ad-hoc signs it
with `Resources/App.entitlements`, runs `codesign --verify --deep --strict`, then creates and
verifies `dist/CursorPad.dmg`. A failed build, a non-arm64 executable or a failed signature check
stops packaging — the script never publishes a bundle that did not verify.

Optional, opt-in install of the verified bundle:

```sh
Scripts/package_app.sh --install   # scoped rollback copy, then /Applications/CursorPad.app
```

The default run never installs, never launches and never touches anything outside `dist/`.
