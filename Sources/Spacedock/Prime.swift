import AppKit
import SwiftUI

// The prime app. A menu bar item lists the registered projects with a running
// indicator; clicking one launches or activates it. A control panel window
// manages the registry and the shared settings. Project windows stay in
// their own apps.

@MainActor
final class ProjectsModel: ObservableObject {
    @Published var registry = Registry()
    @Published var settings = Settings()
    @Published var running: Set<String> = []   // bundle ids
    @Published var lastError: String?

    private var observers: [NSObjectProtocol] = []

    init() {
        reload()
        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshRunning() }
            })
        }
    }

    func reload() {
        do { registry = try Registry.load() } catch { lastError = "projects.json: \(error)" }
        settings = Settings.load()
        refreshRunning()
    }

    func refreshRunning() {
        running = Set(registry.projects.map(\.bundleIdentifier).filter {
            !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty
        })
    }

    func isRunning(_ p: Project) -> Bool { running.contains(p.bundleIdentifier) }

    func runningApp(_ p: Project) -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: p.bundleIdentifier).first
    }

    // MARK: Actions

    /// Launch if not running, otherwise activate. Activating a running app
    /// brings its windows forward and, with the default Mission Control
    /// setting, switches to the Space they are on.
    func open(_ p: Project) {
        if let app = runningApp(p) {
            app.activate()
            return
        }
        let url = Registry.appURL(for: p)
        if !FileManager.default.fileExists(atPath: url.path) {
            do { _ = try Generator.generate(project: p, outputDirectory: Registry.installDirectory) }
            catch { lastError = "\(p.name): \(error)"; return }
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, error in
            if let error { Task { @MainActor in self?.lastError = "\(p.name): \(error.localizedDescription)" } }
        }
    }

    /// The quit Apple event, which the project app answers by closing its
    /// shells. Same path as Cmd-Q.
    func quit(_ p: Project) {
        runningApp(p)?.terminate()
    }

    /// Quit, wait for exit, rewrite the bundle from this binary, relaunch.
    func restart(_ p: Project) {
        guard let app = runningApp(p) else { regenerate(p); open(p); return }
        app.terminate()
        waitForExit(app, deadline: .now() + 3) { [weak self] in
            guard let self else { return }
            if !app.isTerminated { app.forceTerminate() }
            self.regenerate(p)
            self.open(p)
        }
    }

    private func waitForExit(_ app: NSRunningApplication, deadline: DispatchTime, then: @escaping @MainActor () -> Void) {
        if app.isTerminated || DispatchTime.now() >= deadline { then(); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.waitForExit(app, deadline: deadline, then: then)
        }
    }

    func regenerate(_ p: Project) {
        do { _ = try Generator.generate(project: p, outputDirectory: Registry.installDirectory) }
        catch { lastError = "\(p.name): \(error)" }
    }

    /// Rewrites every bundle, prime included. Running apps keep the old
    /// binary until restarted.
    func regenerateAll() {
        do {
            _ = try Generator.generatePrime(outputDirectory: Registry.primeDirectory)
            for p in registry.projects { _ = try Generator.generate(project: p, outputDirectory: Registry.installDirectory) }
        } catch { lastError = "regenerate: \(error)" }
    }

    func add(name: String, colorHex: String, folder: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { lastError = "name is required"; return }
        guard NSColor(hex: colorHex) != nil else { lastError = "color must be #RRGGBB"; return }
        let absolute = URL(fileURLWithPath: (folder as NSString).expandingTildeInPath).standardizedFileURL.path
        let p = Project(name: trimmed, slug: Project.slugify(trimmed), colorHex: colorHex, folder: absolute)
        registry.upsert(p)
        save()
        regenerate(p)
        refreshRunning()
    }

    func update(_ p: Project) {
        registry.upsert(p)
        save()
        regenerate(p)
    }

    func remove(_ p: Project) {
        if let app = runningApp(p) { app.terminate() }
        registry.remove(slug: p.slug)
        save()
        try? FileManager.default.removeItem(at: Registry.appURL(for: p))
        refreshRunning()
    }

    private func save() {
        do { try registry.save() } catch { lastError = "projects.json: \(error)" }
    }

    func saveSettings() {
        do {
            try FileManager.default.createDirectory(at: Registry.supportDirectory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(settings).write(to: Settings.fileURL)
        } catch { lastError = "settings.json: \(error)" }
    }
}

