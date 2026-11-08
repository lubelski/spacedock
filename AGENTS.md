# Spacedock agent guidance

Spacedock generates one macOS application per project, so the Dock, Cmd-Tab, and Spaces treat each project as its own app. Each generated app runs the Spacedock shell: a window in the project color holding a terminal, later a browser, later Tau conversations.

Read `HANDOFF.md` first in a new session, then `.transient-learning-map/orientation.md`.

## Build and run

```sh
swift build -c release
.build/release/Spacedock generate --name NAME --color "#RRGGBB" --folder PATH [--out DIR]
open "out/NAME.app"
```

`generate` writes `DIR/NAME.app` (default `out/`). The executable is a copy of the Spacedock binary. `Contents/Resources/project.json` holds name, slug, color, and folder. Bundle id is `dev.lubelski.spacedock.<slug>`. The bundle is ad-hoc signed.

Run `.build/release/Spacedock` with no arguments to open the shell outside a bundle with a default project.

Stop a generated app with Cmd-Q or `kill <pid>`. It does not respond to AppleScript `quit`.

## Linear

- Project: [Spacedock](https://linear.app/interstellar-cafe/project/spacedock-91da3844ba79) (P-ENG-14, team Interstellar Engineers).
- Origin ticket: [ENG-239](https://linear.app/interstellar-cafe/issue/ENG-239), research for Tau. It now lives in this project.
- Tickets express intent and are written by or with the user. Record divergence in comments rather than rewriting intent.

## Relationship to Tau

Spacedock grew out of Tau (`~/dev/tau`, `CHARTER.md` there). Whether Tau's conversation UI becomes a component inside a Spacedock project app, or Spacedock becomes a feature of Tau, is an open charter question. Do not wire Tau sessions into Spacedock without that decision.

## Working practices

- Commit as you work. Small, coherent commits after meaningful milestones.
- Store research in `research/`. Date findings, link sources, separate verified observations from inferences.
- Keep the learning map in `.transient-learning-map/` current. It is gitignored.
- Do not claim behavior was tested from documentation alone. Dock, Cmd-Tab, and Spaces behavior must be observed, by the agent where a screenshot can show it, or by the user where it is interactive.
