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

`install` writes the prime app, `~/Applications/Spacedock.app`. Click its menu bar icon to open the management window: a vertical project list with running status, Launch/Show, and per-project actions. Right-click, Control-click, or Option-click the icon for the quick-access menu. Opening the app again also shows project management.

The gear in that window, **Settings…** in the menu, or Cmd-, opens a separate settings window in the System Settings style: a searchable sidebar of sections, one grouped form per section, and a Reset on any row that differs from its default. Changes save when a control commits; there is no Save button. Raw Ghostty keys are a key/value table. Project-specific overrides remain in each project's menu.

From a terminal, `open ~/Applications/Spacedock.app --args --panel` opens management on launch; `open ~/Applications/Spacedock.app --args --settings` opens settings on launch (`--settings-section ghostty` picks a section). Launch arguments apply when the app is not already running. The `set`, `set --global`, and `show` commands remain available for managing settings without the UI.

Window settings (font, padding, cursor style, scrollback, emulator) are read from `~/Library/Application Support/Spacedock/settings.json`, written with defaults on first `add`. The emulator is libghostty by default; SwiftTerm remains as `emulator: swiftterm`. Any project can override those fields and add raw [Ghostty config](https://ghostty.org/docs/config/reference) keys:

```sh
.build/release/Spacedock set hoard padding=16 ghostty.font-family="JetBrains Mono" ghostty.background-opacity=0.9
.build/release/Spacedock set --global ghostty.cursor-style-blink=true
.build/release/Spacedock show hoard
```

An empty value removes an override. Changes apply at the project's next launch. The control panel has the same controls under each project's menu and in Settings.

Run `.build/release/Spacedock` with no arguments to open the app outside a bundle with a default project.

## Profiles

`--profile NAME` (or `SPACEDOCK_PROFILE`) on any command gives a separate Spacedock: its own bundle ids, registry, settings, and bundles under `~/Library/Application Support/Spacedock/profiles/NAME/`. Its apps carry a name suffix and an icon badge and launch without taking focus. Development copies live in a profile so they never collide with the installed one.

## Layout

- `Sources/Spacedock/Project.swift`: the project definition and how the app reads it from its bundle.
- `Sources/Spacedock/Generator.swift`: writes the bundle, Info.plist, and icon.
- `Sources/Spacedock/Profile.swift`: which Spacedock this is; paths and bundle id prefix follow it.
- `Sources/Spacedock/Registry.swift`: the project list and install directory.
- `Sources/Spacedock/Settings.swift`: window-layer settings.
- `Sources/Spacedock/Pane.swift`: the `TerminalPane` protocol and its SwiftTerm and libghostty implementations.
- `Sources/Spacedock/App.swift`: the project app delegate, window, menu, terminal, and quit handling.
- `Sources/Spacedock/Prime.swift`: the prime app, menu bar item, and project management window.
- `Sources/Spacedock/SettingsWindow.swift`: the settings schema and the settings window.
- `Sources/Spacedock/main.swift`: argument dispatch.
- `research/`: dated findings.
