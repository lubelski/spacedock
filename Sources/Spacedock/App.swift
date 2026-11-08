import AppKit
import SwiftTerm

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let project: Project
    let settings: Settings
    var windows: [NSWindow] = []
    var terminals: [any TerminalPane] = []
    private var sigterm: DispatchSourceSignal?
    private var quitting = false

    init(project: Project, settings: Settings) {
        self.project = project
        self.settings = settings
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        installMenu()
        installSignalHandlers()
        openTerminalWindow()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // MARK: Quit

    /// `kill <pid>` and `launchctl` send SIGTERM. Route it through the normal
    /// quit path so shells get a chance to exit.
    ///
    /// `terminate` is called from a run loop block, not from inside the
    /// dispatch handler. `applicationShouldTerminate` answers `terminateLater`,
    /// which spins a nested run loop, and that loop cannot drain the main
    /// dispatch queue while a main-queue block is already on the stack. The
    /// deadline timer and SwiftTerm's exit callbacks both arrive on the main
    /// queue, so calling `terminate` from inside the handler hangs the quit.
    private func installSignalHandlers() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler {
            RunLoop.main.perform { NSApp.terminate(nil) }
        }
        source.resume()
        sigterm = source
    }

    /// Cmd-Q, the `quit` Apple event, and SIGTERM all arrive here. Send
    /// SIGHUP to every shell, as a closing terminal does (interactive zsh
    /// ignores SIGTERM but exits on SIGHUP), then finish once they have all
    /// exited or after a short deadline.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let live = terminals.filter { $0.isShellRunning }
        if live.isEmpty { return .terminateNow }
        quitting = true
        for t in live { t.hangUp() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.quitting else { return }
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    // MARK: Windows

    @objc func openTerminalWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = project.name
        window.subtitle = project.folderURL.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("terminal-\(windows.count)")

        // Tint: the title bar carries the project color. The terminal below
        // keeps a dark, slightly tinted background so text stays readable.
        let background = project.color.blended(withFraction: 0.88, of: .black) ?? .black
        window.titlebarAppearsTransparent = true
        window.backgroundColor = project.color
        window.appearance = NSAppearance(named: project.color.luminance > 0.6 ? .aqua : .darkAqua)

        // Padding: a container in the terminal background color, with the
        // terminal inset by `settings.padding` on every side. Ghostty pads
        // inside its own surface, so that pane fills the container.
        let container = NSView(frame: window.contentView!.bounds)
        container.wantsLayer = true
        container.layer?.backgroundColor = background.cgColor

        let inset: CGFloat = settings.emulator.lowercased() == "ghostty" ? 0 : settings.padding
        let terminal = PaneFactory.make(settings: settings, project: project, background: background,
                                        frame: container.bounds.insetBy(dx: inset, dy: inset))
        terminal.autoresizingMask = [.width, .height]
        terminal.onTitle = { [weak window] title in
            if !title.isEmpty { window?.subtitle = title }
        }
        terminal.onDirectory = { [weak window] path in
            window?.subtitle = path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        }
        terminal.onShellExit = { [weak self, weak terminal] in
            guard let self, let terminal else { return }
            self.shellExited(terminal)
        }
        container.addSubview(terminal)

        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        terminal.start(shell: shell, directory: project.folderURL.path,
                       env: ["SPACEDOCK_PROJECT": project.name, "SPACEDOCK_SLUG": project.slug])

        window.contentView = container
        window.makeFirstResponder(terminal)
        if let last = windows.last {
            window.setFrameTopLeftPoint(last.cascadeTopLeft(from: .zero))
        } else {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        windows.append(window)
        terminals.append(terminal)
    }

    func windowWillClose(_ notification: Notification) {
        guard let w = notification.object as? NSWindow else { return }
        if let t = terminals.first(where: { $0.window === w }) {
            if t.isShellRunning { t.hangUp() }
            terminals.removeAll { $0 === t }
        }
        windows.removeAll { $0 === w }
    }

    /// A shell that exits closes its window. During quit, the last shell to
    /// exit lets the app finish terminating.
    func shellExited(_ t: any TerminalPane) {
        terminals.removeAll { $0 === t }
        if quitting {
            if terminals.allSatisfy({ !$0.isShellRunning }) {
                quitting = false
                NSApp.reply(toApplicationShouldTerminate: true)
            }
        } else {
            t.window?.close()
        }
    }

    // MARK: Menu

    func installMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About \(project.name)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide \(project.name)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit \(project.name)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let shellItem = NSMenuItem()
        let shellMenu = NSMenu(title: "Shell")
        shellMenu.addItem(withTitle: "New Terminal Window", action: #selector(openTerminalWindow), keyEquivalent: "n")
        shellMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        shellItem.submenu = shellMenu
        main.addItem(shellItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = main
    }
}
