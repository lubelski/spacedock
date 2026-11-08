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
        let config = NSWorkspace.OpenConfiguration()
        config.activates = !Profile.current.launchesInBackground
        NSWorkspace.shared.openApplication(at: url, configuration: config) { [weak self] _, error in
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
        do { try settings.save() } catch { lastError = "settings.json: \(error)" }
    }

    /// Saves overrides without regenerating: apps read them from the
    /// registry at launch.
    func updateOverrides(_ p: Project) {
        registry.upsert(p)
        save()
    }
}

@MainActor
final class PrimeDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let model = ProjectsModel()
    private var statusItem: NSStatusItem!
    private var panel: NSWindow?
    private var settingsWindow: NSWindow?
    // Separate draft model: refreshing projects must not overwrite unsaved settings.
    private let settingsModel = ProjectsModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "Spacedock")
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked(_:))
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem.button?.toolTip = "Spacedock — click to manage projects; right-click for quick actions"
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        let settings = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(settings)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Spacedock", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
        if CommandLine.arguments.contains(where: { $0.hasPrefix("--settings") }) { showSettings() }
        else if CommandLine.arguments.contains("--panel") { showPanel() }
    }

    /// Launching the app again (Finder, Spotlight, `open`) shows the panel.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return false
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.intersection([.control, .option]).isEmpty == false {
            let menu = NSMenu()
            menu.delegate = self
            // Attach only while tracking; a permanently attached menu consumes normal clicks.
            statusItem.menu = menu
            sender.performClick(nil)
            statusItem.menu = nil
        } else {
            showPanel()
        }
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
        let open = NSMenuItem(title: "Manage Projects…", action: #selector(showPanel), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        let settings = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
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

    @objc func showSettings() {
        if settingsWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            w.title = "Spacedock Settings" + Profile.current.nameSuffix
            // An empty toolbar keeps the tall unified title bar that the
            // sidebar toggle used to bring; the toggle itself is removed.
            w.toolbar = NSToolbar(identifier: "settings")
            w.toolbarStyle = .unified
            w.isReleasedWhenClosed = false
            w.setFrameAutosaveName("settings")
            w.center()
            settingsWindow = w
        }
        if settingsWindow?.isVisible != true {
            settingsModel.reload()
            settingsWindow?.contentViewController = NSHostingController(rootView: SettingsWindowView(model: settingsModel))
        }
        if Profile.current.launchesInBackground {
            settingsWindow?.orderFront(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            settingsWindow?.makeKeyAndOrderFront(nil)
        }
    }

    @objc func showPanel() {
        if panel == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 560),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable],
                             backing: .buffered, defer: false)
            w.title = "Spacedock" + Profile.current.nameSuffix
            w.isReleasedWhenClosed = false
            w.contentViewController = NSHostingController(rootView: ControlPanelView(model: model, showSettings: { [weak self] in self?.showSettings() }))
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
        if Profile.current.launchesInBackground {
            panel?.orderFront(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            panel?.makeKeyAndOrderFront(nil)
        }
    }
}

// MARK: - Project management

/// A vertical list of projects with running state and per-project actions.
/// The gear opens the separate settings window; nothing about shared
/// settings lives here.
struct ControlPanelView: View {
    @ObservedObject var model: ProjectsModel
    @State private var adding = false

    var showSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("Projects").font(.title2.bold())
                Text("\(model.registry.projects.count)")
                    .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
                Button { adding = true } label: { Label("Add Project", systemImage: "plus") }
                    .keyboardShortcut("n", modifiers: .command)
                    .help("Register a project and install its app")
                Menu {
                    Button("Regenerate All") { model.regenerateAll() }
                        .help("Rewrite every bundle from the installed binary. Running apps pick it up on restart.")
                    Button("Refresh") { model.reload() }.keyboardShortcut("r", modifiers: .command)
                    Divider()
                    Button("Reveal Apps in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([Registry.installDirectory])
                    }
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).frame(width: 28)
                Button(action: showSettings) { Image(systemName: "gearshape") }
                    .keyboardShortcut(",", modifiers: .command)
                    .help("Settings")
            }
            .padding(16)

            Divider()

            if model.registry.projects.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "square.grid.2x2").font(.system(size: 36)).foregroundStyle(.tertiary)
                    Text("No projects yet").font(.headline)
                    Text("Each project becomes its own app with a Dock tile, a Cmd-Tab entry, and a Space.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Add Project…") { adding = true }.padding(.top, 4)
                }
                .frame(maxWidth: 320, maxHeight: .infinity)
                .frame(maxWidth: .infinity)
            } else {
                List(model.registry.projects, id: \.slug) { p in
                    ProjectRow(model: model, project: p)
                        .listRowSeparator(.visible)
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(minWidth: 460, minHeight: 360)
        .sheet(isPresented: $adding) { AddProjectSheet(model: model) }
        .overlay(alignment: .bottom) {
            if let err = model.lastError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(err).font(.callout).lineLimit(2)
                    Spacer()
                    Button("Dismiss") { model.lastError = nil }.controlSize(.small)
                }
                .padding(10)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                .padding(12)
            }
        }
    }
}

struct ProjectRow: View {
    @ObservedObject var model: ProjectsModel
    let project: Project
    @State private var editing = false

