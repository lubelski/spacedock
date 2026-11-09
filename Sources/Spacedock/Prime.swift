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
    /// A project the panel should select, set by `--edit SLUG`.
    @Published var requestedSelection: String?

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
        guard p.isLaunchable else {
            lastError = "\(p.name.isEmpty ? p.slug : p.name): \(p.problems.joined(separator: ", "))"
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
        guard p.isLaunchable else { return }
        do { _ = try Generator.generate(project: p, outputDirectory: Registry.installDirectory) }
        catch { lastError = "\(p.name): \(error)" }
    }

    /// Rewrites every bundle, prime included. Running apps keep the old
    /// binary until restarted.
    func regenerateAll() {
        do {
            _ = try Generator.generatePrime(outputDirectory: Registry.primeDirectory)
            for p in registry.projects where p.isLaunchable {
                _ = try Generator.generate(project: p, outputDirectory: Registry.installDirectory)
            }
        } catch { lastError = "regenerate: \(error)" }
    }

    /// Registers a placeholder row and returns its slug for selection.
    func addNew() -> String? {
        do { return try registry.addNew().slug } catch { lastError = "projects.json: \(error)"; return nil }
    }

    /// Renames, recolors, or moves a project. Returns the slug after the
    /// edit, which changes on rename until the bundle is first installed.
    @discardableResult
    func edit(_ slug: String, _ change: (inout Project) -> Void) -> String? {
        do {
            let p = try registry.edit(slug: slug, change)
            refreshRunning()
            return p.slug
        } catch {
            lastError = "\(slug): \(error)"
            return nil
        }
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
        let restartPrime = NSMenuItem(title: "Restart Spacedock", action: #selector(restartSelf), keyEquivalent: "")
        restartPrime.target = self
        appMenu.addItem(restartPrime)
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
        let args = CommandLine.arguments
        if args.contains(where: { $0.hasPrefix("--settings") }) { showSettings() }
        else if let i = args.firstIndex(of: "--edit"), i + 1 < args.count {
            model.requestedSelection = args[i + 1]
            showPanel()
        }
        else if args.contains("--panel") { showPanel() }
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
            // A project that cannot launch shows disabled (no action).
            let action = p.isLaunchable || model.isRunning(p) ? #selector(openProject(_:)) : nil
            let item = NSMenuItem(title: p.name, action: action, keyEquivalent: "")
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
        let restartPrime = NSMenuItem(title: "Restart Spacedock", action: #selector(restartSelf), keyEquivalent: "")
        restartPrime.target = self
        menu.addItem(restartPrime)
        menu.addItem(withTitle: "Quit Spacedock", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    /// Relaunches this prime app from its bundle on disk, so a regenerated
    /// bundle takes effect. A detached shell waits for this pid to exit, then
    /// opens the bundle. Project apps keep running.
    @objc private func restartSelf() {
        let pid = ProcessInfo.processInfo.processIdentifier
        let bundle = Bundle.main.bundleURL.path
        let flag = Profile.current.launchesInBackground ? "-g " : ""
        let script = "while kill -0 \(pid) 2>/dev/null; do sleep 0.1; done; /usr/bin/open \(flag)\"$1\""
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", script, "sh", bundle]
        do { try p.run() } catch { model.lastError = "restart: \(error)"; return }
        NSApp.terminate(nil)
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
            // An empty toolbar keeps the tall unified title bar; the sidebar
            // toggle is removed. The title is drawn centered by the view as a
            // principal toolbar item, so AppKit's leading title is hidden.
            w.toolbar = NSToolbar(identifier: "settings")
            w.toolbarStyle = .unified
            w.titleVisibility = .hidden
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

/// A vertical list of projects. `+` registers a placeholder row and opens
/// its editor in a sheet; double-click or Edit… opens the editor for any
/// row. The gear opens the separate settings window.
struct ControlPanelView: View {
    @ObservedObject var model: ProjectsModel
    @State private var selection: String?
    /// The slug whose editor sheet is open.
    @State private var editing: String?

    var showSettings: () -> Void

    private func takeRequestedSelection() {
        guard let slug = model.requestedSelection else { return }
        selection = slug
        editing = slug
        model.requestedSelection = nil
    }

    private func addProject() {
        if let slug = model.addNew() { selection = slug; editing = slug }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("Projects").font(.title2.bold())
                Text("\(model.registry.projects.count)")
                    .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
                Button(action: addProject) { Label("New Project", systemImage: "plus") }
                    .keyboardShortcut("n", modifiers: .command)
                    .help("Add a project row and edit it")
                Menu {
                    Button("Regenerate All") { model.regenerateAll() }
                        .help("Rewrite every bundle from the installed binary. Running apps pick it up on restart.")
                    Button("Refresh") { model.reload() }.keyboardShortcut("r", modifiers: .command)
                    Divider()
                    Button("Reveal Apps in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([Registry.installDirectory])
                    }
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
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
                    Button("New Project", action: addProject).padding(.top, 4)
                }
                .frame(maxWidth: 320, maxHeight: .infinity)
                .frame(maxWidth: .infinity)
            } else {
                List(selection: $selection) {
                    ForEach(model.registry.projects, id: \.slug) { p in
                        ProjectRow(model: model, project: p, edit: { editing = p.slug })
                            .tag(p.slug)
                            .listRowSeparator(.visible)
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .contextMenu(forSelectionType: String.self, menu: { _ in }, primaryAction: { slugs in
                    if let slug = slugs.first { editing = slug }
                })
            }
        }
        .frame(minWidth: 460, minHeight: 360)
        .sheet(isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            if let slug = editing, let p = model.registry.project(slug: slug) {
                VStack(spacing: 0) {
                    ProjectEditor(model: model, project: p, slug: $editing)
                    Divider()
                    HStack {
                        Spacer()
                        Button("Done") { editing = nil }.keyboardShortcut(.defaultAction)
                    }
                    .padding(12)
                }
                .frame(width: 440, height: 380)
            }
        }
        .onAppear(perform: takeRequestedSelection)
        .onChange(of: model.requestedSelection) { _, _ in takeRequestedSelection() }
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
    var edit: () -> Void

    private var running: Bool { model.isRunning(project) }

    var body: some View {
        HStack(spacing: 12) {
            ProjectIcon(project: project, size: 32)
                .overlay(alignment: .bottomTrailing) {
                    if running {
                        Circle().fill(.green).frame(width: 9, height: 9)
                            .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 2))
                    }
                }
                .help(running ? "Running" : "Stopped")
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name.isEmpty ? "Untitled" : project.name).font(.headline)
                if let problem = project.problems.first {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange).lineLimit(1)
                } else {
                    Text(project.folder.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer()
            Text(running ? "Running" : "Stopped")
                .font(.caption.weight(.medium))
                .foregroundStyle(running ? Color.green : Color.secondary)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background((running ? Color.green : Color.secondary).opacity(0.12), in: Capsule())
            Button(running ? "Show" : "Launch") { model.open(project) }
                .frame(width: 64)
                .disabled(!running && !project.isLaunchable)
            Menu {
                Button("Edit…", action: edit)
                Divider()
                Button("Restart") { model.restart(project) }.disabled(!project.isLaunchable)
                Button("Quit") { model.quit(project) }.disabled(!running)
                Button("Regenerate") { model.regenerate(project) }.disabled(!project.isLaunchable)
                Divider()
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([Registry.appURL(for: project)])
                }
                Button("Open Folder in Finder") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: project.folder))
                }
                .disabled(project.folder.isEmpty)
                Divider()
                Button("Remove", role: .destructive) { model.remove(project) }
            } label: { Image(systemName: "ellipsis.circle") }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        }
        .padding(.vertical, 6)
    }
}

