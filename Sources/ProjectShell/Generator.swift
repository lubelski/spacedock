import AppKit
import Foundation

/// Writes a standalone `.app` bundle for one project. The bundle's executable
/// is a copy of the currently running binary, so every generated app is the
/// same program reading a different `project.json`.
enum Generator {
    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    static func generate(project: Project, outputDirectory: URL) throws -> URL {
        let fm = FileManager.default
        let appURL = outputDirectory.appendingPathComponent("\(project.name).app")
        let contents = appURL.appendingPathComponent("Contents")
        let macOS = contents.appendingPathComponent("MacOS")
        let resources = contents.appendingPathComponent("Resources")

        if fm.fileExists(atPath: appURL.path) {
            try fm.removeItem(at: appURL)
        }
        try fm.createDirectory(at: macOS, withIntermediateDirectories: true)
        try fm.createDirectory(at: resources, withIntermediateDirectories: true)

        // Executable: copy of this binary.
        guard let selfURL = Bundle.main.executableURL else {
            throw Failure(description: "cannot locate own executable")
        }
        let exeName = project.slug
        let exeURL = macOS.appendingPathComponent(exeName)
        try fm.copyItem(at: selfURL.resolvingSymlinksInPath(), to: exeURL)

        // Project definition.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(project).write(to: resources.appendingPathComponent("project.json"))

        // Icon.
        try IconRenderer.writeICNS(for: project, to: resources.appendingPathComponent("AppIcon.icns"))

        // Info.plist.
        let plist: [String: Any] = [
            "CFBundleDevelopmentRegion": "en",
            "CFBundleExecutable": exeName,
            "CFBundleIconFile": "AppIcon",
            "CFBundleIdentifier": project.bundleIdentifier,
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundleName": project.name,
            "CFBundleDisplayName": project.name,
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "0.1",
            "CFBundleVersion": "1",
            "LSMinimumSystemVersion": "14.0",
            "NSHighResolutionCapable": true,
            "NSPrincipalClass": "NSApplication",
        ]
        let plistData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try plistData.write(to: contents.appendingPathComponent("Info.plist"))
        try "APPL????".write(to: contents.appendingPathComponent("PkgInfo"), atomically: true, encoding: .ascii)

        // Ad-hoc signature. Required for the binary to launch at all on
        // Apple silicon; also what the Dock keys the icon cache on.
        try run("/usr/bin/codesign", ["--force", "--sign", "-", "--deep", appURL.path])

        return appURL
    }

    @discardableResult
    static func run(_ launchPath: String, _ arguments: [String]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = arguments
        let out = Pipe()
        p.standardOutput = out
        p.standardError = out
        try p.run()
        p.waitUntilExit()
        let text = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if p.terminationStatus != 0 {
            throw Failure(description: "\(launchPath) \(arguments.joined(separator: " ")) failed (\(p.terminationStatus)): \(text)")
        }
        return text
    }
}

/// Renders a project icon: a rounded square in the project color with the
/// project's initial, written out as an `.icns` through `iconutil`.
enum IconRenderer {
    static func writeICNS(for project: Project, to url: URL) throws {
        let fm = FileManager.default
        let iconset = fm.temporaryDirectory.appendingPathComponent("\(project.slug)-\(UUID().uuidString).iconset")
        try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: iconset) }

        let sizes: [(name: String, px: Int)] = [
            ("icon_16x16", 16), ("icon_16x16@2x", 32),
            ("icon_32x32", 32), ("icon_32x32@2x", 64),
            ("icon_128x128", 128), ("icon_128x128@2x", 256),
            ("icon_256x256", 256), ("icon_256x256@2x", 512),
            ("icon_512x512", 512), ("icon_512x512@2x", 1024),
        ]
        for s in sizes {
            let png = try render(project: project, pixels: s.px)
            try png.write(to: iconset.appendingPathComponent("\(s.name).png"))
        }
        try Generator.run("/usr/bin/iconutil", ["--convert", "icns", "--output", url.path, iconset.path])
    }

    static func render(project: Project, pixels: Int) throws -> Data {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
            throw Generator.Failure(description: "cannot create bitmap for icon")
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx

        let size = CGFloat(pixels)
        // macOS icon grid: the squircle occupies ~80% of the canvas.
        let inset = size * 0.10
        let rect = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
        let path = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.22, yRadius: rect.height * 0.22)
        project.color.setFill()
        path.fill()

        let initial = String(project.name.prefix(1)).uppercased()
        let textColor: NSColor = project.color.luminance > 0.6 ? .black : .white
        let font = NSFont.monospacedSystemFont(ofSize: rect.height * 0.62, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
        let str = NSAttributedString(string: initial, attributes: attrs)
        let textSize = str.size()
        // Center on the glyph box, nudged up slightly to account for descender space.
        let origin = CGPoint(x: rect.midX - textSize.width / 2,
                             y: rect.midY - textSize.height / 2 + rect.height * 0.02)
        str.draw(at: origin)

        NSGraphicsContext.restoreGraphicsState()
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw Generator.Failure(description: "cannot encode icon PNG")
        }
        return data
    }
}
