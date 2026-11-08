import AppKit
import SwiftTerm

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let project: Project
    var windows: [NSWindow] = []

    init(project: Project) {
        self.project = project
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        installMenu()
        openTerminalWindow()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

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
        window.titlebarAppearsTransparent = true
        window.backgroundColor = project.color
        window.appearance = NSAppearance(named: project.color.luminance > 0.6 ? .aqua : .darkAqua)

        let terminal = LocalProcessTerminalView(frame: window.contentView!.bounds)
        terminal.autoresizingMask = [.width, .height]
        terminal.nativeBackgroundColor = project.color.blended(withFraction: 0.88, of: .black) ?? .black
        terminal.nativeForegroundColor = .white
        terminal.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        var env = Terminal.getEnvironmentVariables(termName: "xterm-256color")
        env.append("PROJECT_SHELL_NAME=\(project.name)")
        env.append("PROJECT_SHELL_SLUG=\(project.slug)")
        terminal.startProcess(executable: shell, args: ["-l"], environment: env,
                              execName: "-" + (shell as NSString).lastPathComponent,
                              currentDirectory: project.folderURL.path)

        window.contentView = terminal
        window.makeFirstResponder(terminal)
        if let last = windows.last {
            window.setFrameTopLeftPoint(last.cascadeTopLeft(from: .zero))
        } else {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        windows.append(window)
    }

    func windowWillClose(_ notification: Notification) {
        guard let w = notification.object as? NSWindow else { return }
        windows.removeAll { $0 === w }
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
