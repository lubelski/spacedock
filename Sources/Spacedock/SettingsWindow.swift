import AppKit
import SwiftUI

// The global settings window, in the System Settings idiom: a sidebar of
// sections with a search field above it, and one grouped form per section.
// Each row carries a title, a one-line description, and its control; a row
// whose value differs from the default shows a dot and, on hover, a Reset
// button. Changes save to settings.json when a control commits; there is no
// Save button. Adding a setting means adding one `SettingSpec` to
// `SettingsSchema.all`; search and the sidebar follow from that.

enum SettingsSection: String, CaseIterable, Identifiable {
    case terminal = "Terminal"
    case text = "Text"
    case window = "Window"
    case ghostty = "Ghostty"
    case advanced = "Advanced"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .terminal: "terminal"
        case .text: "textformat"
        case .window: "macwindow"
        case .ghostty: "slider.horizontal.3"
        case .advanced: "wrench.and.screwdriver"
        }
    }

    /// Shown under the section heading.
    var summary: String {
        switch self {
        case .terminal: "Which emulator runs in each project window and how much it remembers."
        case .text: "Font for the terminal text."
        case .window: "Spacing and cursor inside the project window."
        case .ghostty: "Raw Ghostty configuration, applied after the settings above. Only the ghostty emulator reads these keys."
        case .advanced: "The settings file itself."
        }
    }
}

/// One setting: where it lives in `Settings`, how it is edited, and the words
/// around it. `id` is the key `Spacedock set --global` accepts.
struct SettingSpec: Identifiable {
    enum Control {
        /// Optional string. Empty means "use the placeholder behavior".
        case optionalText(WritableKeyPath<Settings, String?>, placeholder: String)
        case number(WritableKeyPath<Settings, CGFloat>, range: ClosedRange<Double>, step: Double)
        case integer(WritableKeyPath<Settings, Int>, range: ClosedRange<Int>)
        case choice(WritableKeyPath<Settings, String>, options: [(value: String, label: String)])
    }

    let id: String
    let section: SettingsSection
    let title: String
    let description: String
    let control: Control

    func isModified(_ s: Settings) -> Bool {
        let d = Settings()
        switch control {
        case .optionalText(let k, _): return s[keyPath: k] != d[keyPath: k]
        case .number(let k, _, _): return s[keyPath: k] != d[keyPath: k]
        case .integer(let k, _): return s[keyPath: k] != d[keyPath: k]
        case .choice(let k, _): return s[keyPath: k] != d[keyPath: k]
        }
    }

    func reset(_ s: inout Settings) {
        let d = Settings()
        switch control {
        case .optionalText(let k, _): s[keyPath: k] = d[keyPath: k]
        case .number(let k, _, _): s[keyPath: k] = d[keyPath: k]
        case .integer(let k, _): s[keyPath: k] = d[keyPath: k]
        case .choice(let k, _): s[keyPath: k] = d[keyPath: k]
        }
    }

    func matches(_ query: String) -> Bool {
        let q = query.lowercased()
        return q.isEmpty || id.lowercased().contains(q) || title.lowercased().contains(q)
            || description.lowercased().contains(q) || section.rawValue.lowercased().contains(q)
    }
}

enum SettingsSchema {
    static let cursorStyles: [(value: String, label: String)] = [
        ("blinkBar", "Bar, blinking"), ("steadyBar", "Bar, steady"),
        ("blinkBlock", "Block, blinking"), ("steadyBlock", "Block, steady"),
        ("blinkUnderline", "Underline, blinking"), ("steadyUnderline", "Underline, steady"),
    ]

    static let all: [SettingSpec] = [
        SettingSpec(id: "emulator", section: .terminal, title: "Emulator",
                    description: "Ghostty is the default. SwiftTerm is kept for compatibility and ignores the Ghostty section.",
                    control: .choice(\.emulator, options: [("ghostty", "Ghostty"), ("swiftterm", "SwiftTerm (compatibility)")])),
        SettingSpec(id: "scrollback", section: .terminal, title: "Scrollback",
                    description: "Lines of output kept above the visible screen.",
                    control: .integer(\.scrollback, range: 0...1_000_000)),
        SettingSpec(id: "fontName", section: .text, title: "Font",
                    description: "PostScript or family name of an installed font. Leave empty for the system monospaced font.",
                    control: .optionalText(\.fontName, placeholder: "System monospaced")),
        SettingSpec(id: "fontSize", section: .text, title: "Font size",
                    description: "In points.",
                    control: .number(\.fontSize, range: 6...72, step: 1)),
        SettingSpec(id: "padding", section: .window, title: "Padding",
                    description: "Space in points between the window edge and the terminal grid.",
                    control: .number(\.padding, range: 0...64, step: 1)),
        SettingSpec(id: "cursorStyle", section: .window, title: "Cursor",
                    description: "Shape of the cursor and whether it blinks.",
                    control: .choice(\.cursorStyle, options: cursorStyles)),
    ]