    private var running: Bool { model.isRunning(project) }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color(nsColor: project.color)).frame(width: 16, height: 16)
                    .overlay(Circle().stroke(Color.primary.opacity(0.15)))
                if running {
                    Circle().fill(.white).frame(width: 5, height: 5)
                }
            }
            .help(running ? "Running" : "Stopped")
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name).font(.headline)
                Text(project.folder.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Text(running ? "Running" : "Stopped")
                .font(.caption.weight(.medium))
                .foregroundStyle(running ? Color.green : Color.secondary)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background((running ? Color.green : Color.secondary).opacity(0.12), in: Capsule())
            Button(running ? "Show" : "Launch") { model.open(project) }
                .frame(width: 64)
            Menu {
                Button("Project Settings…") { editing = true }
                Divider()
                Button("Restart") { model.restart(project) }
                Button("Quit") { model.quit(project) }.disabled(!running)
                Button("Regenerate") { model.regenerate(project) }
                Divider()
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([Registry.appURL(for: project)])
                }
                Button("Open Folder in Finder") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: project.folder))
                }
                Divider()
                Button("Remove", role: .destructive) { model.remove(project) }
            } label: { Image(systemName: "ellipsis.circle") }
            .menuStyle(.borderlessButton).frame(width: 28)
        }
        .padding(.vertical, 6)
        .sheet(isPresented: $editing) { ProjectSettingsSheet(model: model, project: project) }
    }
}

/// Per-project overrides. Empty fields inherit the global value. Raw Ghostty
/// keys are one `key = value` per line.
struct ProjectSettingsSheet: View {
    @ObservedObject var model: ProjectsModel
    let project: Project
    @Environment(\.dismiss) private var dismiss
    @State private var override: SettingsOverride
    @State private var ghosttyText: String
    @State private var error: String?
    private let global: Settings

    init(model: ProjectsModel, project: Project) {
        self.model = model
        self.project = project
        global = model.settings
        _override = State(initialValue: project.settings ?? SettingsOverride())
        _ghosttyText = State(initialValue: GhosttyKeyText.render(project.ghostty ?? [:]))
    }

    private func text(_ key: WritableKeyPath<SettingsOverride, String?>) -> Binding<String> {
        Binding(get: { override[keyPath: key] ?? "" }, set: { override[keyPath: key] = $0.isEmpty ? nil : $0 })
    }
    private func number(_ key: WritableKeyPath<SettingsOverride, CGFloat?>) -> Binding<String> {
        Binding(get: { override[keyPath: key].map { "\($0)" } ?? "" },
                set: { override[keyPath: key] = Double($0).map { CGFloat($0) } })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(project.name) settings").font(.headline)
            Text("Empty fields inherit the global value. Changes apply at the project's next launch.")
                .font(.caption).foregroundStyle(.secondary)
            Form {
                Picker("Emulator", selection: Binding(get: { override.emulator ?? "" }, set: { override.emulator = $0.isEmpty ? nil : $0 })) {
                    Text("Inherit (\(global.emulator))").tag("")
                    Text("ghostty").tag("ghostty")
                    Text("swiftterm").tag("swiftterm")
                }
                TextField("Font name", text: text(\.fontName), prompt: Text(global.fontName ?? "system monospaced"))
                TextField("Font size", text: number(\.fontSize), prompt: Text("\(global.fontSize)"))
                TextField("Padding (pt)", text: number(\.padding), prompt: Text("\(global.padding)"))
                Picker("Cursor", selection: Binding(get: { override.cursorStyle ?? "" }, set: { override.cursorStyle = $0.isEmpty ? nil : $0 })) {
                    Text("Inherit (\(global.cursorStyle))").tag("")
                    ForEach(["blinkBar", "steadyBar", "blinkBlock", "steadyBlock", "blinkUnderline", "steadyUnderline"], id: \.self) { Text($0).tag($0) }
                }
                TextField("Scrollback (lines)", text: Binding(get: { override.scrollback.map(String.init) ?? "" },
                                                              set: { override.scrollback = Int($0) }),
                          prompt: Text("\(global.scrollback)"))
            }
            Text("Ghostty options, one `key = value` per line. Applied after the fields above; ghostty emulator only.")
                .font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $ghosttyText)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 100)
                .border(Color.secondary.opacity(0.3))
            if let error { Text(error).font(.callout).foregroundStyle(.red) }
            HStack {
                Link("Config reference", destination: URL(string: "https://ghostty.org/docs/config/reference")!)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    switch GhosttyKeyText.parse(ghosttyText) {
                    case .failure(let e): error = e
                    case .success(let map):
                        var p = project
                        p.settings = override.isEmpty ? nil : override
                        p.ghostty = map.isEmpty ? nil : map
                        model.updateOverrides(p)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 520)
    }
}

enum GhosttyKeyText {
    static func render(_ map: [String: String]) -> String {
        map.sorted { $0.key < $1.key }.map { "\($0.key) = \($0.value)" }.joined(separator: "\n")
    }

    static func parse(_ text: String) -> Result<[String: String], String> {
        var map: [String: String] = [:]
        for (n, raw) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let eq = line.firstIndex(of: "=") else { return .failure("line \(n + 1): expected key = value") }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if key.isEmpty { return .failure("line \(n + 1): empty key") }
            map[key] = value
        }
        return .success(map)
    }
}

extension String: @retroactive Error {}

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

extension NSColor {
    var hexString: String {
        let c = usingColorSpace(.sRGB) ?? self
        return String(format: "#%02X%02X%02X",
                      Int(round(c.redComponent * 255)), Int(round(c.greenComponent * 255)), Int(round(c.blueComponent * 255)))
    }
}
