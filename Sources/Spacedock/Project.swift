import AppKit
import Foundation

/// The definition of one project. Stored as `project.json` in the generated
/// bundle's Resources, so the running app can read it from `Bundle.main`.
struct Project: Codable {
    var name: String
    var slug: String
    var colorHex: String
    var folder: String
    /// Per-project overrides of the global `Settings`. Nil fields inherit.
    var settings: SettingsOverride? = nil
    /// Raw Ghostty config keys for this project, merged over the global map.
    var ghostty: [String: String]? = nil

    static let bundleIDPrefix = "dev.lubelski.spacedock"

    var bundleIdentifier: String { "\(Profile.current.bundlePrefix).\(slug)" }

    /// Name as shown in the Dock: the project name plus the profile suffix.
    var displayName: String { name + Profile.current.nameSuffix }

    var color: NSColor { NSColor(hex: colorHex) ?? .systemBlue }

    var folderURL: URL { URL(fileURLWithPath: (folder as NSString).expandingTildeInPath) }

    /// Why the project cannot launch. Empty when it can. A project with
    /// problems stays registered; only launching is blocked.
    var problems: [String] {
        var out: [String] = []
        if name.trimmingCharacters(in: .whitespaces).isEmpty { out.append("Name is empty") }
        if NSColor(hex: colorHex) == nil { out.append("Color is not #RRGGBB") }
        if folder.isEmpty {
            out.append("No folder chosen")
        } else {
            var isDir: ObjCBool = false
            if !FileManager.default.fileExists(atPath: folderURL.path, isDirectory: &isDir) || !isDir.boolValue {
                out.append("Folder not found")
            }
        }
        return out
    }

    var isLaunchable: Bool { problems.isEmpty }

    /// Colors handed to new projects, first unused one wins.
    static let palette = ["#3B82F6", "#0F766E", "#D97706", "#7C3AED", "#DC2626", "#DB2777", "#65A30D", "#0891B2"]

    /// Reads `project.json` from the running bundle. Returns nil when the
    /// binary runs outside a generated bundle (e.g. `swift run`).
    static func fromMainBundle() -> Project? {
        guard let url = Bundle.main.url(forResource: "project", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Project.self, from: data)
    }

    static func slugify(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics
        let scalars = name.lowercased().unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let collapsed = String(scalars).split(separator: "-", omittingEmptySubsequences: true).joined(separator: "-")
        return collapsed.isEmpty ? "project" : collapsed
    }
}

extension NSColor {
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
                  green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255,
                  alpha: 1)
    }

    /// Perceived luminance in sRGB, 0 (black) to 1 (white).
    var luminance: CGFloat {
        guard let c = usingColorSpace(.sRGB) else { return 0.5 }
        return 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent
    }
}
