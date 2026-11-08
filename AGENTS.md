# Spacedock agent guidance

Spacedock generates one macOS application per project, so the Dock, Cmd-Tab, and Spaces treat each project as its own app. Each generated app runs the Spacedock shell: a window in the project color holding a terminal, later a browser. A separate prime app, `~/Applications/Spacedock.app`, is a menu bar control panel for the project apps.

Read `HANDOFF.md` first in a new session, then `.transient-learning-map/orientation.md`.

## Build and run

```sh
swift build -c release
.build/release/Spacedock add --name NAME --color "#RRGGBB" --folder PATH
open ~/Applications/Spacedock/NAME.app
.build/release/Spacedock install        # the prime app, ~/Applications/Spacedock.app
.build/release/Spacedock regenerate     # after every rebuild: rewrites prime and all installed bundles
.build/release/Spacedock restart [SLUG ...]   # quit running apps, regenerate, relaunch them (prime too)
.build/release/Spacedock list           # slug, color, running|stopped, folder, name
.build/release/Spacedock set SLUG KEY=VALUE ...      # per-project override; ghostty.<key> for raw Ghostty config
.build/release/Spacedock set --global KEY=VALUE ...  # edits settings.json
.build/release/Spacedock show SLUG      # effective settings for one project
.build/release/Spacedock remove SLUG
```

`add` records the project in `~/Library/Application Support/Spacedock/projects.json` and installs `~/Applications/Spacedock/NAME.app`. `regenerate` rebuilds every registered bundle from the current binary. `generate --name ... [--out DIR]` still writes an unregistered one-off bundle (default `out/`).

The executable is a copy of the Spacedock binary. `Contents/Resources/project.json` holds name, slug, color, and folder. Bundle id is `dev.lubelski.spacedock.<slug>`. The bundle is ad-hoc signed.

Window settings (font, padding, cursor style, scrollback, emulator) are read at launch from `~/Library/Application Support/Spacedock/settings.json`, written with defaults on first `add`. `emulator` is `ghostty` (default) or `swiftterm` (compatibility only, no new work); both are linked. Each project in `projects.json` may carry a `settings` object overriding any of those fields and a `ghostty` map of raw Ghostty config keys; a global `ghostty` map lives in `settings.json`. Project keys win. Apps read overrides from the registry at launch, so `set` needs a relaunch, not a regenerate. Raw Ghostty keys do nothing in the swiftterm emulator. The window layer talks to the emulator only through `TerminalPane` in `Sources/Spacedock/Pane.swift`.

The prime app runs as a menu bar item (`LSUIElement`, bundle id `dev.lubelski.spacedock`, role from the `SpacedockRole` Info.plist key). Its menu lists projects with a running indicator and launches or activates them. `open ~/Applications/Spacedock.app` while it runs, or launch it with `--args --panel`, shows the control panel: project list with launch, show, quit, restart, regenerate, remove; an add form; the settings form. Project windows stay in their own apps.

Run `.build/release/Spacedock` with no arguments to open the shell outside a bundle with a default project.

Stop a generated app with Cmd-Q, `kill <pid>`, or `osascript -e 'tell application id "dev.lubelski.spacedock.SLUG" to quit'`. All three send SIGHUP to the shells and wait up to 2 s.

## Issues

- Work is tracked on a kanban board, the GitHub Project [Spacedock](https://github.com/users/lubelski/projects/3) (number 3, owner `lubelski`), also reachable from the repo's Projects tab. Columns: Todo, In Progress, Done. Items are issues on `lubelski/spacedock`.
- Read with `gh issue list`, `gh issue view`, and `gh project item-list 3 --owner lubelski`. Add a new issue to the board with `gh project item-add 3 --owner lubelski --url <issue url>`, then set its Status with `gh project item-edit` (field `Status`, project id `PVT_kwHOAAL9Js4BqwVL`). Move the card when starting and finishing work.
- Issues express intent and are written by or with the user. Record divergence in comments rather than rewriting intent.

## CLI and UI parity

The CLI should let someone do everything from an agent or a terminal. The UI should also allow almost everything. When adding a capability, add it to the CLI, and add it to the UI unless there is a reason not to.

## Working practices

- Commit as you work. Small, coherent commits after meaningful milestones.
- Store research in `research/`. Date findings, link sources, separate verified observations from inferences.
- Keep the learning map in `.transient-learning-map/` current. It is gitignored.
- Do not claim behavior was tested from documentation alone. Dock, Cmd-Tab, and Spaces behavior must be observed, by the agent where a screenshot can show it, or by the user where it is interactive.