@MainActor
final class PrimeDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let model = ProjectsModel()
    private var statusItem: NSStatusItem!
    private var panel: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "Spacedock")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        // `open ~/Applications/Spacedock.app --args --panel` opens the control panel.
        if CommandLine.arguments.contains("--panel") { showPanel() }
    }

    /// Launching the app again (Finder, Spotlight, `open`) shows the panel.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return false
    }

    // Rebuilt every time the menu opens, so CLI changes to the registry show up.
    func menuNeedsUpdate(_ menu: NSMenu) {
        model.reload()
        menu.removeAllItems()
        if model.registry.projects.isEmpty {
            menu.addItem(withTitle: "No projects", action: nil, keyEquivalent: "")
        }
        for p in model.registry.projects {
            let item = NSMenuItem(title: p.name, action: #selector(openProject(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = p.slug
            item.image = swatch(p.color, running: model.isRunning(p))
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let open = NSMenuItem(title: "Control Panel…", action: #selector(showPanel), keyEquivalent: ",")
        open.target = self
        menu.addItem(open)
        let regen = NSMenuItem(title: "Regenerate All", action: #selector(regenerateAll), keyEquivalent: "")
        regen.target = self
        menu.addItem(regen)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Spacedock", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    /// A filled circle in the project color when running, a ring when not.
    private func swatch(_ color: NSColor, running: Bool) -> NSImage {
        let size = NSSize(width: 12, height: 12)
        let image = NSImage(size: size, flipped: false) { rect in
            let path = NSBezierPath(ovalIn: rect.insetBy(dx: 1.5, dy: 1.5))
            color.setStroke(); color.setFill()
            path.lineWidth = 1.5
            if running { path.fill() } else { path.stroke() }
            return true
        }
        return image
    }

    @objc private func openProject(_ sender: NSMenuItem) {
        guard let slug = sender.representedObject as? String, let p = model.registry.project(slug: slug) else { return }
        model.open(p)
    }

    @objc private func regenerateAll() { model.regenerateAll() }

    @objc func showPanel() {
        if panel == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable],
                             backing: .buffered, defer: false)
            w.title = "Spacedock"
            w.isReleasedWhenClosed = false
            w.contentViewController = NSHostingController(rootView: ControlPanelView(model: model))
            // Center on the screen that holds the menu bar the user clicked,
            // not whichever screen AppKit picks for a windowless app.
            if let screen = NSScreen.main ?? NSScreen.screens.first {
                let f = screen.visibleFrame
                w.setFrameOrigin(NSPoint(x: f.midX - w.frame.width / 2, y: f.midY - w.frame.height / 2))
            }
            w.setFrameAutosaveName("control-panel")
            panel = w
        }
        model.reload()
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Control panel

struct ControlPanelView: View {
    @ObservedObject var model: ProjectsModel

    var body: some View {
        TabView {
            ProjectsTab(model: model).tabItem { Text("Projects") }
            SettingsTab(model: model).tabItem { Text("Settings") }
        }
        .padding()
        .frame(minWidth: 560, minHeight: 400)
        .overlay(alignment: .bottom) {
            if let err = model.lastError {
                HStack {
                    Text(err).font(.callout).foregroundStyle(.red).lineLimit(2)
                    Spacer()
                    Button("Dismiss") { model.lastError = nil }
                }
                .padding(8)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                .padding()
            }
        }
    }
}

struct ProjectsTab: View {
    @ObservedObject var model: ProjectsModel
    @State private var adding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.registry.projects.isEmpty {
                Text("No projects yet.").foregroundStyle(.secondary)
                Spacer()
            } else {
                List(model.registry.projects, id: \.slug) { p in
                    ProjectRow(model: model, project: p)
                }
            }
            HStack {
                Button("Add Project…") { adding = true }
                Button("Regenerate All") { model.regenerateAll() }
                    .help("Rewrite every bundle from the installed binary. Running apps pick it up on restart.")
                Spacer()
                Button("Refresh") { model.reload() }
            }
        }
        .padding(.top, 8)
        .sheet(isPresented: $adding) { AddProjectSheet(model: model) }
    }
}

struct ProjectRow: View {
    @ObservedObject var model: ProjectsModel
    let project: Project

    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(Color(nsColor: project.color)).frame(width: 14, height: 14)
                .overlay(Circle().stroke(Color.primary.opacity(0.2)))
            VStack(alignment: .leading) {
                Text(project.name).font(.headline)
                Text(project.folder.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(model.isRunning(project) ? "running" : "stopped")
                .font(.caption).foregroundStyle(model.isRunning(project) ? .green : .secondary)
            Button(model.isRunning(project) ? "Show" : "Launch") { model.open(project) }
            Menu {
                Button("Restart") { model.restart(project) }
                Button("Quit") { model.quit(project) }.disabled(!model.isRunning(project))
                Button("Regenerate") { model.regenerate(project) }
                Divider()
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([Registry.appURL(for: project)])
                }
                Divider()
                Button("Remove", role: .destructive) { model.remove(project) }
            } label: { Image(systemName: "ellipsis.circle") }
            .menuStyle(.borderlessButton).frame(width: 28)
        }
        .padding(.vertical, 4)
    }
}

