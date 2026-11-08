# Install location, registry, window settings, graceful quit

Date: 2026-11-08, second session. macOS 26 (Darwin 27.2.0), Swift 6.4.2, SwiftTerm 1.99.3.

## Verified

- `Spacedock add` wrote `~/Library/Application Support/Spacedock/projects.json` and `settings.json`, and installed `~/Applications/Spacedock/{Tau,Hoard,Spacedock}.app`. Both Tau and Hoard launched from there and appeared in `lsappinfo` under their bundle ids.
- `Spacedock regenerate` rewrote all three bundles from the current binary in one run.
- Terminal inset by 8 pt on every side inside a container colored like the terminal background (screenshot of Tau window).
- `osascript -e 'tell application id "dev.lubelski.spacedock.hoard" to quit'` quit the Hoard app and its shell. The first session's "ignores AppleScript quit" was observed before `NSAppleScriptEnabled` and `applicationShouldTerminate` existed. Not isolated which of the two mattered.
- `kill <pid>` (SIGTERM) quit the Tau app and its shell in 0.09 s. No orphan zsh processes afterwards.
- Interactive zsh ignores SIGTERM. With `LocalProcess.terminate()` (SIGTERM) the shell survived until the 2 s SIGKILL fallback. With SIGHUP it exits at once.
- Calling `NSApp.terminate` from inside a `DispatchSource` signal handler hung the quit: `applicationShouldTerminate` returned `terminateLater`, and the nested run loop never ran the main-queue deadline block or SwiftTerm's main-queue `processTerminated`. Deferring the `terminate` call through `RunLoop.main.perform` fixed it. Same handler body, logged to stderr, showed the signal and the delegate call both arriving before the hang.

## Not yet verified

- Dock icon refresh after regeneration. A `Probe.app` was installed red (#DC2626), launched, quit, re-added blue (#2563EB), regenerated, and relaunched. The screen locked before the screenshot. User to report the tile color.
- Cmd-Q. Same code path as the Apple event, not exercised separately.
- Shell title and OSC 7 subtitle updates. Code reads the delegate callbacks; not observed.

## Inference

The bundle's `_CodeSignature` changes the executable bytes, so `md5` of the installed binary never matches `.build/release/Spacedock`. Use `codesign -dv` or a version string to compare, not a hash.
