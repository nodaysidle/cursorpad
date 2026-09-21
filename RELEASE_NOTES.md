# CursorPad Release Notes

## Version 1.1.0 — Usability, Typography & Audit Remediation

### Highlights
This release transforms CursorPad from an initial technical release into a polished, responsive, and ergonomic native macOS writing environment. It resolves all findings from the architectural audit and adds the core usability controls promised in the product specification.

---

### New Features & Usability Improvements

* **Native Preferences Window (`⌘,`):**
  * Added dedicated macOS Settings scene accessible via `Command + ,` or the App menu.
  * Adjust editor font size (9 pt to 32 pt) with a live point indicator.
  * Customize tab width (`2 spaces`, `4 spaces`, `8 spaces`).
  * Toggle line wrapping on/off.
  * One-click "Reset to Defaults" button.
  * All settings immediately persist to `UserDefaults` and reconfigure the active editor text view in real time.

* **Typography & View Shortcuts:**
  * **Zoom In (`⌘+` / `⌘=`):** Increase editor font size on the fly.
  * **Zoom Out (`⌘-`):** Decrease editor font size on the fly.
  * **Actual Size (`⌘0`):** Reset editor font size to default 13 pt.
  * **Toggle Line Wrapping (`⌥Z`):** Instant word wrap switching.

* **Sidebar Search Filter:**
  * Added a fast filter bar at the top of the compact library sidebar styled in Cursor's dark aesthetic (`#1e1e1e` / `#2b2b2b`).
  * Real-time filtering by note title with an instant clear button (`✕`).

* **Live Word & Character Counts:**
  * Status bar now tracks live word count alongside character count: `"X words · Y characters"`.
  * Computes dynamically across whitespace and newline boundaries as you type.

* **Explicit Save & Real-Time Persistence Feedback:**
  * Added `File → Save` and `Command + S` shortcut.
  * Status bar Save button with live indicator: `Saved`, `Unsaved changes`, `Saving…`, or `Not saved`.
  * Generation tracking ensures rapid typing during a flush never erroneously marks unsaved edits as saved.

---

### Audit & Stability Fixes

* **Gutter Layout Optimization:**
  * Fixed performance bottleneck where `ensureLayout(for: documentRange)` was invoked per line inside the gutter draw pass.
  * Gutter now ensures layout once per draw pass, preserving smooth typing latency well under the 8ms target.

* **Recovery State Machine Vocabulary:**
  * `AppState.LibraryStatus` now implements the strict 5-state recovery vocabulary: `idle`, `active`, `succeeded`, `failed(String)`, and `cancelled`.
  * Cancelled launches are accurately recorded as `.cancelled` rather than `.failed("launch was cancelled")`.

* **Debounce & Dead Code Cleanup:**
  * Properly wired `services.debounceInterval` into `NonBlockingAtomicDiskStorage`.
  * Removed unused `noteBodies` write-only cache in `AppState`.

* **Command Palette Zero-Result Fix:**
  * Pressing Enter when no search results match no longer dismisses the palette; the search field remains active with `"No matching notes found"`.

* **Palette Accessibility Traits:**
  * Enhanced palette rows with accessible labels, `.isButton` trait, and selection state announcements.

* **Packaging & Install:**
  * Fixed LaunchServices trailing-slash path comparison in `--install` script.

---

### Verification
* **148 automated tests** passing across 9 test suites (`swift test`).
* Full code changes reviewed and validated by **TypeSafe Jev (`jev-review`)** with 0 warnings.
