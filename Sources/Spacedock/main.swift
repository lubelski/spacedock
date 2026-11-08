import AppKit
import Foundation

// One binary, two roles.
//
// As a command line tool:
//   Spacedock add --name NAME --color #RRGGBB --folder PATH
//       registers the project and installs ~/Applications/Spacedock/NAME.app.
//   Spacedock regenerate
//       rebuilds every registered bundle from this binary.
//   Spacedock list
//   Spacedock remove SLUG
//   Spacedock generate --name NAME --color #RRGGBB --folder PATH [--out DIR]
//       one-off bundle, not registered (default DIR is ./out).
//
// As an app (no arguments): reads project.json from its own bundle. With no
// bundle (plain `swift run`) it opens a default project so the shell still runs.

func fail(_ message: String, status: Int32 = 1) -> Never {
    FileHandle.standardError.write("\(message)\n".data(using: .utf8)!)
    exit(status)
}

func usage() -> Never {
    fail("""
    usage:
      Spacedock add --name NAME [--color #RRGGBB] [--folder PATH]
      Spacedock regenerate
      Spacedock list
      Spacedock remove SLUG
      Spacedock generate --name NAME [--color #RRGGBB] [--folder PATH] [--out DIR]
      Spacedock            (run as the app in the current bundle)
    """, status: 64)
}

func parseProject(_ args: ArraySlice<String>) -> (Project, URL?) {
    var name: String?, color = "#3B82F6", folder = FileManager.default.currentDirectoryPath, out: String?
    var it = args.makeIterator()
    while let a = it.next() {
        switch a {
        case "--name": name = it.next()
        case "--color": color = it.next() ?? color
        case "--folder": folder = it.next() ?? folder
        case "--out": out = it.next()
        default: usage()
        }
    }
    guard let name, !name.isEmpty else { usage() }
    guard NSColor(hex: color) != nil else { fail("bad color \(color); use #RRGGBB", status: 64) }
    let absoluteFolder = URL(fileURLWithPath: (folder as NSString).expandingTildeInPath).standardizedFileURL.path
    let project = Project(name: name, slug: Project.slugify(name), colorHex: color, folder: absoluteFolder)
    return (project, out.map { URL(fileURLWithPath: $0) })
}

func install(_ project: Project) throws -> URL {
    try FileManager.default.createDirectory(at: Registry.installDirectory, withIntermediateDirectories: true)
    return try Generator.generate(project: project, outputDirectory: Registry.installDirectory)
}

let args = CommandLine.arguments.dropFirst()

do {
    switch args.first {
    case "generate":
        let (project, out) = parseProject(args.dropFirst())
        let dir = out ?? URL(fileURLWithPath: "out")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        print(try Generator.generate(project: project, outputDirectory: dir).path)
        exit(0)

    case "add":
        let (project, _) = parseProject(args.dropFirst())
        var registry = try Registry.load()
        registry.upsert(project)
        try registry.save()
        try Settings().writeIfMissing()
        print(try install(project).path)
        exit(0)

    case "regenerate":
        let registry = try Registry.load()
        if registry.projects.isEmpty { fail("no projects registered; use `Spacedock add`") }
        for p in registry.projects { print(try install(p).path) }
        exit(0)

    case "list":
        let registry = try Registry.load()
        for p in registry.projects {
            print("\(p.slug)\t\(p.colorHex)\t\(p.folder)\t\(p.name)")
        }
        exit(0)

    case "remove":
        guard let slug = args.dropFirst().first else { usage() }
        var registry = try Registry.load()
        guard let p = registry.remove(slug: slug) else { fail("no project with slug \(slug)") }
        try registry.save()
        let app = Registry.installDirectory.appendingPathComponent("\(p.name).app")
        if FileManager.default.fileExists(atPath: app.path) { try FileManager.default.removeItem(at: app) }
        print("removed \(p.name)")
        exit(0)

    case .some(let other) where !other.hasPrefix("-"):
        usage()

    default:
        break
    }
} catch {
    fail("\(args.first ?? "spacedock") failed: \(error)")
}

let project = Project.fromMainBundle()
    ?? Project(name: "Shell", slug: "shell", colorHex: "#6B7280", folder: NSHomeDirectory())

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate(project: project, settings: Settings.load())
    app.delegate = delegate
    app.run()
}