/// The project's icon as the bundle draws it, rendered on demand. Keyed on
/// what the icon depends on, so an edit redraws it and a refresh does not.
struct ProjectIcon: View {
    let project: Project
    var size: CGFloat

    @MainActor private static var cache: [String: NSImage] = [:]

    private var image: NSImage? {
        let key = [project.colorHex, project.avatarText, project.image ?? "", project.imageStyle?.rawValue ?? ""].joined(separator: "|")
        if let hit = Self.cache[key] { return hit }
        let img = IconRenderer.image(color: project.color, content: project.iconContent, pixels: 256)
        Self.cache[key] = img
        return img
    }

    var body: some View {
        if let image {
            Image(nsImage: image).resizable().interpolation(.high).frame(width: size, height: size)
        } else {
            RoundedRectangle(cornerRadius: size * 0.2).fill(Color(nsColor: project.color)).frame(width: size, height: size)
        }
    }
}

/// Name, color, and folder of one project, shown in a sheet and saved as they change: the name
/// on Return or when the field loses focus, the color after the picker
/// settles, the folder when chosen. Terminal overrides stay in their sheet.
struct ProjectEditor: View {
    @ObservedObject var model: ProjectsModel
    let project: Project
    /// The edited slug; updated when a rename changes it.
    @Binding var slug: String?
    @State private var name: String
    @State private var color: Color
    @State private var colorCommit: Task<Void, Never>?
    @State private var avatar: String
    @State private var showingTerminalSettings = false
    @FocusState private var nameFocused: Bool
    @FocusState private var avatarFocused: Bool

    init(model: ProjectsModel, project: Project, slug: Binding<String?>) {
        self.model = model
        self.project = project
        _slug = slug
        _name = State(initialValue: project.name)
        _color = State(initialValue: Color(nsColor: project.color))
        _avatar = State(initialValue: project.avatar ?? "")
    }

