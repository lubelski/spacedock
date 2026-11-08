import AppKit
import Foundation
import SwiftTerm

/// Window-layer settings shared by every generated app. Read from
/// `~/Library/Application Support/Spacedock/settings.json` at launch. A
/// missing file or a missing key falls back to the default here. A project
/// can override any field through `Project.settings`, and add raw Ghostty
/// config keys through `Project.ghostty`.
struct Settings: Codable {
    var fontName: String? = nil
    var fontSize: CGFloat = 13
    var padding: CGFloat = 8
    /// One of: blinkBlock, steadyBlock, blinkUnderline, steadyUnderline, blinkBar, steadyBar.
    var cursorStyle: String = "blinkBar"
    var scrollback: Int = 10_000
    /// "ghostty" (default) or "swiftterm" (compatibility).
    var emulator: String = "ghostty"
    /// Raw Ghostty config keys, applied after the fields above. Only the
    /// ghostty emulator reads them. See https://ghostty.org/docs/config/reference
    var ghostty: [String: String] = [:]

    static var fileURL: URL { Registry.supportDirectory.appendingPathComponent("settings.json") }

    init() {}

    /// Missing keys keep their defaults, so an older settings.json still loads.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fontName = try c.decodeIfPresent(String.self, forKey: .fontName)
        fontSize = try c.decodeIfPresent(CGFloat.self, forKey: .fontSize) ?? fontSize
        padding = try c.decodeIfPresent(CGFloat.self, forKey: .padding) ?? padding
        cursorStyle = try c.decodeIfPresent(String.self, forKey: .cursorStyle) ?? cursorStyle
        scrollback = try c.decodeIfPresent(Int.self, forKey: .scrollback) ?? scrollback
        emulator = try c.decodeIfPresent(String.self, forKey: .emulator) ?? emulator
        ghostty = try c.decodeIfPresent([String: String].self, forKey: .ghostty) ?? ghostty
    }

    /// The keys `set` accepts, in the order the panel shows them.
    static let overridableKeys = ["fontName", "fontSize", "padding", "cursorStyle", "scrollback", "emulator"]

    static func load() -> Settings {
        guard let data = try? Data(contentsOf: fileURL) else { return Settings() }
        do {
            return try JSONDecoder().decode(Settings.self, from: data)
        } catch {
            NSLog("Spacedock: settings.json unreadable, using defaults: \(error)")
            return Settings()
        }
    }

    func save() throws {
        try FileManager.default.createDirectory(at: Registry.supportDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: Settings.fileURL)
    }

    /// Writes the current defaults so the user has a file to edit.
    func writeIfMissing() throws {
        guard !FileManager.default.fileExists(atPath: Settings.fileURL.path) else { return }
        try save()
    }

    /// Global settings with one project's overrides applied.
    func applying(_ o: SettingsOverride?, ghostty projectGhostty: [String: String]?) -> Settings {
        var s = self
        if let o {
            if let v = o.fontName { s.fontName = v.isEmpty ? nil : v }
            if let v = o.fontSize { s.fontSize = v }
            if let v = o.padding { s.padding = v }
            if let v = o.cursorStyle { s.cursorStyle = v }
            if let v = o.scrollback { s.scrollback = v }
            if let v = o.emulator { s.emulator = v }
        }
        if let projectGhostty { s.ghostty.merge(projectGhostty) { _, p in p } }
        return s
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

/// A partial `Settings`: every field optional, nil means inherit the global value.
struct SettingsOverride: Codable, Equatable {
    var fontName: String? = nil
    var fontSize: CGFloat? = nil
    var padding: CGFloat? = nil
    var cursorStyle: String? = nil
    var scrollback: Int? = nil
    var emulator: String? = nil

    var isEmpty: Bool { self == SettingsOverride() }

    /// Sets one field from a string. An empty value clears the override.
    /// Returns an error message for an unknown key or a bad value.
    mutating func set(_ key: String, _ raw: String) -> String? {
        let value: String? = raw.isEmpty ? nil : raw
        switch key {
        case "fontName": fontName = value
        case "fontSize":
            if let value { guard let d = Double(value) else { return "fontSize needs a number" }; fontSize = CGFloat(d) } else { fontSize = nil }
        case "padding":
            if let value { guard let d = Double(value) else { return "padding needs a number" }; padding = CGFloat(d) } else { padding = nil }
        case "cursorStyle":
            if let value { guard CursorStyle(tagName: value) != nil else { return "cursorStyle must be one of \(CursorStyle.allCases.map(\.tagName).joined(separator: ", "))" } }
            cursorStyle = value
        case "scrollback":
            if let value { guard let i = Int(value) else { return "scrollback needs an integer" }; scrollback = i } else { scrollback = nil }
        case "emulator":
            if let value { guard ["ghostty", "swiftterm"].contains(value.lowercased()) else { return "emulator must be ghostty or swiftterm" } }
            emulator = value?.lowercased()
        default: return "unknown key \(key); keys: \(Settings.overridableKeys.joined(separator: ", ")), ghostty.<key>"
        }
        return nil
    }
}

extension Settings {
    /// Same keys as `SettingsOverride.set`, applied to the global file.
    mutating func set(_ key: String, _ raw: String) -> String? {
        var o = SettingsOverride()
        if let err = o.set(key, raw) { return err }
        if raw.isEmpty { return "global \(key) cannot be cleared; give a value" }
        self = applying(o, ghostty: nil)
        return nil
    }
}
