import Foundation

/// Which Spacedock this is. The default profile is the user's installed copy.
/// Any other profile (an agent's development copy, say) gets its own bundle
/// ids, registry, settings, and install folder, so it cannot touch the
/// installed one. A running app reads its profile from Info.plist; the CLI
/// takes `--profile NAME` or `SPACEDOCK_PROFILE`.
struct Profile: Equatable {
    static let defaultName = "default"
    static let plistKey = "SpacedockProfile"

    let name: String

    nonisolated(unsafe) static var current = Profile(name: Profile.defaultName)

    var isDefault: Bool { name == Profile.defaultName }

    /// `dev.lubelski.spacedock` for the default, `dev.lubelski.spacedock.<profile>` otherwise.
    var bundlePrefix: String {
        isDefault ? Project.bundleIDPrefix : "\(Project.bundleIDPrefix).\(name)"
    }

    /// Appended to app names so the Dock and Cmd-Tab tell copies apart.
    var nameSuffix: String { isDefault ? "" : " (\(name))" }

    /// Registry and settings live here.
    var supportDirectory: URL {
        let base = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support/Spacedock")
        return isDefault ? base : base.appendingPathComponent("profiles/\(name)")
    }

    /// Project bundles. The default profile uses `~/Applications/Spacedock/`;
    /// other profiles stay under Application Support so Spotlight and
    /// Launchpad do not list them.
    var installDirectory: URL {
        isDefault
            ? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Applications/Spacedock")
            : supportDirectory.appendingPathComponent("Applications")
    }

    /// The prime app's folder: `~/Applications` for the default, next to the
    /// project bundles otherwise.
    var primeDirectory: URL {
        isDefault ? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Applications") : installDirectory
    }

    /// Non-default profiles launch without taking focus.
    var launchesInBackground: Bool { !isDefault }

    /// Sanitized like a slug, so it is safe in bundle ids and paths.
    static func named(_ raw: String) -> Profile {
        let slug = Project.slugify(raw)
        return Profile(name: slug == "project" ? defaultName : slug)
    }

    /// The running app's profile, from its Info.plist. Absent means default.
    static func fromMainBundle() -> Profile {
        if let name = Bundle.main.object(forInfoDictionaryKey: plistKey) as? String, !name.isEmpty {
            return Profile(name: name)
        }
        return Profile(name: defaultName)
    }
}
