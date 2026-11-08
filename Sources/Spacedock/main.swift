import AppKit
import Foundation

// One binary, two roles.
//
// As a command line tool:
//   Spacedock add --name NAME --color #RRGGBB --folder PATH
//       registers the project and installs ~/Applications/Spacedock/NAME.app.
//   Spacedock install
//       installs the prime app, ~/Applications/Spacedock.app: a menu bar
//       control panel for the project apps. `open` it again, or launch it
//       with `--args --panel`, to show the panel.
//   Spacedock regenerate
//       rebuilds the prime app and every registered bundle from this binary.
//   Spacedock restart [SLUG ...]
//       quits the named running project apps (all running ones by default),
//       regenerates every bundle, and relaunches the ones that were running.
//       The prime app is restarted too when it is running.
//   Spacedock list
//       one line per project: slug, color, running or stopped, folder, name.
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
      Spacedock install
      Spacedock regenerate
      Spacedock restart [SLUG ...]
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

func running(_ bundleID: String) -> NSRunningApplication? {
    NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
}

/// Sends the quit Apple event and waits up to `timeout` seconds for exit.
/// Returns false if the app is still running afterwards.
func quitAndWait(_ app: NSRunningApplication, timeout: TimeInterval = 3) -> Bool {
    app.terminate()
    let deadline = Date().addingTimeInterval(timeout)
    while !app.isTerminated && Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
    return app.isTerminated
}

func installPrime() throws -> URL {
    try FileManager.default.createDirectory(at: Registry.primeDirectory, withIntermediateDirectories: true)
    return try Generator.generatePrime(outputDirectory: Registry.primeDirectory)
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
        if !FileManager.default.fileExists(atPath: Registry.primeAppURL.path) { _ = try installPrime() }
        print(try install(project).path)
        exit(0)

    case "install":
        try Settings().writeIfMissing()
        print(try installPrime().path)
        exit(0)

    case "regenerate":
        let registry = try Registry.load()
        print(try installPrime().path)
        for p in registry.projects { print(try install(p).path) }
        exit(0)

    case "restart":
        let registry = try Registry.load()
        let slugs = Array(args.dropFirst())
        let targets = slugs.isEmpty ? registry.projects : try slugs.map { slug in
            guard let p = registry.project(slug: slug) else { fail("no project with slug \(slug)") }
            return p
        }
        var toRelaunch: [URL] = []
        for p in targets {
            guard let app = running(p.bundleIdentifier) else { continue }
            if !quitAndWait(app) { app.forceTerminate(); _ = quitAndWait(app, timeout: 1) }
            toRelaunch.append(Registry.appURL(for: p))
            print("quit \(p.name)")
        }
        let primeWasRunning = running(Project.bundleIDPrefix)
        if let prime = primeWasRunning {
            if !quitAndWait(prime) { prime.forceTerminate(); _ = quitAndWait(prime, timeout: 1) }
            print("quit Spacedock")
        }
        _ = try installPrime()
        for p in registry.projects { _ = try install(p) }
        print("regenerated \(registry.projects.count + 1) bundles")
        if primeWasRunning != nil { toRelaunch.insert(Registry.primeAppURL, at: 0) }
        for url in toRelaunch {
            try Generator.run("/usr/bin/open", [url.path])
            print("launched \(url.deletingPathExtension().lastPathComponent)")
        }
        exit(0)

    case "list":
        let registry = try Registry.load()
        for p in registry.projects {
            let state = running(p.bundleIdentifier) == nil ? "stopped" : "running"
            print("\(p.slug)\t\(p.colorHex)\t\(state)\t\(p.folder)\t\(p.name)")
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

let isPrime = (Bundle.main.object(forInfoDictionaryKey: Generator.primeRoleKey) as? String) == Generator.primeRoleValue

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate: NSApplicationDelegate
    if isPrime {
        delegate = PrimeDelegate()
    } else {
        let project = Project.fromMainBundle()
            ?? Project(name: "Shell", slug: "shell", colorHex: "#6B7280", folder: NSHomeDirectory())
        delegate = AppDelegate(project: project, settings: Settings.load())
    }
    app.delegate = delegate
    app.run()
}