    static func specs(in section: SettingsSection) -> [SettingSpec] { all.filter { $0.section == section } }
}

// MARK: - Window

struct SettingsWindowView: View {
    @ObservedObject var model: ProjectsModel
    @State private var selection: SettingsSection?
    @State private var query: String

    /// `--settings-section NAME` and `--settings-query TEXT` pick the first
    /// view, for screenshots and tests. Default is the first section.
    init(model: ProjectsModel) {
        self.model = model
        let args = CommandLine.arguments
        func value(_ flag: String) -> String? { args.firstIndex(of: flag).flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } }
        _selection = State(initialValue: value("--settings-section").flatMap { name in SettingsSection.allCases.first { $0.rawValue.lowercased() == name.lowercased() } } ?? .terminal)
        _query = State(initialValue: value("--settings-query") ?? "")
    }

    private var searching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Sections that have a row matching the query.
    private var matchingSections: [SettingsSection] {
        SettingsSection.allCases.filter { section in
            switch section {
            case .ghostty, .advanced:
                return section.rawValue.localizedCaseInsensitiveContains(query)
                    || section.summary.localizedCaseInsensitiveContains(query)
            default:
                return SettingsSchema.specs(in: section).contains { $0.matches(query) }
            }
        }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.callout)
                    TextField("Search", text: $query).textFieldStyle(.plain)
                    if searching {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 7))
                .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 4)

                List(selection: $selection) {
                    ForEach(searching ? matchingSections : SettingsSection.allCases) { s in
                        Label(s.rawValue, systemImage: s.symbol).tag(s)
                    }
                    if searching && matchingSections.isEmpty {
                        Text("No matches").foregroundStyle(.secondary)
                    }
                }
                .listStyle(.sidebar)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            Group {
                if searching {
                    SearchResultsView(model: model, query: query, sections: matchingSections)
                } else if let selection {
                    SectionForm(model: model, section: selection)
                } else {
                    Text("Select a section").foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom) { footer }
        }
        .frame(minWidth: 680, minHeight: 440)
        .onChange(of: query) { _, _ in
            if searching, let selection, !matchingSections.contains(selection) { self.selection = matchingSections.first }
        }
    }

    private var runningProjects: [Project] { model.registry.projects.filter { model.isRunning($0) } }

    private var footer: some View {
        HStack(spacing: 10) {
            Text("Project apps read settings when they launch. Restart a project to apply a change.")
                .font(.callout).foregroundStyle(.secondary)
            Spacer()
            if let err = model.lastError {
                Text(err).font(.callout).foregroundStyle(.red).lineLimit(1).help(err)
                Button("Dismiss") { model.lastError = nil }.controlSize(.small)
            }
            Button("Restart Running Projects") { for p in runningProjects { model.restart(p) } }
                .disabled(runningProjects.isEmpty)
                .help("Quit, regenerate, and relaunch every running project app.")
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.bar)
    }
}

/// One section as a grouped form, the section summary as the footer of its
/// first group.
struct SectionForm: View {
    @ObservedObject var model: ProjectsModel
    let section: SettingsSection

    var body: some View {
        Form {
            switch section {
            case .ghostty:
                Section { GhosttyKeysEditor(model: model) } footer: { SectionFooter(section.summary) }
            case .advanced:
                AdvancedSettingsSections(model: model)
            default:
                Section {
                    ForEach(SettingsSchema.specs(in: section)) { SettingRow(model: model, spec: $0) }
                }
            }
        }
        .formStyle(.grouped)
        .settingsTitle(section.rawValue)
    }
}

/// Matching rows grouped under their section names.
struct SearchResultsView: View {
    @ObservedObject var model: ProjectsModel
    let query: String
    let sections: [SettingsSection]

