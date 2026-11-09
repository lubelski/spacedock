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
    /// Up to three characters drawn on the icon. Nil uses `Project.initials(name)`.
    var avatar: String? = nil
    /// An image for the icon, a copy under `images/` in the support directory.
    /// Wins over the letters. A missing file falls back to the letters.
    var image: String? = nil
    /// How the image sits in the icon. Nil means `.framed`.
    var imageStyle: IconImageStyle? = nil

    static let bundleIDPrefix = "dev.lubelski.spacedock"

    var bundleIdentifier: String { "\(Profile.current.bundlePrefix).\(slug)" }

    /// Name as shown in the Dock: the project name plus the profile suffix.
    var displayName: String { name + Profile.current.nameSuffix }

    var color: NSColor { NSColor(hex: colorHex) ?? .systemBlue }

    /// The letters on the icon: the manual avatar, or initials of the name.
    var avatarText: String {
        if let a = avatar?.trimmingCharacters(in: .whitespaces), !a.isEmpty { return a }
        return Project.initials(name)
    }

    /// What the icon shows: the image when it loads, the letters otherwise.
    var iconContent: IconContent {
        if let image, let picture = NSImage(contentsOfFile: image) {
            return .image(picture, imageStyle ?? .framed)
        }
        return .text(avatarText)
    }

    static let avatarLimit = 3

    /// Up to three letters for the icon. Each word of a multi-word name
    /// gives its first letter: "machine-configuration-notes" is MCN,
    /// "SpaceDock" is SD. A one-word name of three characters or fewer is
    /// used whole ("Tau" is TAU). A longer single word gives its first
    /// letter. Words split on anything that is not a letter or digit, on a
    /// lowercase-to-uppercase step, and between letters and digits.
    static func initials(_ name: String) -> String {
        var words: [String] = []
        for chunk in name.split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
            var word = ""
            var prev: Character?
            for ch in chunk {
                if let p = prev, (p.isLowercase && ch.isUppercase) || (p.isLetter != ch.isLetter) {
                    words.append(word); word = ""
                }
                word.append(ch); prev = ch
            }
            if !word.isEmpty { words.append(word) }
        }
        guard let first = words.first else { return "?" }
        if words.count == 1 {
            return first.count <= avatarLimit ? first.uppercased() : String(first.prefix(1)).uppercased()
        }
        return words.prefix(avatarLimit).map { String($0.prefix(1)) }.joined().uppercased()
    }

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

/// How a custom image sits in the project icon.
enum IconImageStyle: String, Codable, CaseIterable {
    /// The image on a light rounded plate inside the project-color squircle,
    /// so the color frames it whatever the image looks like.
    case framed
    /// The image fills the squircle, with a ring of the project color at the edge.
    case fill
}

/// What a project icon draws inside the squircle.
enum IconContent {
    case text(String)
    case image(NSImage, IconImageStyle)
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
