# Spacedock

Proof of concept for Tau [ENG-239](https://linear.app/interstellar-cafe/issue/ENG-239/research-one-macos-application-per-tau-project): one macOS application per project.

The question under test: if each project is its own `.app` bundle with its own bundle identifier, icon, and color, does macOS give us the Dock, Cmd-Tab, and Spaces behavior that a single shared app cannot? The first content of each project app is a terminal, so the experiment can be judged with real work.

## Build

```sh
swift build -c release
```

## Generate a project app

```sh
.build/release/Spacedock generate --name Tau --color "#D97706" --folder ~/dev/tau
open "out/Tau.app"
```

`generate` writes `out/<Name>.app`. The bundle's executable is a copy of the `Spacedock` binary. Its `Contents/Resources/project.json` holds the name, slug, color, and folder. The bundle is ad-hoc signed.

Run `.build/release/Spacedock` with no arguments to open the app outside a bundle with a default project.

## Layout

- `Sources/Spacedock/Project.swift`: the project definition and how the app reads it from its bundle.
- `Sources/Spacedock/Generator.swift`: writes the bundle, Info.plist, and icon.
- `Sources/Spacedock/App.swift`: the app delegate, window, menu, and terminal.
- `Sources/Spacedock/main.swift`: argument dispatch.
- `research/`: dated findings.
