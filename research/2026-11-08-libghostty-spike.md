# libghostty spike

Date: 2026-11-08, third session. macOS 26, Swift 6.4.2, Lakr233/libghostty-spm 2.2.2026110702 (Ghostty upstream commit 042b16b6146a).

## Package choice

Two Swift packages wrap the libghostty embedder API. `Lakr233/libghostty-spm` had a release the day before (2.2.2026110702), 122 stars, weekly releases pinned to upstream main, a prebuilt XCFramework (80.9 MB download), an AppKit `AppTerminalView`, and an `.exec` backend that spawns the shell through a pty with its own MIT shell integration. `rijieli/libghostty-spm` is a fork pinned to stable Ghostty releases, 0 stars, last push 2026-10-31, same package layout. Chose Lakr233 for the maintenance cadence. Both require Swift 6.2 or later.

## Verified

- Added the dependency and a `TerminalPane` protocol. `SwiftTermPane` wraps `LocalProcessTerminalView` (a subclass could not adopt the delegate protocol: the view is its own delegate for some callbacks and those methods are not `open`). `GhosttyPane` subclasses `AppTerminalView`, builds a `TerminalController` from settings (background, foreground, cursor style and blink, font size and family, window padding, `scrollback-limit`), and starts the shell with `TerminalSurfaceOptions(backend: .exec, workingDirectory:, envVars:, command:)`.
- Bare binary with `emulator: ghostty`: window opened with a login zsh (`/usr/bin/login -flp will /bin/bash --noprofile --norc -c exec -l /bin/zsh`), the user's prompt theme, blinking bar cursor, and padding. Screenshot by window id.
- Generated bundle `GhostProbe.app` with the resource bundle copied into `Contents/Resources`: teal title bar, `~/dev/hoard (main*)` prompt in the project folder, subtitle `~/dev/hoard` from the OSC 7 report. Screenshot by window id.
- SIGTERM to the GhostProbe app: app, `login`, and `zsh` all exited within 3 s. The exec backend's pty closes with the surface, so the shell gets SIGHUP without a pid on our side.
- Release binary grows from 5.4 MB (SwiftTerm only) to 14.2 MB (both emulators linked). The GhosttyTerminal resource bundle is 124 KB.

## Not yet verified

- Scrollback, selection, copy and paste, and Cmd-key handling in the ghostty pane. The window menu's Edit items target `NSText` selectors, which `AppTerminalView` may not answer.
- Font: with `fontName` empty the pane uses Ghostty's bundled default rather than the system monospaced font that SwiftTerm uses. Visible in the screenshots as a different typeface.
- Behavior when the shell exits on its own (`terminalDidClose`). Coded to close the window, not observed.
- Whether `withWindowPaddingX/Y` takes points or pixels. Looked right at 8.

## Inference

The pane protocol is small enough (start, hangUp, isShellRunning, three callbacks) that the emulator is a per-launch setting rather than an architecture decision. Keeping both linked costs 9 MB per generated app and an 80 MB download at first build.
