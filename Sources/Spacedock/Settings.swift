import AppKit
import Foundation
import SwiftTerm

/// Window-layer settings shared by every generated app. Read from
/// `~/Library/Application Support/Spacedock/settings.json` at launch. A
/// missing file or a missing key falls back to the default here.
struct Settings: Codable {
    var fontName: String? = nil
    var fontSize: CGFloat = 13
    var padding: CGFloat = 8
    /// One of: blinkBlock, steadyBlock, blinkUnderline, steadyUnderline, blinkBar, steadyBar.
    var cursorStyle: String = "blinkBar"
    var scrollback: Int = 10_000

    static let fileURL = Registry.supportDirectory.appendingPathComponent("settings.json")

    static func load() -> Settings {
        guard let data = try? Data(contentsOf: fileURL) else { return Settings() }
        do {
            return try JSONDecoder().decode(Settings.self, from: data)
        } catch {
            NSLog("Spacedock: settings.json unreadable, using defaults: \(error)")
            return Settings()
        }
    }

    /// Writes the current defaults so the user has a file to edit.
    func writeIfMissing() throws {
        guard !FileManager.default.fileExists(atPath: Settings.fileURL.path) else { return }
        try FileManager.default.createDirectory(at: Registry.supportDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: Settings.fileURL)
    }

    var font: NSFont {
        if let fontName, let f = NSFont(name: fontName, size: fontSize) { return f }
        return NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }

    var terminalCursorStyle: CursorStyle {
        CursorStyle(tagName: cursorStyle) ?? .blinkBar
    }

    var terminalOptions: TerminalOptions {
        var o = TerminalOptions.default
        o.cursorStyle = terminalCursorStyle
        o.scrollback = scrollback
        return o
    }
}
