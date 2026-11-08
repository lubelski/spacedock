# Spacedock

One macOS application per project. Each project gets its own bundle id, icon, color, Dock tile, Cmd-Tab entry, and Space assignment, with a terminal inside.

The question under test: if each project is its own `.app` bundle with its own bundle identifier, icon, and color, does macOS give us the Dock, Cmd-Tab, and Spaces behavior that a single shared app cannot? The first content of each project app is a terminal, so the experiment can be judged with real work.

## Build

```sh
swift build -c release
```

## Install a project app

```sh
.build/release/Spacedock add --name Hoard --color "#0F766E" --folder ~/dev/hoard
open ~/Applications/Spacedock/Hoard.app
```

`add` records the project in `~/Library/Application Support/Spacedock/projects.json` and installs `~/Applications/Spacedock/<Name>.app`. After a rebuild, `regenerate` rewrites every installed bundle, and `restart` quits the running apps, regenerates, and relaunches them. `list` and `remove <slug>` manage the registry. `generate --name ... [--out DIR]` writes an unregistered one-off bundle.

The bundle's executable is a copy of the `Spacedock` binary. Its `Contents/Resources/project.json` holds the name, slug, color, and folder. The bundle is ad-hoc signed.

`install` writes the prime app, `~/Applications/Spacedock.app`: a menu bar item that lists the projects, shows which are running, and launches or activates them. Open it again for the control panel, which adds and removes projects, restarts them, and edits settings.

Window settings (font, padding, cursor style, scrollback, emulator) are read from `~/Library/Application Support/Spacedock/settings.json`, written with defaults on first `add`. The emulator is libghostty by default; SwiftTerm remains as `emulator: swiftterm`. Any project can override those fields and add raw [Ghostty config](https://ghostty.org/docs/config/reference) keys:

```sh
.build/release/Spacedock set hoard padding=16 ghostty.font-family="JetBrains Mono" ghostty.background-opacity=0.9
.build/release/Spacedock set --global ghostty.cursor-style-blink=true
.build/release/Spacedock show hoard
```

An empty value removes an override. Changes apply at the project's next launch. The control panel has the same controls under each project's menu and in Settings.

Run `.build/release/Spacedock` with no arguments to open the app outside a bundle with a default project.

## Layout

- `Sources/Spacedock/Project.swift`: the project definition and how the app reads it from its bundle.
- `Sources/Spacedock/Generator.swift`: writes the bundle, Info.plist, and icon.
- `Sources/Spacedock/Registry.swift`: the project list and install directory.
- `Sources/Spacedock/Settings.swift`: window-layer settings.
- `Sources/Spacedock/Pane.swift`: the `TerminalPane` protocol and its SwiftTerm and libghostty implementations.
- `Sources/Spacedock/App.swift`: the project app delegate, window, menu, terminal, and quit handling.
- `Sources/Spacedock/Prime.swift`: the prime app, menu bar item, and control panel.
- `Sources/Spacedock/main.swift`: argument dispatch.
- `research/`: dated findings.