    /// Applies an edit and follows the slug if a rename changed it.
    private func commit(_ change: (inout Project) -> Void) {
        if let new = model.edit(project.slug, change), new != project.slug { slug = new }
    }

    private func commitName() {
        guard name.trimmingCharacters(in: .whitespaces) != project.name else { return }
        commit { $0.name = name }
    }

    private func commitAvatar() {
        let a = avatar.trimmingCharacters(in: .whitespaces)
        guard a != (project.avatar ?? "") else { return }
        commit { $0.avatar = a }
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        panel.prompt = "Use Image"
        panel.message = "Choose a logo or picture for the project icon. Spacedock keeps a copy."
        if !project.folder.isEmpty { panel.directoryURL = project.folderURL }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let copy = try Registry.importImage(url.path)
            commit { $0.image = copy }
        } catch {
            model.lastError = "\(project.name): \(error)"
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Choose"
        panel.directoryURL = project.folder.isEmpty
            ? URL(fileURLWithPath: NSHomeDirectory() + "/dev")
            : project.folderURL
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // A placeholder name gives way to the folder's name.
        let rename = project.name.hasPrefix("New Project") && name == project.name
        if rename { name = url.lastPathComponent }
        commit { p in
            p.folder = url.path
            if rename { p.name = url.lastPathComponent }
        }
    }

    var body: some View {
        Form {
            Section("Project") {
                TextField("Name", text: $name)
                    .focused($nameFocused)
                    .onSubmit(commitName)
                ColorPicker("Color", selection: $color, supportsOpacity: false)
                LabeledContent("Folder") {
                    HStack(spacing: 6) {
                        Text(project.folder.isEmpty ? "None" : project.folder.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                            .foregroundStyle(project.folder.isEmpty ? .secondary : .primary)
                            .lineLimit(1).truncationMode(.middle)
                            .help(project.folder)
                        Button("Choose…", action: chooseFolder)
                    }
                }
            }
            Section {
                HStack(alignment: .top, spacing: 16) {
                    ProjectIcon(project: project, size: 72)
                    VStack(alignment: .leading, spacing: 8) {
                        if project.image == nil {
                            TextField("Letters", text: $avatar, prompt: Text(Project.initials(name)))
                                .focused($avatarFocused)
                                .onSubmit(commitAvatar)
                        }
                        HStack(spacing: 6) {
                            Button(project.image == nil ? "Choose Image…" : "Change Image…", action: chooseImage)
                            if project.image != nil {
                                Button("Remove Image") { commit { $0.image = nil } }
                            }
                        }
                        if project.image != nil {
                            Picker("Style", selection: Binding(
                                get: { project.imageStyle ?? .framed },
                                set: { style in commit { $0.imageStyle = style } })) {
                                Text("Framed").tag(IconImageStyle.framed)
                                Text("Fill").tag(IconImageStyle.fill)
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                }
            } header: {
                Text("Icon")
            } footer: {
                Text(project.image != nil
                     ? "Framed puts the image on a light plate inside the project color. Fill covers the icon, with a ring of the project color."
                     : "Up to \(Project.avatarLimit) characters. Empty uses the initials of the name.")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !project.problems.isEmpty {
                Section {
                    ForEach(project.problems, id: \.self) { problem in
                        Label(problem, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                } footer: {
                    Text("The project stays in the list. It cannot launch until this is fixed.")
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Section {
                Button("Terminal Settings…") { showingTerminalSettings = true }
            } footer: {
                Text(model.isRunning(project)
                     ? "Running. Name, color, icon, and folder changes apply when the app next launches."
                     : "Changes save as you make them.")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formStyle(.grouped)
        .onChange(of: nameFocused) { _, focused in if !focused { commitName() } }
        .onChange(of: avatarFocused) { _, focused in if !focused { commitAvatar() } }
        .onChange(of: avatar) { _, value in
            if value.count > Project.avatarLimit { avatar = String(value.prefix(Project.avatarLimit)) }
        }
        .onChange(of: color) { _, newColor in
            colorCommit?.cancel()
            let hex = NSColor(newColor).hexString
            colorCommit = Task {
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled, hex != project.colorHex.uppercased() else { return }
                commit { $0.colorHex = hex }
            }
        }
        .onDisappear { commitName(); commitAvatar() }
        .sheet(isPresented: $showingTerminalSettings) { ProjectSettingsSheet(model: model, project: project) }
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

extension NSColor {
    var hexString: String {
        let c = usingColorSpace(.sRGB) ?? self
        return String(format: "#%02X%02X%02X",
                      Int(round(c.redComponent * 255)), Int(round(c.greenComponent * 255)), Int(round(c.blueComponent * 255)))
    }
}
