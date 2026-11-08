# Management and settings separation — 2026-11-08

Issue: https://github.com/lubelski/spacedock/issues/12

## Implementation

Normal status-button click opens the project management window. Right-click, Control-click, and Option-click attach and track the quick-access menu temporarily. Global settings use a separate reusable window and a separate draft model, so registry refreshes do not overwrite unsaved settings. Closing and reopening settings reloads persisted values. Per-project overrides stay in project-row menus. Cmd-, and Settings… open global settings; --settings supports opening it on app launch.

## Observed

- `swift build -c release` succeeded in `.wt/management-window`.
- Installed and launched only profile `management-ui`, leaving the default app and registry untouched.
- Window screenshots showed management with an empty list, management with a sample project, and global settings in a separately titled window.
- Sample project was registered via CLI, then appeared after reopening management.
- Screenshots during this session: `/tmp/spacedock-management.png`, `/tmp/spacedock-management-populated.png`, `/tmp/spacedock-settings.png` (temporary, not repository assets).

## Not verified interactively

System Events returned `osascript is not allowed assistive access (-1728)`. Normal/alternate status-button clicks, Cmd-,, settings save/revert, and draft preservation need interactive verification. No Dock, Space-switching, or Cmd-Tab behavior is claimed tested.

## Second pass (session 4, 2026-11-08): System Settings style

User rejected the first settings window ("looks terrible", modeled on VS Code) and asked for VS Code's search and scaling with a Mac-native look. Rebuilt `Sources/Spacedock/SettingsWindow.swift`:

- A declarative schema. `SettingsSchema.all` is a list of `SettingSpec` (id, section, title, description, control, key path into `Settings`). Rows, search, sidebar filtering, modified markers, and reset all derive from it. Adding a setting is one entry.
- `NavigationSplitView`: a search field over a sidebar of sections (Terminal, Text, Window, Ghostty, Advanced), one `Form(.grouped)` per section. Window title stays "Spacedock Settings", the section is the subtitle.
- Rows are `LabeledContent` with title, one-line description, and the control. A value that differs from the default shows an accent dot; hovering the row shows Reset.
- Changes write settings.json on commit (submit, picker, stepper). No Save button. Footer: "Restart Running Projects".
- Ghostty keys: a `Table` with Key and Value columns and plus/minus under it, instead of a free-text block. Repeated keys are flagged; the last row wins, matching Ghostty.
- Advanced: file location, Open in Editor, Reveal in Finder, Reload, and Reset All behind an NSAlert.
- Management window: title with count, Add Project, an overflow menu (Regenerate All, Refresh, Reveal Apps), a gear that opens Settings; rows with color dot, name, folder, Running/Stopped capsule, Launch/Show, per-project menu. Empty state with an Add button.
- `--settings-section NAME` and `--settings-query TEXT` launch arguments choose the first view, for screenshots.

Observed (profile `management-ui`, window-id screenshots): Terminal, Text, Ghostty, Advanced sections and a `font` search rendered as designed; CLI-written values (`fontSize=14`, two ghostty keys) appeared with the modified dot and in the table. Anti-learnings: a `TextField("key", ...)` inside a `Table` inside a `Form` renders its title as a label, use an empty title with `prompt:` and `.labelsHidden()`; `.navigationTitle` on the detail replaces the window title, use `.navigationSubtitle` for the section; grouped-form footers align trailing by default.

Not verified: any click or keystroke (Accessibility still denied), so autosave on commit, hover Reset, table editing, and the alert were not exercised.
