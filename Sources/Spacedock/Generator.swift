import AppKit
import Foundation

/// Writes a standalone `.app` bundle for one project. The bundle's executable
/// is a copy of the currently running binary, so every generated app is the
/// same program reading a different `project.json`.
enum Generator {
    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    /// What a bundle needs beyond the shared executable.
    struct Spec {
        var name: String
        var bundleIdentifier: String
        var executableName: String
        var color: NSColor
        var content: IconContent
        /// Written to `Resources/project.json` when present.
        var project: Project?
        /// Extra Info.plist keys, e.g. `LSUIElement` for the prime app.
        var extraPlist: [String: Any] = [:]
    }

    static let primeRoleKey = "SpacedockRole"
    static let primeRoleValue = "prime"

    /// The prime app: menu bar control panel, no Dock tile, bundle id without a slug.
    static func primeSpec() -> Spec {
        Spec(name: "Spacedock" + Profile.current.nameSuffix,
             bundleIdentifier: Profile.current.bundlePrefix,
             executableName: "spacedock",
             color: NSColor(hex: "#334155") ?? .darkGray,
             content: .text("S"),
             project: nil,
             extraPlist: ["LSUIElement": true, primeRoleKey: primeRoleValue])
    }

    static func generate(project: Project, outputDirectory: URL) throws -> URL {
        try generate(Spec(name: project.displayName,
                          bundleIdentifier: project.bundleIdentifier,
                          executableName: project.slug,
                          color: project.color,
                          content: project.iconContent,
                          project: project),
                     outputDirectory: outputDirectory)
    }

    static func generatePrime(outputDirectory: URL) throws -> URL {
        try generate(primeSpec(), outputDirectory: outputDirectory)
    }

