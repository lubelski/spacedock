import Foundation

/// The list of registered projects and where their bundles live.
///
/// `~/Library/Application Support/Spacedock/projects.json` is authoritative.
/// The bundles in `~/Applications/Spacedock/` are derived from it and can be
/// rebuilt at any time with `Spacedock regenerate`.
struct Registry: Codable {
    var projects: [Project] = []

    static let supportDirectory = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library/Application Support/Spacedock")
    static let fileURL = supportDirectory.appendingPathComponent("projects.json")
    static let installDirectory = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Applications/Spacedock")

    static func load() throws -> Registry {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return Registry() }
        return try JSONDecoder().decode(Registry.self, from: Data(contentsOf: fileURL))
    }

    func save() throws {
        try FileManager.default.createDirectory(at: Registry.supportDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: Registry.fileURL)
    }

    func project(slug: String) -> Project? {
        projects.first { $0.slug == slug }
    }

    /// Adds or replaces the project with the same slug.
    mutating func upsert(_ project: Project) {
        projects.removeAll { $0.slug == project.slug }
        projects.append(project)
        projects.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    @discardableResult
    mutating func remove(slug: String) -> Project? {
        guard let p = project(slug: slug) else { return nil }
        projects.removeAll { $0.slug == slug }
        return p
    }
}
