import AppKit

/// The project window's title bar: a unified toolbar (the tall title bar)
/// with the terminal title centered and the project name in a badge of the
/// project color at the trailing edge. The bar itself keeps the system
/// window color.
@MainActor
final class ProjectTitleBar: NSObject, NSToolbarDelegate {
    private static let titleID = NSToolbarItem.Identifier("title")
    private static let badgeID = NSToolbarItem.Identifier("badge")

    private let project: Project
    private let titleLabel = NSTextField(labelWithString: "")
    let toolbar: NSToolbar

    init(project: Project) {
        self.project = project
        toolbar = NSToolbar(identifier: "project-window")
        super.init()
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.centeredItemIdentifiers = [Self.titleID]
        titleLabel.font = .titleBarFont(ofSize: NSFont.systemFontSize)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.alignment = .center
        setTitle("")
    }

    /// Install on `window`. AppKit's own leading title is hidden; the
    /// window keeps its `title` for the Window menu and Mission Control.
    func install(on window: NSWindow) {
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        window.titleVisibility = .hidden
        window.title = titleLabel.stringValue
    }

    /// The terminal's title, or the project name when the terminal has
    /// not set one.
    func setTitle(_ title: String) {
        let shown = title.isEmpty ? project.displayName : title
        titleLabel.stringValue = shown
        titleLabel.toolTip = shown
        titleLabel.window?.title = shown
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, Self.titleID, .flexibleSpace, Self.badgeID]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: id)
        switch id {
        case Self.titleID:
            titleLabel.translatesAutoresizingMaskIntoConstraints = false
            titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            titleLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 520).isActive = true
            item.view = titleLabel
            item.visibilityPriority = .high
        case Self.badgeID:
            item.view = BadgeView(text: project.displayName, color: project.color)
            item.visibilityPriority = .user
        default:
            return nil
        }
        return item
    }
}

/// A rounded pill in the project color holding the project name.
final class BadgeView: NSView {
    private let label: NSTextField

    init(text: String, color: NSColor) {
        label = NSTextField(labelWithString: text)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = color.cgColor
        layer?.cornerRadius = 6
        layer?.cornerCurve = .continuous
        label.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        label.textColor = color.luminance > 0.6 ? .black : .white
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}
