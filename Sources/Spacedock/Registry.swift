import AppKit
import Foundation

/// The list of registered projects and where their bundles live.
///
/// `~/Library/Application Support/Spacedock/projects.json` is authoritative.
/// The bundles in `~/Applications/Spacedock/` are derived from it and can be
/// rebuilt at any time with `Spacedock regenerate`.
struct Registry: Codable {
    var projects: [Project] = []

    // All paths follow `Profile.current`.
    static var supportDirectory: URL { Profile.current.supportDirectory }
    static var fileURL: URL { supportDirectory.appendingPathComponent("projects.json") }
    static var installDirectory: URL { Profile.current.installDirectory }
    /// The prime app lives beside the project folder, not inside it, so a
    /// registered project named Spacedock does not collide with it.
    static var primeDirectory: URL { Profile.current.primeDirectory }
    static var primeAppURL: URL { primeDirectory.appendingPathComponent("Spacedock\(Profile.current.nameSuffix).app") }

    /// Copies of project images. The registry points here, so moving or
    /// deleting the original does not change the icon.
    static var imagesDirectory: URL { supportDirectory.appendingPathComponent("images") }

    /// Copies an image file into `imagesDirectory` and returns the copy's path.
    static func importImage(_ path: String) throws -> String {
        let source = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        guard NSImage(contentsOf: source) != nil else { throw "\(path) is not an image macOS can read" }
        try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        let ext = source.pathExtension.isEmpty ? "png" : source.pathExtension.lowercased()
        let copy = imagesDirectory.appendingPathComponent("\(UUID().uuidString).\(ext)")
        try FileManager.default.copyItem(at: source, to: copy)
        return copy.path
    }

    /// Deletes an image copy once no project uses it. Leaves files outside
    /// `imagesDirectory` alone.
    func discardImage(_ path: String?) {
        guard let path, path.hasPrefix(Registry.imagesDirectory.path + "/"),
              !projects.contains(where: { $0.image == path }) else { return }
        try? FileManager.default.removeItem(atPath: path)
    }

    static func appURL(for project: Project) -> URL {
        installDirectory.appendingPathComponent("\(project.displayName).app")
    }

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

    /// `base`, or `base-2`, `base-3`, ... if another project has it.
    func uniqueSlug(_ base: String, excluding: String? = nil) -> String {
        var slug = base, n = 2
        while projects.contains(where: { $0.slug == slug && $0.slug != excluding }) {
            slug = "\(base)-\(n)"; n += 1
        }
        return slug
    }

    /// Registers a placeholder project, "New Project" with an unused color
    /// and no folder, and saves. It cannot launch until a folder is chosen.
    mutating func addNew() throws -> Project {
        var name = "New Project", n = 2
        while projects.contains(where: { $0.name == name }) { name = "New Project \(n)"; n += 1 }
        let used = Set(projects.map { $0.colorHex.uppercased() })
        let color = Project.palette.first { !used.contains($0) } ?? Project.palette[projects.count % Project.palette.count]
        let p = Project(name: name, slug: uniqueSlug(Project.slugify(name)), colorHex: color, folder: "")
        upsert(p)
        try save()
        return p
    }

    /// Applies `change` to the project with `slug`, saves, and keeps its
    /// bundle in step. The slug follows the name until the project's bundle
    /// is first installed; after that it stays fixed, because the bundle id
    /// (and any Space assignment) derives from it. A renamed bundle is moved
    /// by deleting the old one. A launchable project's bundle is rewritten;
    /// one with problems keeps whatever bundle it had.
    @discardableResult
    mutating func edit(slug: String, _ change: (inout Project) -> Void) throws -> Project {
        guard let old = project(slug: slug) else { throw "no project with slug \(slug)" }
        var p = old
        change(&p)
        p.name = p.name.trimmingCharacters(in: .whitespaces)
        if let a = p.avatar?.trimmingCharacters(in: .whitespaces) {
            guard a.count <= Project.avatarLimit else { throw "avatar \"\(a)\" is longer than \(Project.avatarLimit) characters" }
            p.avatar = a.isEmpty ? nil : a
        }
        if p.image?.isEmpty == true { p.image = nil }
        if !p.folder.isEmpty {
            p.folder = URL(fileURLWithPath: (p.folder as NSString).expandingTildeInPath).standardizedFileURL.path
        }
        let oldApp = Registry.appURL(for: old)
        let installed = FileManager.default.fileExists(atPath: oldApp.path)
        if p.name != old.name, !installed, !p.name.isEmpty {
            p.slug = uniqueSlug(Project.slugify(p.name), excluding: old.slug)
        }
        projects.removeAll { $0.slug == old.slug }
        upsert(p)
        try save()
        if old.image != p.image { discardImage(old.image) }
        if installed, Registry.appURL(for: p) != oldApp { try? FileManager.default.removeItem(at: oldApp) }
        if p.isLaunchable {
            try FileManager.default.createDirectory(at: Registry.installDirectory, withIntermediateDirectories: true)
            _ = try Generator.generate(project: p, outputDirectory: Registry.installDirectory)
        }
        return p
    }

    @discardableResult
    mutating func remove(slug: String) -> Project? {
        guard let p = project(slug: slug) else { return nil }
        projects.removeAll { $0.slug == slug }
        discardImage(p.image)
        return p
    }
}
