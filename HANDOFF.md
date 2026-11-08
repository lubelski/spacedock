# Handoff

Written 2026-11-08 at the end of the first session, updated the same day after the second. Read this, then `AGENTS.md`, then `.transient-learning-map/orientation.md`.

## What this is

Spacedock makes each project the user works on its own macOS application. Own bundle id, icon, color, Dock tile, Cmd-Tab entry, Space assignment. Inside: a terminal now, a browser next.

The idea came from a frustration with single-window developer tools: one app for many projects defeats the Dock, Cmd-Tab, and Spaces. The user tried a VM-per-Space approach earlier for the same reason. "Application" is the only unit macOS gives an icon, a switcher slot, and a Space binding at once, so each project becomes one.

## State

Remote: https://github.com/lubelski/spacedock (public, `main` tracks `origin/main`). Installed bundles: four under `~/Applications/Spacedock/` (run `Spacedock list`), registered in `~/Library/Application Support/Spacedock/projects.json`. `Probe` is a throwaway for the icon-refresh test (see `research/2026-11-08-install-and-quit.md`); remove it with `Spacedock remove probe`. `out/` holds stale pre-rename bundles, gitignored, safe to delete.

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
- `Sources/Spacedock/Registry.swift`: `projects.json` under `~/Library/Application Support/Spacedock/`, install directory `~/Applications/Spacedock/`.
- `Sources/Spacedock/Settings.swift`: `settings.json` next to the registry. Font, padding, cursor style, scrollback. Defaults: system mono 13, 8 pt, blinking bar, 10000 lines.
- `Sources/Spacedock/App.swift`: `AppDelegate`, one window per terminal with a padded container, main menu, graceful quit (SIGHUP to shells, 2 s SIGKILL fallback), SIGTERM handler.
- `Sources/Spacedock/main.swift`: `add`, `regenerate`, `list`, `remove`, `generate` subcommands, or run as app.

## Decisions so far

1. Standalone repo, not a module of a larger app. The open questions were about macOS, and a negative result should not disturb anything else.
2. Copy the binary into each bundle rather than split a framework. Revisit when a larger component joins or update propagation matters.
3. SwiftTerm as the first terminal. libghostty is a candidate replacement behind the same window. The user's view: rewriting the bridge later is acceptable ("agents are good at rewriting").
4. Window layer (splits, padding, cursor style, font) is ours regardless of emulator. Design it against a small protocol so the emulator can swap.

## Open threads

In the order the agent would take them. The user has not confirmed this order.

1. Done: install location and registry.
2. Done except the observation: regenerate in place and confirm the Dock icon refreshes. Probe.app is set up for the user to look at.
3. Done except splits (`NSSplitView`): padding, cursor style, font, and scrollback are settings.
4. libghostty spike. Try `rijieli/libghostty-spm` at tag `ghostty-1.4.0` (pinned to stable Ghostty) or `Lakr233/libghostty-spm` (tracks main weekly). Both wrap the internal embedder API that upstream says will change. Upstream `libghostty-vt` 1.0.0 is parsing and state only, no renderer. A first-party Swift Metal renderer was announced by Mitchell Hashimoto as coming soon, not released as of this search.
5. Embedded browser: a WKWebView window per project for PR and ticket pages. Cookies live in the app's own WebKit container, so expect per-project login or a broker.
6. Shared state and secrets across project apps. Keychain ACLs follow the designated requirement, which includes the bundle id, and ad-hoc signatures are each unique. Chrome's answer is one broker process that owns secrets. Not needed until a browser joins.
7. Done: graceful quit.
8. Binary updates: `regenerate` rewrites bundles but running apps keep the old binary. A `Spacedock restart` that quits, regenerates, and relaunches would close the loop.

## Issue tracking

GitHub Project https://github.com/users/lubelski/projects/3, whose items are issues on `lubelski/spacedock`, one per open thread above. Decided 2026-11-08.

## Gotchas

- The bundle id prefix changed from `dev.lubelski.projectshell` to `dev.lubelski.spacedock` in the rename commit. Space assignments made against the old ids do not carry over.
- `out/` and `.transient-learning-map/` are gitignored. The learning map was gitignored without asking the user first, which the user's global instructions say to do. Raise it if it matters.
- Do not call `NSApp.terminate` from inside a `DispatchSource` handler. `terminateLater` spins a nested run loop that cannot drain the main dispatch queue while a main-queue block is on the stack. `App.swift` defers through `RunLoop.main.perform`.
- Interactive zsh ignores SIGTERM. Quit sends SIGHUP.
- `Bundle.main.executableURL` is what `generate` copies. Running `generate` from a bundle copies that bundle's binary, which is fine, but a stale `out/` binary will not pick up new code until you rebuild and regenerate.

## Links

- GitHub: https://github.com/lubelski/spacedock

- Project board: https://github.com/users/lubelski/projects/3
- Issues: https://github.com/lubelski/spacedock/issues
- SwiftTerm: https://github.com/migueldeicaza/SwiftTerm
- libghostty packages: https://github.com/rijieli/libghostty-spm, https://github.com/Lakr233/libghostty-spm