    static func generate(_ spec: Spec, outputDirectory: URL) throws -> URL {
        let fm = FileManager.default
        let appURL = outputDirectory.appendingPathComponent("\(spec.name).app")
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
        let exeURL = macOS.appendingPathComponent(spec.executableName)
        try fm.copyItem(at: selfURL.resolvingSymlinksInPath(), to: exeURL)

        // SwiftPM resource bundles sit next to the executable in the build
        // directory. `Bundle.module` looks in `Bundle.main.resourceURL`, so
        // copy them into Resources. GhosttyTerminal ships terminfo and shell
        // integration this way; SwiftTerm has none.
        let siblings = try fm.contentsOfDirectory(at: selfURL.resolvingSymlinksInPath().deletingLastPathComponent(),
                                                  includingPropertiesForKeys: nil)
        for sibling in siblings where sibling.pathExtension == "bundle" {
            try fm.copyItem(at: sibling, to: resources.appendingPathComponent(sibling.lastPathComponent))
        }
        if let ownResources = Bundle.main.resourceURL, ownResources != selfURL.deletingLastPathComponent() {
            // Regenerating from an installed app: its Resources hold the bundles.
            for sibling in (try? fm.contentsOfDirectory(at: ownResources, includingPropertiesForKeys: nil)) ?? []
            where sibling.pathExtension == "bundle" && !fm.fileExists(atPath: resources.appendingPathComponent(sibling.lastPathComponent).path) {
                try fm.copyItem(at: sibling, to: resources.appendingPathComponent(sibling.lastPathComponent))
            }
        }

        // Project definition.
        if let project = spec.project {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(project).write(to: resources.appendingPathComponent("project.json"))
        }

        // Icon.
        try IconRenderer.writeICNS(color: spec.color, content: spec.content, slug: spec.executableName,
                                   badge: Profile.current.isDefault ? nil : Profile.current.name,
                                   to: resources.appendingPathComponent("AppIcon.icns"))

        // Info.plist.
        var plist: [String: Any] = [
            "CFBundleDevelopmentRegion": "en",
            "CFBundleExecutable": spec.executableName,
            "CFBundleIconFile": "AppIcon",
            "CFBundleIdentifier": spec.bundleIdentifier,
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundleName": spec.name,
            "CFBundleDisplayName": spec.name,
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "0.1",
            "CFBundleVersion": "1",
            "LSMinimumSystemVersion": "14.0",
            "NSHighResolutionCapable": true,
            "NSPrincipalClass": "NSApplication",
            "NSAppleScriptEnabled": true,
        ]
        if !Profile.current.isDefault { plist[Profile.plistKey] = Profile.current.name }
        plist.merge(spec.extraPlist) { _, new in new }
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

/// Renders a project icon, written out as an `.icns` through `iconutil`.
/// Every icon is a rounded square in the project color. Inside it sits the
/// project's letters, or its image framed on a light plate, or its image
/// filling the square inside a ring of the project color.
enum IconRenderer {
    static func writeICNS(color: NSColor, content: IconContent, slug: String, badge: String? = nil, to url: URL) throws {
        let fm = FileManager.default
        let iconset = fm.temporaryDirectory.appendingPathComponent("\(slug)-\(UUID().uuidString).iconset")
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
            let png = try render(color: color, content: content, badge: badge, pixels: s.px)
            try png.write(to: iconset.appendingPathComponent("\(s.name).png"))
        }
        try Generator.run("/usr/bin/iconutil", ["--convert", "icns", "--output", url.path, iconset.path])
    }

    /// The icon as an image, for previews in the control panel.
    static func image(color: NSColor, content: IconContent, pixels: Int = 128) -> NSImage? {
        guard let data = try? render(color: color, content: content, pixels: pixels) else { return nil }
        return NSImage(data: data)
    }

    static func render(color: NSColor, content: IconContent, badge: String? = nil, pixels: Int) throws -> Data {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
            throw Generator.Failure(description: "cannot create bitmap for icon")
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        ctx.imageInterpolation = .high

        let size = CGFloat(pixels)
        // macOS icon grid: the squircle occupies ~80% of the canvas.
        let inset = size * 0.10
        let rect = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
        let radius = rect.width * 0.22
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        color.setFill()
        path.fill()

        switch content {
        case .text(let text):
            drawText(text, in: rect, color: color)
        case .image(let picture, .framed):
            // A light plate inset from the edge, its corners concentric with
            // the squircle's. The ring of project color around it is what
            // marks the icon as a Spacedock project.
            let gap = rect.width * 0.12
            let plate = rect.insetBy(dx: gap, dy: gap)
            let plateRadius = max(radius - gap, plate.width * 0.08)
            let platePath = NSBezierPath(roundedRect: plate, xRadius: plateRadius, yRadius: plateRadius)
            NSColor.white.setFill()
            platePath.fill()
            NSGraphicsContext.saveGraphicsState()
            platePath.addClip()
            draw(picture, fitting: plate.insetBy(dx: plate.width * 0.10, dy: plate.height * 0.10))
            NSGraphicsContext.restoreGraphicsState()
            NSColor.black.withAlphaComponent(0.10).setStroke()
            platePath.lineWidth = max(1, size / 256)
            platePath.stroke()
        case .image(let picture, .fill):
            NSGraphicsContext.saveGraphicsState()
            path.addClip()
            draw(picture, filling: rect)
            NSGraphicsContext.restoreGraphicsState()
            let ring = rect.width * 0.07
            let ringRect = rect.insetBy(dx: ring / 2, dy: ring / 2)
            let ringPath = NSBezierPath(roundedRect: ringRect, xRadius: radius - ring / 2, yRadius: radius - ring / 2)
            ringPath.lineWidth = ring
            color.setStroke()
            ringPath.stroke()
        }

        // Profile badge: a dark band across the bottom with the profile name,
        // so a development copy never passes for the installed one.
        if let badge, pixels >= 64 {
            let band = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * 0.26)
            let bandPath = NSBezierPath(roundedRect: band, xRadius: rect.width * 0.22, yRadius: rect.height * 0.22)
            bandPath.appendRect(CGRect(x: band.minX, y: band.midY, width: band.width, height: band.height / 2))
            NSColor.black.withAlphaComponent(0.72).setFill()
            bandPath.fill()
            let bfont = NSFont.systemFont(ofSize: band.height * 0.55, weight: .bold)
            let battrs: [NSAttributedString.Key: Any] = [.font: bfont, .foregroundColor: NSColor.white]
            let bstr = NSAttributedString(string: badge.uppercased(), attributes: battrs)
            let bsize = bstr.size()
            bstr.draw(at: CGPoint(x: band.midX - bsize.width / 2, y: band.midY - bsize.height / 2))
        }

        NSGraphicsContext.restoreGraphicsState()
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw Generator.Failure(description: "cannot encode icon PNG")
        }
        return data
    }

    /// Letters centered on their cap height, scaled down to fit the width:
    /// one letter at 62% of the square's height, three at about 41%.
    private static func drawText(_ text: String, in rect: CGRect, color: NSColor) {
        let textColor: NSColor = color.luminance > 0.6 ? .black : .white
        var font = NSFont.monospacedSystemFont(ofSize: rect.height * 0.62, weight: .semibold)
        var str = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: textColor])
        let maxWidth = rect.width * 0.74
        if str.size().width > maxWidth {
            font = NSFont.monospacedSystemFont(ofSize: font.pointSize * maxWidth / str.size().width, weight: .semibold)
            str = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: textColor])
        }
        let width = str.size().width
        // draw(at:) places the line box's bottom at the origin; the baseline
        // sits |descender| above it.
        let baseline = rect.midY - font.capHeight / 2
        str.draw(at: CGPoint(x: rect.midX - width / 2, y: baseline + font.descender))
    }

    private static func draw(_ picture: NSImage, fitting box: CGRect) {
        let s = picture.size
        guard s.width > 0, s.height > 0 else { return }
        let scale = min(box.width / s.width, box.height / s.height)
        let w = s.width * scale, h = s.height * scale
        picture.draw(in: CGRect(x: box.midX - w / 2, y: box.midY - h / 2, width: w, height: h))
    }

    private static func draw(_ picture: NSImage, filling box: CGRect) {
        let s = picture.size
        guard s.width > 0, s.height > 0 else { return }
        let scale = max(box.width / s.width, box.height / s.height)
        let w = s.width * scale, h = s.height * scale
        picture.draw(in: CGRect(x: box.midX - w / 2, y: box.midY - h / 2, width: w, height: h))
    }
}
