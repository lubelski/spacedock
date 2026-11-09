# Spacedock agent guidance

Spacedock generates one macOS application per project, so the Dock, Cmd-Tab, and Spaces treat each project as its own app. Each generated app runs the Spacedock shell: a window holding a terminal, later a browser, with the project name in a badge of the project color at the right of its title bar. A separate prime app, `~/Applications/Spacedock.app`, is a menu bar control panel for the project apps.

Read `HANDOFF.md` first in a new session, then `.transient-learning-map/orientation.md`.

## Profiles: keep agent copies away from the installed copy

The default profile is the user's installed copy: `~/Applications/Spacedock*.app`, registry and settings in `~/Library/Application Support/Spacedock/`, bundle ids `dev.lubelski.spacedock.<slug>`. Agents do not touch it. For anything you build and run, pass `--profile NAME` on every command (or export `SPACEDOCK_PROFILE=NAME`). A profile has its own bundle ids (`dev.lubelski.spacedock.<profile>.<slug>`), its own registry and settings, and its bundles under `~/Library/Application Support/Spacedock/profiles/<profile>/Applications/`. Its apps carry a `(profile)` name suffix, a badge on the icon, and open in the background without taking focus. A running app reads its profile from Info.plist, so a forgotten environment variable cannot cross profiles. Quit a profile's apps with `Spacedock quit --profile NAME` when done.

```sh
export SPACEDOCK_PROFILE=dev
swift build -c release
.build/release/Spacedock add --name Hoard --color "#0F766E" --folder ~/dev/hoard
.build/release/Spacedock restart hoard      # launches in the background
.build/release/Spacedock quit
```

The user can assign a profile's apps to a Space of their own once, through the Dock tile's Options menu, and macOS keeps honoring it because the bundle ids are stable. Pass `--foreground` to a profile app to let it activate.

## Build and run

```sh
swift build -c release
.build/release/Spacedock add --name NAME --color "#RRGGBB" --folder PATH
open ~/Applications/Spacedock/NAME.app
.build/release/Spacedock install        # the prime app, ~/Applications/Spacedock.app
.build/release/Spacedock regenerate     # after every rebuild: rewrites prime and all installed bundles
.build/release/Spacedock restart [SLUG ...]   # quit running apps, regenerate, relaunch them (prime too); named ones launch even if stopped
.build/release/Spacedock quit [SLUG ...]      # quit running apps (all, plus prime, with no names)
.build/release/Spacedock list           # slug, color, running|stopped, folder, name
.build/release/Spacedock new            # placeholder row, prints its slug; cannot launch until it has a folder
.build/release/Spacedock edit SLUG [--name N] [--color #RRGGBB] [--folder PATH]   # slug follows the name until the bundle is first installed
.build/release/Spacedock set SLUG KEY=VALUE ...      # per-project override; ghostty.<key> for raw Ghostty config
.build/release/Spacedock set --global KEY=VALUE ...  # edits settings.json
.build/release/Spacedock show SLUG      # effective settings for one project
.build/release/Spacedock remove SLUG
```

`add` records the project in `~/Library/Application Support/Spacedock/projects.json` and installs `~/Applications/Spacedock/NAME.app`. `regenerate` rebuilds every registered bundle from the current binary. `generate --name ... [--out DIR]` still writes an unregistered one-off bundle (default `out/`).

The executable is a copy of the Spacedock binary. `Contents/Resources/project.json` holds name, slug, color, and folder. Bundle id is `dev.lubelski.spacedock.<slug>`. The bundle is ad-hoc signed.

Window settings (font, padding, cursor style, scrollback, emulator) are read at launch from `~/Library/Application Support/Spacedock/settings.json`, written with defaults on first `add`. `emulator` is `ghostty` (default) or `swiftterm` (compatibility only, no new work); both are linked. Each project in `projects.json` may carry a `settings` object overriding any of those fields and a `ghostty` map of raw Ghostty config keys; a global `ghostty` map lives in `settings.json`. Project keys win. Apps read overrides from the registry at launch, so `set` needs a relaunch, not a regenerate. Raw Ghostty keys do nothing in the swiftterm emulator. The window layer talks to the emulator only through `TerminalPane` in `Sources/Spacedock/Pane.swift`.

