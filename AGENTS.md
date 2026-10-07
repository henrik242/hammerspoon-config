# Hammerspoon config

Personal macOS automation.

## Layout

- `init.lua` - shared helpers (`mods`, `keep`, `alert`, `run`), window moving/layouts, lock, Bluetooth, reload watcher.
- `clipboard.lua` - clipboard history (replaces Clipy). `require("clipboard").start(mods, keep)`.
- `browser.lua` - URL router to Chrome profiles (replaces Choosy). `require("browser").start(keep)`.
- `local.lua` - gitignored machine-specific settings (browser profile accounts and routing rules). Template: `local.example.lua`. Keep personal details (emails, employer, work tools) there, not in tracked files.

Feature modules return `M` with `M.start(...)`; shared state is passed in, not global. Plain modules, not Spoons. Small features stay in `init.lua`.

## Conventions

- Hotkeys use `mods` (ctrl+alt+cmd).
- Store long-lived timers, watchers and tasks in `keep`, or they get garbage collected and callbacks silently stop.
- Use the `alert()` helper, not `hs.alert.show` directly (a nil screen arg drops the duration) and not `hs.notify` (banners don't show for this user).
- Comments: terse, plain ASCII, explain why rather than what.

## Gotchas

- Saving any file in `~/.hammerspoon/` reloads the config (pathwatcher).
- A chooser left open across a reload is orphaned and can't be closed; `clipboard.lua` hides it in `hs.shutdownCallback`. Fix a stuck one with `killall Hammerspoon; open -a Hammerspoon`.
- `hs.chooser`: the icon column is a fixed 36px wide and as tall as the row, and icons scale to fit, so pad icons on a wider-than-tall canvas to get a fixed small size. The `⌘1`-`⌘9` labels are fixed at 25pt and can't be changed. Row text can be `hs.styledtext` (font, size, `truncateTail`).
- `hs.ipc` is not loaded, so the `hs` CLI doesn't work.

## Clipboard history

- Stored in `hs.settings` key `clipHistory`: array of `{text, app}` (app = bundle ID), newest first, max 1000 entries of up to 100 KB. Entries that differ only in surrounding whitespace are duplicates; the newest wins.
- Changing it from outside: write through cfprefsd (`NSUserDefaults` suite `org.hammerspoon.Hammerspoon`, e.g. via JXA), then `touch init.lua` so the in-memory copy is reloaded. A copy in between overwrites the write.
- Clipy's old data: `~/Library/Application Support/com.clipy-app.Clipy/sqlite.db` (table `pasteboardHistoryAssets`, type `public.utf8-plain-text`). Open it read-only.

## Testing

- Syntax: `luac -p init.lua *.lua`.
- Clipboard recording: `pbcopy` something, wait about 1s, then check with `defaults export org.hammerspoon.Hammerspoon -`.
- UI: temporarily add an `hs.timer.doAfter` line that shows the chooser and hides it after a few seconds, take a `screencapture -x`, then remove the line. Allow about 2s for the reload.
