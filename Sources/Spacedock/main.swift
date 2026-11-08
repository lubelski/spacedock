import AppKit
import Foundation

// Two modes, one binary:
//   Spacedock generate --name NAME --color #RRGGBB --folder PATH [--out DIR]
//       writes NAME.app into DIR (default ./out) and prints its path.
//   Spacedock
//       runs as an app. Reads project.json from its own bundle; when there is
//       none (plain `swift run`), uses a default project so the app still opens.

func usage() -> Never {
    FileHandle.standardError.write("""
    usage:
      Spacedock generate --name NAME --color #RRGGBB --folder PATH [--out DIR]
      Spacedock            (run as the app in the current bundle)

    """.data(using: .utf8)!)
    exit(64)
}

func parseGenerate(_ args: ArraySlice<String>) -> (Project, URL) {
    var name: String?, color = "#3B82F6", folder = NSHomeDirectory(), out = "out"
    var it = args.makeIterator()
    while let a = it.next() {
        switch a {
        case "--name": name = it.next()
        case "--color": color = it.next() ?? color
        case "--folder": folder = it.next() ?? folder
        case "--out": out = it.next() ?? out
        default: usage()
        }
    }
    guard let name, !name.isEmpty else { usage() }
    guard NSColor(hex: color) != nil else {
        FileHandle.standardError.write("bad color \(color); use #RRGGBB\n".data(using: .utf8)!)
        exit(64)
    }
    let project = Project(name: name, slug: Project.slugify(name), colorHex: color, folder: folder)
    return (project, URL(fileURLWithPath: out))
}

let args = CommandLine.arguments.dropFirst()

if args.first == "generate" {
    let (project, out) = parseGenerate(args.dropFirst())
    do {
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let app = try Generator.generate(project: project, outputDirectory: out)
        print(app.path)
        exit(0)
    } catch {
        FileHandle.standardError.write("generate failed: \(error)\n".data(using: .utf8)!)
        exit(1)
    }
}

let project = Project.fromMainBundle()
    ?? Project(name: "Shell", slug: "shell", colorHex: "#6B7280", folder: NSHomeDirectory())

let app = NSApplication.shared
let delegate = AppDelegate(project: project)
app.delegate = delegate
app.run()
