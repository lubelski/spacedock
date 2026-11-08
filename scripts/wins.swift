// Lists windows owned by processes whose name contains ARG (default "spacedock"),
// with bounds and on-screen state. Build: swiftc -O scripts/wins.swift -o /tmp/wins

import CoreGraphics
import Foundation
let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as! [[String: Any]]
for w in list where (w[kCGWindowOwnerName as String] as? String)?.lowercased().contains(CommandLine.arguments.dropFirst().first ?? "spacedock") == true {
    print(w[kCGWindowNumber as String]!, w[kCGWindowOwnerName as String]!, w[kCGWindowName as String] ?? "-", w[kCGWindowBounds as String]!, "onscreen:", w[kCGWindowIsOnscreen as String] ?? false, "layer:", w[kCGWindowLayer as String]!)
}
