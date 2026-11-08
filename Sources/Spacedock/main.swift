import AppKit
import Foundation

// One binary, two roles.
//
// As a command line tool:
//   Spacedock add --name NAME --color #RRGGBB --folder PATH [--set KEY=VALUE ...] [--ghostty KEY=VALUE ...]
//       registers the project and installs ~/Applications/Spacedock/NAME.app.
//   Spacedock set SLUG KEY=VALUE ...
//   Spacedock set --global KEY=VALUE ...
//       per-project or global settings. KEY is fontName, fontSize, padding,
//       cursorStyle, scrollback, emulator, or ghostty.<ghostty-config-key>.
//       An empty VALUE removes a per-project override. Takes effect at the
//       project's next launch; no regenerate needed.
//   Spacedock show SLUG
//       the project's effective settings.
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
//   Spacedock quit [SLUG ...]
//       quits the named running project apps, or every running one plus the
//       prime app when no names are given. Agents use it to clean up a profile.
//   Spacedock list
//       one line per project: slug, color, running or stopped, folder, name.
//   Spacedock remove SLUG
//   Spacedock generate --name NAME --color #RRGGBB --folder PATH [--out DIR]
//       one-off bundle, not registered (default DIR is ./out).
//
// Every CLI command takes --profile NAME (or SPACEDOCK_PROFILE). The default
// profile is the installed copy. Any other profile has its own bundle ids,
// registry, settings, and bundles under
// ~/Library/Application Support/Spacedock/profiles/NAME/, and its apps launch
// in the background (no focus change). Use it for development copies.
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
      Spacedock add --name NAME [--color #RRGGBB] [--folder PATH] [--set KEY=VALUE ...] [--ghostty KEY=VALUE ...]
      Spacedock set SLUG KEY=VALUE ...
      Spacedock set --global KEY=VALUE ...
      Spacedock show SLUG
      Spacedock install
      Spacedock regenerate
      Spacedock restart [SLUG ...]
      Spacedock quit [SLUG ...]
      Spacedock list
      Spacedock remove SLUG
      Spacedock generate --name NAME [--color #RRGGBB] [--folder PATH] [--out DIR]
      Spacedock            (run as the app in the current bundle)
    """, status: 64)
}

/// Applies `KEY=VALUE` to a project's overrides. `ghostty.KEY` goes to the raw map.
func apply(_ assignment: String, to project: inout Project) {
    guard let eq = assignment.firstIndex(of: "=") else { fail("expected KEY=VALUE, got \(assignment)", status: 64) }
    let key = String(assignment[..<eq]), value = String(assignment[assignment.index(after: eq)...])
    if key.hasPrefix("ghostty.") {
        let gkey = String(key.dropFirst("ghostty.".count))
        var map = project.ghostty ?? [:]
        if value.isEmpty { map.removeValue(forKey: gkey) } else { map[gkey] = value }
        project.ghostty = map.isEmpty ? nil : map
    } else {
        var o = project.settings ?? SettingsOverride()
        if let err = o.set(key, value) { fail(err, status: 64) }
        project.settings = o.isEmpty ? nil : o
    }
}

func parseProject(_ args: ArraySlice<String>) -> (Project, URL?) {
    var name: String?, color = "#3B82F6", folder = FileManager.default.currentDirectoryPath, out: String?
    var assignments: [String] = []
    var it = args.makeIterator()
    while let a = it.next() {
        switch a {
        case "--name": name = it.next()
        case "--color": color = it.next() ?? color
        case "--folder": folder = it.next() ?? folder
        case "--out": out = it.next()
        case "--set": if let v = it.next() { assignments.append(v) } else { usage() }
        case "--ghostty": if let v = it.next() { assignments.append("ghostty." + v) } else { usage() }
        default: usage()
        }
    }
    guard let name, !name.isEmpty else { usage() }
    guard NSColor(hex: color) != nil else { fail("bad color \(color); use #RRGGBB", status: 64) }
    let absoluteFolder = URL(fileURLWithPath: (folder as NSString).expandingTildeInPath).standardizedFileURL.path
    var project = Project(name: name, slug: Project.slugify(name), colorHex: color, folder: absoluteFolder)
    for a in assignments { apply(a, to: &project) }
    return (project, out.map { URL(fileURLWithPath: $0) })
}

func describe(_ s: Settings) -> String {
    var lines = [
        "emulator\t\(s.emulator)",
        "fontName\t\(s.fontName ?? "(system monospaced)")",
        "fontSize\t\(s.fontSize)",
        "padding\t\(s.padding)",
        "cursorStyle\t\(s.cursorStyle)",
        "scrollback\t\(s.scrollback)",
    ]
    for (k, v) in s.ghostty.sorted(by: { $0.key < $1.key }) { lines.append("ghostty.\(k)\t\(v)") }
    return lines.joined(separator: "\n")
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

var argv = Array(CommandLine.arguments.dropFirst())
if let i = argv.firstIndex(of: "--profile") {
    guard i + 1 < argv.count else { usage() }
    Profile.current = Profile.named(argv[i + 1])
    argv.removeSubrange(i...i + 1)
} else if let env = ProcessInfo.processInfo.environment["SPACEDOCK_PROFILE"], !env.isEmpty {
    Profile.current = Profile.named(env)
}
// A running app's profile comes from its bundle, never from the environment.
if CommandLine.arguments.count <= 1 || argv.first?.hasPrefix("-") == true {
    Profile.current = Profile.fromMainBundle()
}
let args = argv[...]

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
        // Named projects relaunch even if stopped; with no names, only the running ones do.
        var toRelaunch: [URL] = []
        for p in targets {
            if let app = running(p.bundleIdentifier) {
                if !quitAndWait(app) { app.forceTerminate(); _ = quitAndWait(app, timeout: 1) }
                print("quit \(p.displayName)")
                toRelaunch.append(Registry.appURL(for: p))
            } else if !slugs.isEmpty {
                toRelaunch.append(Registry.appURL(for: p))
            }
        }
        let primeWasRunning = running(Profile.current.bundlePrefix)
        if let prime = primeWasRunning {
            if !quitAndWait(prime) { prime.forceTerminate(); _ = quitAndWait(prime, timeout: 1) }
            print("quit Spacedock\(Profile.current.nameSuffix)")
        }
        _ = try installPrime()
        for p in registry.projects { _ = try install(p) }
        print("regenerated \(registry.projects.count + 1) bundles")
        if primeWasRunning != nil { toRelaunch.insert(Registry.primeAppURL, at: 0) }
        for url in toRelaunch {
            try Generator.run("/usr/bin/open", Profile.current.launchesInBackground ? ["-g", url.path] : [url.path])
            print("launched \(url.deletingPathExtension().lastPathComponent)")
        }
        exit(0)

    case "set":
        var rest = Array(args.dropFirst())
        guard let target = rest.first else { usage() }
        rest.removeFirst()
        if rest.isEmpty { usage() }
        if target == "--global" {
            var settings = Settings.load()
            for a in rest {
                guard let eq = a.firstIndex(of: "=") else { fail("expected KEY=VALUE, got \(a)", status: 64) }
                let key = String(a[..<eq]), value = String(a[a.index(after: eq)...])
                if key.hasPrefix("ghostty.") {
                    let gkey = String(key.dropFirst("ghostty.".count))
                    if value.isEmpty { settings.ghostty.removeValue(forKey: gkey) } else { settings.ghostty[gkey] = value }
                } else if let err = settings.set(key, value) {
                    fail(err, status: 64)
                }
            }
            try settings.save()
            print(describe(settings))
        } else {
            var registry = try Registry.load()
            guard var p = registry.project(slug: target) else { fail("no project with slug \(target)") }
            for a in rest { apply(a, to: &p) }
            registry.upsert(p)
            try registry.save()
            print(describe(Settings.load().applying(p.settings, ghostty: p.ghostty)))
        }
        exit(0)

    case "show":
        guard let slug = args.dropFirst().first else { usage() }
        let registry = try Registry.load()
        guard let p = registry.project(slug: slug) else { fail("no project with slug \(slug)") }
        print("\(p.name)\t\(p.colorHex)\t\(p.folder)")
        print(describe(Settings.load().applying(p.settings, ghostty: p.ghostty)))
        exit(0)

    case "quit":
        let registry = try Registry.load()
        let slugs = Array(args.dropFirst())
        let targets = slugs.isEmpty ? registry.projects : try slugs.map { slug in
            guard let p = registry.project(slug: slug) else { fail("no project with slug \(slug)") }
            return p
        }
        for p in targets {
            guard let app = running(p.bundleIdentifier) else { continue }
            if !quitAndWait(app) { app.forceTerminate(); _ = quitAndWait(app, timeout: 1) }
            print("quit \(p.displayName)")
        }
        if slugs.isEmpty, let prime = running(Profile.current.bundlePrefix) {
            if !quitAndWait(prime) { prime.forceTerminate(); _ = quitAndWait(prime, timeout: 1) }
            print("quit Spacedock\(Profile.current.nameSuffix)")
        }
        exit(0)

    case "list":
        let registry = try Registry.load()
        for p in registry.projects {
            let state = running(p.bundleIdentifier) == nil ? "stopped" : "running"
            print("\(p.slug)\t\(p.colorHex)\t\(state)\t\(p.folder)\t\(p.displayName)")
        }
        exit(0)

    case "remove":
        guard let slug = args.dropFirst().first else { usage() }
        var registry = try Registry.load()
        guard let p = registry.remove(slug: slug) else { fail("no project with slug \(slug)") }
        try registry.save()
        let app = Registry.appURL(for: p)
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
        let bundled = Project.fromMainBundle()
            ?? Project(name: "Shell", slug: "shell", colorHex: "#6B7280", folder: NSHomeDirectory())
        // The registry has the latest overrides; the bundle's copy is the identity.
        let project = (try? Registry.load())?.project(slug: bundled.slug) ?? bundled
        delegate = AppDelegate(project: project, settings: Settings.load().applying(project.settings, ghostty: project.ghostty))
    }
    app.delegate = delegate
    app.run()
}
