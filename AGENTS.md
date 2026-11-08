# Spacedock agent guidance

Spacedock generates one macOS application per project, so the Dock, Cmd-Tab, and Spaces treat each project as its own app. Each generated app runs the Spacedock shell: a window in the project color holding a terminal, later a browser.

Read `HANDOFF.md` first in a new session, then `.transient-learning-map/orientation.md`.

## Build and run

```sh
swift build -c release
.build/release/Spacedock add --name NAME --color "#RRGGBB" --folder PATH
open ~/Applications/Spacedock/NAME.app
.build/release/Spacedock regenerate     # after every rebuild: rewrites all installed bundles
.build/release/Spacedock list
.build/release/Spacedock remove SLUG
```

`add` records the project in `~/Library/Application Support/Spacedock/projects.json` and installs `~/Applications/Spacedock/NAME.app`. `regenerate` rebuilds every registered bundle from the current binary. `generate --name ... [--out DIR]` still writes an unregistered one-off bundle (default `out/`).

The executable is a copy of the Spacedock binary. `Contents/Resources/project.json` holds name, slug, color, and folder. Bundle id is `dev.lubelski.spacedock.<slug>`. The bundle is ad-hoc signed.

Window settings (font, padding, cursor style, scrollback) are read at launch from `~/Library/Application Support/Spacedock/settings.json`, written with defaults on first `add`.

Run `.build/release/Spacedock` with no arguments to open the shell outside a bundle with a default project.

Stop a generated app with Cmd-Q, `kill <pid>`, or `osascript -e 'tell application id "dev.lubelski.spacedock.SLUG" to quit'`. All three send SIGHUP to the shells and wait up to 2 s.

## Issues

- Work is tracked in the GitHub Project [Spacedock](https://github.com/users/lubelski/projects/3) (number 3, owner `lubelski`), whose items are issues on `lubelski/spacedock`. Use `gh issue list`, `gh issue view`, and `gh project item-list 3 --owner lubelski`. Add new issues to the project with `gh project item-add 3 --owner lubelski --url <issue url>`.
- Issues express intent and are written by or with the user. Record divergence in comments rather than rewriting intent.

## Working practices

- Commit as you work. Small, coherent commits after meaningful milestones.
- Store research in `research/`. Date findings, link sources, separate verified observations from inferences.
- Keep the learning map in `.transient-learning-map/` current. It is gitignored.
- Do not claim behavior was tested from documentation alone. Dock, Cmd-Tab, and Spaces behavior must be observed, by the agent where a screenshot can show it, or by the user where it is interactive.
