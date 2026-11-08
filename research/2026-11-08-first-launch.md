# First launch of generated project apps

Date: 2026-11-08. Commit 8f7bdbb. macOS 26 (Darwin 27.2.0), Xcode 27.2, Swift 6.4.2, SwiftTerm 1.99.3.

## Verified

- `Spacedock generate` wrote `out/Tau.app` and `out/Hoard.app`. Each bundle: Info.plist, PkgInfo, `MacOS/<slug>` (copy of the Spacedock binary), `Resources/project.json`, `Resources/AppIcon.icns` (66 KB), `_CodeSignature`.
- `codesign -dv out/Tau.app`: `Identifier=dev.lubelski.spacedock.tau`, `Signature=adhoc`, `TeamIdentifier=not set`.
- `open` launched both without a Gatekeeper prompt.
- `lsappinfo list` showed three applications named around "Tau": `com.lubelski.tau` (installed Tau), `dev.lubelski.spacedock.tau`, `dev.lubelski.spacedock.hoard`.
- Dock showed two new tiles, an orange T and a teal H, with the generated icons.
- Menu bar read "Hoard" when the Hoard window was frontmost.
- Hoard's window had a teal title bar and a login zsh prompt in `~/dev/hoard` with the user's prompt theme.

## Not yet verified

- Cmd-Tab listing. Interactive.
- "Assign To: This Desktop" and Dock-click-jumps-to-Space. Interactive.
- Dock icon cache behavior on regeneration.

## Inference

macOS attributes Dock tiles and application identity to the bundle identifier of the launched bundle, regardless of the executable bytes being identical across bundles. The Chrome app-shim precedent predicted this and it held.