    var body: some View {
        Form {
            if sections.isEmpty {
                Text("No settings match “\(query)”.").foregroundStyle(.secondary)
            }
            ForEach(sections) { section in
                Section(section.rawValue) {
                    switch section {
                    case .ghostty: GhosttyKeysEditor(model: model)
                    case .advanced: AdvancedSettingsSections(model: model, grouped: false)
                    default:
                        ForEach(SettingsSchema.specs(in: section).filter { $0.matches(query) }) { SettingRow(model: model, spec: $0) }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .settingsTitle("Search")
    }
}

/// Title and description on the left, the control on the right. A dot after
/// the title marks a value that differs from the default; hovering the row
/// shows Reset.
struct SettingRow: View {
    @ObservedObject var model: ProjectsModel
    let spec: SettingSpec
    @State private var hovering = false

    private var modified: Bool { spec.isModified(model.settings) }

    var body: some View {
        LabeledContent {
            HStack(spacing: 8) {
                if modified && hovering {
                    Button("Reset") { spec.reset(&model.settings); model.saveSettings() }
                        .controlSize(.small)
                        .help("Reset to the default")
                }
                control
            }
        } label: {
            HStack(spacing: 5) {
                Text(spec.title)
                if modified {
                    Circle().fill(Color.accentColor).frame(width: 6, height: 6)
                        .help("Differs from the default")
                }
            }
            Text(spec.description).font(.callout).foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    @ViewBuilder private var control: some View {
        switch spec.control {
        case .optionalText(let k, let placeholder):
            TextField("", text: Binding(
                get: { model.settings[keyPath: k] ?? "" },
                set: { model.settings[keyPath: k] = $0.isEmpty ? nil : $0 }), prompt: Text(placeholder))
            .labelsHidden().textFieldStyle(.roundedBorder).frame(width: 200)
            .onSubmit { model.saveSettings() }
        case .number(let k, let range, let step):
            TextField("", value: Binding(
                get: { Double(model.settings[keyPath: k]) },
                set: { model.settings[keyPath: k] = CGFloat(min(max($0, range.lowerBound), range.upperBound)) }),
                format: .number)
            .frame(width: 60).multilineTextAlignment(.trailing)
            .onSubmit { model.saveSettings() }
            Stepper("", value: Binding(
                get: { Double(model.settings[keyPath: k]) },
                set: { model.settings[keyPath: k] = CGFloat($0); model.saveSettings() }),
                in: range, step: step)
            .labelsHidden()
        case .integer(let k, let range):
            TextField("", value: Binding(
                get: { model.settings[keyPath: k] },
                set: { model.settings[keyPath: k] = min(max($0, range.lowerBound), range.upperBound) }),
                format: .number)
            .frame(width: 100).multilineTextAlignment(.trailing)
            .onSubmit { model.saveSettings() }
        case .choice(let k, let options):
            Picker("", selection: Binding(
                get: { model.settings[keyPath: k] },
                set: { model.settings[keyPath: k] = $0; model.saveSettings() })) {
                ForEach(options, id: \.value) { Text($0.label).tag($0.value) }
            }
            .labelsHidden().frame(width: 200)
        }
    }
}

extension View {
    /// "Spacedock Settings", centered in the unified title bar. One row, no
    /// section name, no profile suffix.
    func settingsTitle(_ subtitle: String) -> some View {
        toolbar {
            ToolbarItem(placement: .principal) {
                Text("Spacedock Settings").font(.title3.weight(.semibold))
            }
        }
    }
}

/// Grouped-form footers default to trailing alignment; settings read better leading.
struct SectionFooter: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.callout).foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Ghostty keys

/// A key/value table of raw Ghostty keys with add and remove buttons under
/// it. Each cell commits on submit or focus loss; a row with an empty key is
/// kept in the table and never written.
struct GhosttyKeysEditor: View {
    @ObservedObject var model: ProjectsModel

    struct Entry: Identifiable, Equatable {
        let id: UUID
        var key: String
        var value: String
    }

    @State private var entries: [Entry] = []
    @State private var selected: Entry.ID?
    @FocusState private var focused: UUID?

    private func load() {
        entries = model.settings.ghostty.sorted { $0.key < $1.key }.map { Entry(id: UUID(), key: $0.key, value: $0.value) }
    }

    private var asMap: [String: String] {
        Dictionary(entries.compactMap { e -> (String, String)? in
            let k = e.key.trimmingCharacters(in: .whitespaces)
            return k.isEmpty ? nil : (k, e.value.trimmingCharacters(in: .whitespaces))
        }) { _, last in last }   // repeated key: last row wins, as in Ghostty's own config
    }

    private func commit() {
        let map = asMap
        guard map != model.settings.ghostty else { return }
        model.settings.ghostty = map
        model.saveSettings()
    }

    private var duplicateKeys: Set<String> {
        var seen: Set<String> = [], dup: Set<String> = []
        for e in entries {
            let k = e.key.trimmingCharacters(in: .whitespaces)
            if !k.isEmpty, !seen.insert(k).inserted { dup.insert(k) }
        }
        return dup
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Table($entries, selection: $selected) {
                TableColumn("Key") { $entry in
                    HStack(spacing: 4) {
                        TextField("", text: $entry.key, prompt: Text("key"))
                            .labelsHidden().font(.body.monospaced())
                            .focused($focused, equals: entry.id)
                            .onSubmit(commit)
                        if duplicateKeys.contains(entry.key.trimmingCharacters(in: .whitespaces)) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                                .help("Repeated key: the last row wins.")
                        }
                    }
                }
                .width(min: 140, ideal: 200)
                TableColumn("Value") { $entry in
                    TextField("", text: $entry.value, prompt: Text("value"))
                        .labelsHidden().font(.body.monospaced()).onSubmit(commit)
                }
            }
            .frame(minHeight: 160)
            HStack(spacing: 0) {
                Button {
                    let e = Entry(id: UUID(), key: "", value: "")
                    entries.append(e)
                    selected = e.id
                    focused = e.id
                } label: { Image(systemName: "plus").frame(width: 20, height: 18) }
                .help("Add an option")
                Divider().frame(height: 14)
                Button {
                    entries.removeAll { $0.id == selected }
                    selected = nil
                    commit()
                } label: { Image(systemName: "minus").frame(width: 20, height: 18) }
                .disabled(selected == nil)
                .help("Remove the selected option")
                Spacer()
                Link("Config reference", destination: URL(string: "https://ghostty.org/docs/config/reference")!)
                    .font(.callout).padding(.trailing, 6)
            }
            .buttonStyle(.borderless)
            .padding(.vertical, 2)
        }
        .onAppear(perform: load)
        .onChange(of: focused) { _, _ in commit() }
        .onChange(of: model.settings.ghostty) { _, new in
            if asMap != new { load() }   // changed underneath us (Reload, Reset All), not by our own commit
        }
    }
}

// MARK: - Advanced

struct AdvancedSettingsSections: View {
    @ObservedObject var model: ProjectsModel
    var grouped = true

    private var path: String { Settings.fileURL.path.replacingOccurrences(of: NSHomeDirectory(), with: "~") }

    var body: some View {
        if grouped {
            Section {
                fileRows
            } header: { Text("Settings file") } footer: {
                SectionFooter("Every setting in this window is a key in this file. The CLI's `set --global` writes the same file.")
            }
            Section {
                resetRow
            } footer: {
                SectionFooter("Per-project overrides are not touched.")
            }
        } else {
            fileRows
            resetRow
        }
    }

    @ViewBuilder private var fileRows: some View {
        LabeledContent {
            HStack {
                Button("Open in Editor") {
                    try? model.settings.writeIfMissing()
                    NSWorkspace.shared.open(Settings.fileURL)
                }
                Button("Reveal in Finder") {
                    try? model.settings.writeIfMissing()
                    NSWorkspace.shared.activateFileViewerSelecting([Settings.fileURL])
                }
            }
        } label: {
            Text("Location")
            Text(path).font(.callout.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
        }
        LabeledContent {
            Button("Reload") { model.settings = Settings.load() }
        } label: {
            Text("Reload from disk")
            Text("Discard uncommitted edits in this window and reread the file.").font(.callout).foregroundStyle(.secondary)
        }
    }

    private var resetRow: some View {
        LabeledContent {
            Button("Reset All…", role: .destructive) {
                let alert = NSAlert()
                alert.messageText = "Reset all settings to their defaults?"
                alert.informativeText = "Every value in this window, including Ghostty options, returns to its default."
                alert.addButton(withTitle: "Reset All")
                alert.addButton(withTitle: "Cancel")
                if alert.runModal() == .alertFirstButtonReturn {
                    model.settings = Settings()
                    model.saveSettings()
                }
            }
        } label: {
            Text("Reset everything")
            Text("Return every global setting to its default.").font(.callout).foregroundStyle(.secondary)
        }
    }
}
