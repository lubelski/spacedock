# Handoff

Written 2026-11-08 at the end of the first session, updated the same day after the second. Read this, then `AGENTS.md`, then `.transient-learning-map/orientation.md`.

## What this is

Spacedock makes each project the user works on its own macOS application. Own bundle id, icon, color, Dock tile, Cmd-Tab entry, Space assignment. Inside: a terminal now, a browser next.

The idea came from a frustration with single-window developer tools: one app for many projects defeats the Dock, Cmd-Tab, and Spaces. The user tried a VM-per-Space approach earlier for the same reason. "Application" is the only unit macOS gives an icon, a switcher slot, and a Space binding at once, so each project becomes one.

## State

Session 4 (2026-11-08) on branch `management-window` (worktree `.wt/management-window`, issue #12): the control panel is now two windows. Primary menu bar click opens project management (vertical list, gear); the gear or Cmd-, opens Settings, rebuilt in the System Settings style after the user rejected a VS Code-styled first pass. `SettingsWindow.swift` holds a `SettingSpec` schema that drives rows, search, sidebar, and reset; Ghostty keys are a key/value `Table`. Verified by window-id screenshots on profile `management-ui`; no clicks (Accessibility denied). Not merged. See `research/2026-11-08-management-settings.md`.

Remote: https://github.com/lubelski/spacedock (public, `main` tracks `origin/main`). Installed bundles: four under `~/Applications/Spacedock/` (run `Spacedock list`), registered in `~/Library/Application Support/Spacedock/projects.json`. `Probe` is a throwaway for the icon-refresh test (see `research/2026-11-08-install-and-quit.md`); remove it with `Spacedock remove probe`. `out/` holds stale pre-rename bundles, gitignored, safe to delete.

Session 3 (2026-11-08), later: the user chose the unbind route over the fork. `GhosttyPane` unbinds `super+n`, `super+shift+w`, `super+q` so the menu bar handles them; `Package.swift` is back on upstream `Lakr233/libghostty-spm`. The fork and its PR 1 stay as a parked reference. Verified by real key events (`scripts/keypost.swift`, CGEvent posted to the pid while the app was frontmost): Cmd-N opened a second window, Cmd-W closed one, Cmd-Q quit with no orphan shells.

Session 3 (2026-11-08), earlier, superseded: explored Ghostty's keybinding system as the authority for shortcuts. The ghostty view swallows bound keys (Cmd-N, Cmd-Shift-W, Cmd-Q, ...) before the menu bar and emits Ghostty actions; libghostty-spm had no hook for window-level ones. Added `TerminalWindowAction` + `TerminalSurfaceWindowActionDelegate` (surface-targeted) and `TerminalController.windowActionDelegate` (app-targeted: `quit`, `close_all_windows`) to the package on a branch, with tests and README text; `GhosttyPane` adopts both and forwards to `AppDelegate` through `TerminalPane.onWindowRequest`. `GhosttyPane.hangUp` now sets `controller = nil`, which tears the surface down and hangs up the shell; removing the view did not. Verified on the dev profile via `--binding-action`: new_window opened a second window and shell, quit exited, Apple-event quit left no orphans. The package change lives on `lubelski/libghostty-spm` branch `window-action-delegate` as PR 1 into that fork, parked. Do not open an upstream PR without the user. If splits or tabs ever need Ghostty's actions, that branch is the starting point. We do not own Zig or the Ghostty patch stack.

Session 3 (2026-11-08) added profiles (`Profile.swift`): `--profile NAME` or `SPACEDOCK_PROFILE` gives agent copies their own bundle ids, registry, settings, and bundles under Application Support, a name suffix, an icon badge, and background launch (`open -g`, no `activate`, `orderFront`). The running app reads its profile from the `SpacedockProfile` Info.plist key. `quit [SLUG ...]` added. Verified: `add --profile dev` wrote separate files; `restart --profile dev hoard` launched without changing the frontmost app (iTerm2 before and after); default registry untouched. Not verified: Space assignment through the Dock for a profile's apps (user-side, one-time).

Session 3 (2026-11-08) made libghostty the default (user decision) and added per-project overrides: `Project.settings` (a `SettingsOverride`, all fields optional) and `Project.ghostty` (raw keys), plus `Settings.ghostty` globally. `set`, `set --global`, `show` on the CLI; a Project Settings sheet and a global Ghostty editor in the panel. Apps merge overrides from the registry at launch. Verified: `set hoard ghostty.font-size=20` then relaunch grew the text. Not verified: `cursor-color` override did not visibly change the cursor (cause unknown; the package theme sets no cursor keys), and the panel sheets were not exercised by click.

Session 3 (2026-11-08) also ran the libghostty spike (`research/2026-11-08-libghostty-spike.md`). `Pane.swift` holds a `TerminalPane` protocol with SwiftTerm and libghostty (Lakr233/libghostty-spm) implementations. `settings.json` `emulator` picks one; default `swiftterm`. A ghostty-backed project app was generated, launched, screenshotted, and quit cleanly. Open: which emulator should be the default, and the ghostty pane's copy, paste, and font behavior.

Session 3 (2026-11-08) also added `Spacedock restart [SLUG ...]`: quit running project apps and the prime app through the Apple event, regenerate every bundle, relaunch what was running. Verified: one running project plus prime restarted with new pids in 0.93 s. `list` shows running state.

Session 3 (2026-11-08) added the prime app (`Spacedock install`, `~/Applications/Spacedock.app`): menu bar item, control panel with project list, add form, settings form. Verified: runs as UIElement, panel renders with correct running state (screenshot). Not yet observed: whether activating a project from the menu switches to its Space (issue #8 comment).

Session 2 (2026-11-08) added: install location and registry (`add`, `regenerate`, `list`, `remove`), `settings.json` for font, padding, cursor, scrollback, and graceful quit via Cmd-Q, AppleScript `quit`, and SIGTERM. Verified except the Dock icon refresh after regeneration, which the user still has to look at.

Verified on 2026-11-08 (macOS 26, Xcode 27.2, Swift 6.4.2, SwiftTerm 1.99.3):

- Generated bundles launch via `open` with no Gatekeeper prompt. Ad-hoc signature is enough.
- Two generated apps appear in `lsappinfo` as separate applications with their own bundle ids, next to the other running apps.
- Dock shows two tiles with the generated icons. Menu bar shows the project name.
- Title bar tints with the project color. Login zsh opens in the project folder with the user's prompt theme.
- User tried Cmd-Tab and Space assignment by hand and said it "works incredibly well". Not observed by the agent.

Details: `research/2026-11-08-first-launch.md`.

## Code

- `Sources/Spacedock/Project.swift`: the project definition, read from `project.json` in the bundle. `bundleIDPrefix = "dev.lubelski.spacedock"`.
- `Sources/Spacedock/Generator.swift`: writes the bundle (Info.plist, PkgInfo, copied executable, `project.json`, icns via `iconutil`, `codesign --sign -`).
- `Sources/Spacedock/Profile.swift`: `Profile.current`, set from `--profile`/env in the CLI and from Info.plist in the app. Bundle prefix, support, install, and prime directories derive from it.
- `Sources/Spacedock/Registry.swift`: `projects.json` under `~/Library/Application Support/Spacedock/`, install directory `~/Applications/Spacedock/`.
- `Sources/Spacedock/Settings.swift`: `settings.json` next to the registry. Font, padding, cursor style, scrollback, emulator, raw `ghostty` map. Defaults: system mono 13, 8 pt, blinking bar, 10000 lines, ghostty. `SettingsOverride` is the per-project partial; `Settings.applying` merges. Custom `init(from:)` so missing keys keep defaults.
- `Sources/Spacedock/Prime.swift`: `PrimeDelegate` (status item, panel window), `ProjectsModel` (registry, settings, running state via `NSRunningApplication`, launch/activate/quit/restart/add/remove/regenerate), SwiftUI `ControlPanelView`.
- `Sources/Spacedock/Pane.swift`: `TerminalPane`, `SwiftTermPane` (wraps `LocalProcessTerminalView`), `GhosttyPane` (subclasses `AppTerminalView`, exec backend), `PaneFactory`.
- `Sources/Spacedock/App.swift`: `AppDelegate`, one window per terminal with a padded container, main menu, graceful quit (SIGHUP to shells, 2 s SIGKILL fallback), SIGTERM handler.
- `Sources/Spacedock/main.swift`: `add`, `install`, `regenerate`, `list`, `remove`, `generate` subcommands, or run as app. Role (prime or project) comes from the `SpacedockRole` Info.plist key.

## Decisions so far

1. Standalone repo, not a module of a larger app. The open questions were about macOS, and a negative result should not disturb anything else.
2. Copy the binary into each bundle rather than split a framework. Revisit when a larger component joins or update propagation matters.
3. SwiftTerm as the first terminal. libghostty now sits behind the same window as a second `TerminalPane`; the default is still SwiftTerm until the user decides.
4. Window layer (splits, padding, cursor style, font) is ours regardless of emulator. `TerminalPane` in `Pane.swift` is the protocol; both emulators implement it.

## Open threads

In the order the agent would take them. The user has not confirmed this order.

1. Done: install location and registry.
2. Done except the observation: regenerate in place and confirm the Dock icon refreshes. Probe.app is set up for the user to look at.
3. Done except splits (`NSSplitView`): padding, cursor style, font, and scrollback are settings.
4. Done: libghostty spike. Remaining: default emulator decision, copy and paste and font in the ghostty pane. Try `rijieli/libghostty-spm` at tag `ghostty-1.4.0` (pinned to stable Ghostty) or `Lakr233/libghostty-spm` (tracks main weekly). Both wrap the internal embedder API that upstream says will change. Upstream `libghostty-vt` 1.0.0 is parsing and state only, no renderer. A first-party Swift Metal renderer was announced by Mitchell Hashimoto as coming soon, not released as of this search.
5. Embedded browser: a WKWebView window per project for PR and ticket pages. Cookies live in the app's own WebKit container, so expect per-project login or a broker.
6. Shared state and secrets across project apps. Keychain ACLs follow the designated requirement, which includes the bundle id, and ad-hoc signatures are each unique. Chrome's answer is one broker process that owns secrets. Not needed until a browser joins.
7. Done: graceful quit.
8. Done: `Spacedock restart`, and Restart per project in the control panel.

## Issue tracking

GitHub Project https://github.com/users/lubelski/projects/3, whose items are issues on `lubelski/spacedock`, one per open thread above. Decided 2026-11-08.

## Gotchas

- The bundle id prefix changed from `dev.lubelski.projectshell` to `dev.lubelski.spacedock` in the rename commit. Space assignments made against the old ids do not carry over.
- `out/` and `.transient-learning-map/` are gitignored. The learning map was gitignored without asking the user first, which the user's global instructions say to do. Raise it if it matters.
- Anything that may end in `terminateLater` must be entered from the run loop, not from a dispatch block or an emulator callback. `onWindowRequest` hops through `RunLoop.main.perform` for this reason; the first version hung on `quit`.
- Ghostty addresses `quit` to the app target, not the surface. A surface delegate alone never sees it.
- `restart` once looked up the prime app by the unprofiled bundle id and quit the user's installed prime from a dev-profile run. Every bundle id lookup goes through `Profile.current.bundlePrefix` now. Grep for `Project.bundleIDPrefix` before adding another.
- `Bundle.module` in a generated app needs the SwiftPM resource bundle under `Contents/Resources`. The generator copies every `*.bundle` next to the source executable. Without it GhosttyTerminal traps at first use.
- A windowless accessory app's first window lands on whichever screen AppKit picks. `showPanel` centers on `NSScreen.main` explicitly; without that the panel opened on the external display.
- `screencapture -x file` captures the main display only. Use `-l <windowid>` (ids from `CGWindowListCopyWindowInfo`) to capture a window on another display.
- Do not call `NSApp.terminate` from inside a `DispatchSource` handler. `terminateLater` spins a nested run loop that cannot drain the main dispatch queue while a main-queue block is on the stack. `App.swift` defers through `RunLoop.main.perform`.
- Interactive zsh ignores SIGTERM. Quit sends SIGHUP.
- `Bundle.main.executableURL` is what `generate` copies. Running `generate` from a bundle copies that bundle's binary, which is fine, but a stale `out/` binary will not pick up new code until you rebuild and regenerate.

## Links

- GitHub: https://github.com/lubelski/spacedock

- Project board: https://github.com/users/lubelski/projects/3
- Issues: https://github.com/lubelski/spacedock/issues
- SwiftTerm: https://github.com/migueldeicaza/SwiftTerm
- libghostty packages: https://github.com/rijieli/libghostty-spm, https://github.com/Lakr233/libghostty-spm