The prime app runs as a menu bar item (`LSUIElement`, bundle id `dev.lubelski.spacedock`, role from the `SpacedockRole` Info.plist key). Its menu lists projects with a running indicator and launches or activates them. Clicking the menu bar icon, `open ~/Applications/Spacedock.app` while it runs, or launching it with `--args --panel`, shows the project management window: a project list with launch, show, quit, restart, regenerate, remove, and a gear, beside an edit pane for the selected project (name, color, folder, terminal settings). `+` adds a "New Project" row with no folder and selects it. A project with problems (no folder, missing folder, empty name) stays in the list and cannot launch. `--args --edit SLUG` opens the panel with that project selected. Right-click or Option-click the icon for the quick menu. Its Restart Spacedock item, also in the app menu, relaunches the prime app from its bundle on disk and leaves project apps running. The gear, Cmd-,, or `--args --settings` opens the separate settings window (`Sources/Spacedock/SettingsWindow.swift`): sidebar of sections, search, grouped forms, autosave on commit. A new global setting is one `SettingSpec` in `SettingsSchema.all` plus its field in `Settings`. Project windows stay in their own apps.

Keyboard shortcuts: the ghostty view reports a Ghostty-bound key as handled before the menu bar sees it, and libghostty-spm gives the host no way to receive window-level actions (new_window, quit). So `GhosttyPane` unbinds the keys our menu owns (`super+n`, `super+shift+w`, `super+q`) in the config it builds, and those fall through to the menu bar. Everything else (Cmd-C, Cmd-V, Cmd-W as close_surface, font size) stays Ghostty's. A project can rebind with raw `ghostty.keybind` settings, but a Ghostty action the host does not implement (new_split, new_tab) is swallowed. A delegate that would forward those actions exists for reference on the fork `lubelski/libghostty-spm`, PR 1, parked. Debug: launch a profile app with `--args --binding-action NAME` to run a Ghostty binding action 2 s after launch; `--binding-action dump-config` logs the config Ghostty loaded.

Run `.build/release/Spacedock` with no arguments to open the shell outside a bundle with a default project.

Stop a generated app with Cmd-Q, `kill <pid>`, or `osascript -e 'tell application id "dev.lubelski.spacedock.SLUG" to quit'`. All three send SIGHUP to the shells and wait up to 2 s.

## Issues

- Work is tracked on a kanban board, the GitHub Project [Spacedock](https://github.com/users/lubelski/projects/3) (number 3, owner `lubelski`), also reachable from the repo's Projects tab. Columns: Todo, In Progress, Done. Items are issues on `lubelski/spacedock`.
- Read with `gh issue list`, `gh issue view`, and `gh project item-list 3 --owner lubelski`. Add a new issue to the board with `gh project item-add 3 --owner lubelski --url <issue url>`, then set its Status with `gh project item-edit` (field `Status`, project id `PVT_kwHOAAL9Js4BqwVL`). Move the card when starting and finishing work.
- Issues express intent and are written by or with the user. Record divergence in comments rather than rewriting intent.

## CLI and UI parity

The CLI should let someone do everything from an agent or a terminal. The UI should also allow almost everything. When adding a capability, add it to the CLI, and add it to the UI unless there is a reason not to.

## Working practices

- Work in a worktree under `.wt/` (for example, `.wt/<branch>/`), not in the primary checkout. Keep the primary checkout on the latest `main` unless the user says otherwise. Pull after merges.
- Commit and push as you work. Small, coherent commits after meaningful milestones.
- Open a pull request when the work is ready for review. Do not merge without the user's authorization.
- Every PR follows `.github/pull_request_template.md`: Overview, Visual Preview, Changes, Notes, in that order. The `pull-request` skill (`.claude/skills/pull-request/SKILL.md`) walks through opening and updating one.
- Put screenshots, recordings, or other concrete evidence in Visual Preview. Upload images with `gh pr create|edit|comment --attach <file>#<alt text>` and reference the file by the same path in the body. The CLI rewrites the path to the uploaded asset. Do not commit screenshots to the repo. UI changes should show the affected window, before and after where useful. Nonvisual changes should include test output, logs, or a reproducible example instead.
- Evidence must come from the actual change, with enough context to interpret it. Capture profile apps, never the user's installed apps or desktop. Label mocks and unverified behavior. Never substitute a proposed design for a screenshot of working UI. If visual capture is unavailable, say why, give the alternative evidence, and name the remaining verification gap.
- Do not ask the user to run a terminal command unless the agent literally cannot run it (an interactive login, a prompt that needs the user's password, a permission dialog). Run it yourself and report the result.
- Store research in `research/`. Date findings, link sources, separate verified observations from inferences.
- Keep the learning map in `.transient-learning-map/` current. It is gitignored.
- Testing keys and windows without Accessibility: `scripts/keypost.swift` posts a key press to a pid (the app must be frontmost, so bring it forward with `open`, post, then hand focus back with `osascript -e 'tell application "NAME" to activate'`); `scripts/wins.swift` lists an app's windows by owner name for counting or `screencapture -l <id>`. Both are one `swiftc -O` away. Use them on a profile, never on the user's installed apps.
- Do not claim behavior was tested from documentation alone. Dock, Cmd-Tab, and Spaces behavior must be observed, by the agent where a screenshot can show it, or by the user where it is interactive.
