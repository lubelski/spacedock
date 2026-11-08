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
