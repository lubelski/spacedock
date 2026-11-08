# Handoff

Written 2026-11-08 at the end of the first session. Read this, then `AGENTS.md`, then `.transient-learning-map/orientation.md`.

## What this is

Spacedock makes each project the user works on its own macOS application. Own bundle id, icon, color, Dock tile, Cmd-Tab entry, Space assignment. Inside: a terminal now, a browser next, Tau conversations maybe later.

The idea came from a frustration with Tau (`~/dev/tau`): one app for many projects defeats the Dock, Cmd-Tab, and Spaces. The user tried a VM-per-Space approach earlier for the same reason. "Application" is the only unit macOS gives an icon, a switcher slot, and a Space binding at once, so each project becomes one.

## State

Three commits on `main`, no remote. Nothing is running. The old `~/dev/project-shell/out/` bundles were killed and the directory no longer exists after the rename to `~/dev/spacedock`.

Verified on 2026-11-08 (macOS 26, Xcode 27.2, Swift 6.4.2, SwiftTerm 1.99.3):

- Generated bundles launch via `open` with no Gatekeeper prompt. Ad-hoc signature is enough.
- Two generated apps appear in `lsappinfo` as separate applications with their own bundle ids, next to the installed Tau.
- Dock shows two tiles with the generated icons. Menu bar shows the project name.
- Title bar tints with the project color. Login zsh opens in the project folder with the user's prompt theme.
- User tried Cmd-Tab and Space assignment by hand and said it "works incredibly well". Not observed by the agent.

Details: `research/2026-11-08-first-launch.md`.

## Code

- `Sources/Spacedock/Project.swift`: the project definition, read from `project.json` in the bundle. `bundleIDPrefix = "dev.lubelski.spacedock"`.
- `Sources/Spacedock/Generator.swift`: writes the bundle (Info.plist, PkgInfo, copied executable, `project.json`, icns via `iconutil`, `codesign --sign -`).
- `Sources/Spacedock/App.swift`: `AppDelegate`, one window per terminal, main menu, SwiftTerm `LocalProcessTerminalView`.
- `Sources/Spacedock/main.swift`: `generate` subcommand or run as app.

## Decisions so far

1. Separate repo from Tau. The open questions were about macOS, not Tau's code, and a negative result should not disturb Tau.
2. Copy the binary into each bundle rather than split a framework. Revisit when Tau core joins or update propagation matters.
3. SwiftTerm as the first terminal. libghostty is a candidate replacement behind the same window. The user's view: rewriting the bridge later is acceptable ("agents are good at rewriting").
4. Window layer (splits, padding, cursor style, font) is ours regardless of emulator. Design it against a small protocol so the emulator can swap.

## Open threads

In the order the agent would take them. The user has not confirmed this order.

1. Stable install location, candidate `~/Applications/Spacedock/`, and a registry (`projects.json`) so every bundle can be regenerated after a binary update.
2. Regenerate in place and confirm the Dock icon refreshes rather than serving a cached icon.
3. Window layer as settings: splits (`NSSplitView`), padding (container view with insets), cursor style (`TerminalOptions.cursorStyle`, blinking bar wanted), font. Scrollback above SwiftTerm's default of 500.
4. libghostty spike. Try `rijieli/libghostty-spm` at tag `ghostty-1.4.0` (pinned to stable Ghostty) or `Lakr233/libghostty-spm` (tracks main weekly). Both wrap the internal embedder API that upstream says will change. Upstream `libghostty-vt` 1.0.0 is parsing and state only, no renderer. A first-party Swift Metal renderer was announced by Mitchell Hashimoto as coming soon, not released as of this search.
5. Embedded browser: a WKWebView window per project for PR and ticket pages. Cookies live in the app's own WebKit container, so expect per-project login or a broker.
6. Shared state and secrets across project apps. Keychain ACLs follow the designated requirement, which includes the bundle id, and ad-hoc signatures are each unique. Chrome's answer is one broker process that owns secrets. Not needed until a browser or Tau session joins.
7. Graceful quit: respond to AppleScript `quit` and SIGTERM, closing shells cleanly.

## Pending question for the user

Should the open threads become sub-issues under ENG-239, or top-level issues in the Spacedock project with ENG-239 closed as the research it was? The agent leans toward the second.

## Gotchas

- The bundle id prefix changed from `dev.lubelski.projectshell` to `dev.lubelski.spacedock` in the rename commit. Space assignments made against the old ids do not carry over.
- `out/` and `.transient-learning-map/` are gitignored. The learning map was gitignored without asking the user first, which the user's global instructions say to do. Raise it if it matters.
- Generated apps ignore AppleScript `quit`. Use Cmd-Q or `kill`.
- `Bundle.main.executableURL` is what `generate` copies. Running `generate` from a bundle copies that bundle's binary, which is fine, but a stale `out/` binary will not pick up new code until you rebuild and regenerate.

## Links

- Linear project: https://linear.app/interstellar-cafe/project/spacedock-91da3844ba79
- ENG-239 (origin research ticket, now in Spacedock): https://linear.app/interstellar-cafe/issue/ENG-239
- ENG-167 (Tau, per-Space link routing, related but distinct): https://linear.app/interstellar-cafe/issue/ENG-167
- SwiftTerm: https://github.com/migueldeicaza/SwiftTerm
- libghostty packages: https://github.com/rijieli/libghostty-spm, https://github.com/Lakr233/libghostty-spm