struct AddProjectSheet: View {
    @ObservedObject var model: ProjectsModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var color = Color(nsColor: NSColor(hex: "#3B82F6")!)
    @State private var folder = NSHomeDirectory() + "/dev"

    var body: some View {
        Form {
            TextField("Name", text: $name)
            ColorPicker("Color", selection: $color, supportsOpacity: false)
            HStack {
                TextField("Folder", text: $folder)
                Button("Choose…") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.directoryURL = URL(fileURLWithPath: (folder as NSString).expandingTildeInPath)
                    if panel.runModal() == .OK, let url = panel.url { folder = url.path }
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add") {
                    model.add(name: name, colorHex: NSColor(color).hexString, folder: folder)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(width: 420)
    }
}

struct SettingsTab: View {
    @ObservedObject var model: ProjectsModel

    private func double(_ key: WritableKeyPath<Settings, CGFloat>) -> Binding<Double> {
        Binding(get: { Double(model.settings[keyPath: key]) },
                set: { model.settings[keyPath: key] = CGFloat($0) })
    }

    private let cursorStyles = ["blinkBar", "steadyBar", "blinkBlock", "steadyBlock", "blinkUnderline", "steadyUnderline"]

    var body: some View {
        Form {
            TextField("Font name", text: Binding(
                get: { model.settings.fontName ?? "" },
                set: { model.settings.fontName = $0.isEmpty ? nil : $0 }))
                .help("Empty uses the system monospaced font.")
            TextField("Font size", value: double(\.fontSize), format: .number)
            TextField("Padding (pt)", value: double(\.padding), format: .number)
            Picker("Cursor", selection: $model.settings.cursorStyle) {
                ForEach(cursorStyles, id: \.self) { Text($0).tag($0) }
            }
            TextField("Scrollback (lines)", value: $model.settings.scrollback, formatter: NumberFormatter())
            Text("Project apps read settings when they launch. Restart one to apply.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Revert") { model.settings = Settings.load() }
                Button("Save") { model.saveSettings() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(.top, 8)
    }
}

extension NSColor {
    var hexString: String {
        let c = usingColorSpace(.sRGB) ?? self
        return String(format: "#%02X%02X%02X",
                      Int(round(c.redComponent * 255)), Int(round(c.greenComponent * 255)), Int(round(c.blueComponent * 255)))
    }
}
