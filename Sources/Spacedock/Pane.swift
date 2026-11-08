import AppKit
import SwiftTerm
import GhosttyTerminal

/// One terminal inside a window, independent of the emulator behind it. The
/// window layer (tint, padding, menu, quit) talks only to this.
@MainActor
protocol TerminalPane: NSView {
    /// Starts a login shell in `directory`. `env` entries are KEY=VALUE.
    func start(shell: String, directory: String, env: [String: String])
    /// True while the shell is alive.
    var isShellRunning: Bool { get }
    /// Asks the shell to exit the way a closing terminal does (SIGHUP).
    func hangUp()
    var onShellExit: (() -> Void)? { get set }
    var onTitle: ((String) -> Void)? { get set }
    var onDirectory: ((String) -> Void)? { get set }
    /// A window-level request from the emulator's own keybindings: new
    /// window, close, quit, fullscreen. Ghostty emits these for Cmd-N,
    /// Cmd-Shift-W, Cmd-Q and friends; SwiftTerm never does.
    var onWindowRequest: ((WindowRequest) -> Void)? { get set }
    /// Asks the emulator to run one of its own binding actions by name
    /// (Ghostty: `new_window`, `quit`, `copy_to_clipboard`, ...). Returns
    /// false when the emulator has no such action. Used by the
    /// `--binding-action` debug argument so agents can drive keybinding
    /// paths without a keyboard.
    func runBindingAction(_ name: String) -> Bool
}

enum WindowRequest {
    case newWindow
    case closeWindow
    case quit
    case toggleFullscreen
    /// Tabs and splits do not exist yet; the window layer decides what to do.
    case newTab
    case newSplit
}

enum PaneFactory {
    @MainActor
    static func make(settings: Settings, project: Project, background: NSColor, frame: NSRect) -> any TerminalPane {
        switch settings.emulator.lowercased() {
        case "ghostty": return GhosttyPane(frame: frame, settings: settings, project: project, background: background)
        default: return SwiftTermPane(frame: frame, settings: settings, background: background)
        }
    }
}

// MARK: - SwiftTerm

/// Wraps `LocalProcessTerminalView` rather than subclassing it: the view is
/// its own delegate for some callbacks, so a subclass cannot adopt the
/// delegate protocol without colliding with non-open methods.
final class SwiftTermPane: NSView, TerminalPane, LocalProcessTerminalViewDelegate {
    var onShellExit: (() -> Void)?
    var onTitle: ((String) -> Void)?
    var onDirectory: ((String) -> Void)?
    var onWindowRequest: ((WindowRequest) -> Void)?
    let inner: LocalProcessTerminalView

    func runBindingAction(_ name: String) -> Bool { false }

    init(frame: NSRect, settings: Settings, background: NSColor) {
        inner = LocalProcessTerminalView(frame: NSRect(origin: .zero, size: frame.size),
                                         font: settings.font, options: settings.terminalOptions)
        super.init(frame: frame)
        inner.autoresizingMask = [.width, .height]
        inner.nativeBackgroundColor = background
        inner.nativeForegroundColor = .white
        inner.processDelegate = self
        addSubview(inner)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool {
        window?.makeFirstResponder(inner) ?? false
    }

    func start(shell: String, directory: String, env: [String: String]) {
        var vars = Terminal.getEnvironmentVariables(termName: "xterm-256color")
        vars.append(contentsOf: env.map { "\($0.key)=\($0.value)" })
        inner.startProcess(executable: shell, args: ["-l"], environment: vars,
                           execName: "-" + (shell as NSString).lastPathComponent,
                           currentDirectory: directory)
    }

    var isShellRunning: Bool { inner.process.running }

    func hangUp() {
        if inner.process.running { kill(inner.process.shellPid, SIGHUP) }
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) { onTitle?(title) }
    func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) {
        guard let directory, let url = URL(string: directory) else { return }
        onDirectory?(url.path)
    }
    func processTerminated(source: SwiftTerm.TerminalView, exitCode: Int32?) { onShellExit?() }
}

// MARK: - libghostty (Lakr233/libghostty-spm, GhosttyTerminal)

/// The exec backend owns the pty. Closing the surface closes the pty, which
/// hangs up the shell, so there is no pid to signal from here.
final class GhosttyPane: AppTerminalView, TerminalPane,
                         TerminalSurfaceTitleDelegate, TerminalSurfacePwdDelegate, TerminalSurfaceCloseDelegate,
                         TerminalSurfaceWindowActionDelegate {
    var onShellExit: (() -> Void)?
    var onTitle: ((String) -> Void)?
    var onDirectory: ((String) -> Void)?
    var onWindowRequest: ((WindowRequest) -> Void)?
    private var shellAlive = false
    private let ghosttyController: TerminalController

    init(frame: NSRect, settings: Settings, project: Project, background: NSColor) {
        let cursor: TerminalCursorStyle
        let blink: Bool
        switch settings.terminalCursorStyle {
        case .blinkBlock: cursor = .block; blink = true
        case .steadyBlock: cursor = .block; blink = false
        case .blinkUnderline: cursor = .underline; blink = true
        case .steadyUnderline: cursor = .underline; blink = false
        case .blinkBar: cursor = .bar; blink = true
        case .steadyBar: cursor = .bar; blink = false
        }
        ghosttyController = TerminalController { b in
            b.withBackground(background.hexString)
            b.withForeground("#FFFFFF")
            b.withCursorStyle(cursor)
            b.withCursorStyleBlink(blink)
            b.withFontSize(Float(settings.fontSize))
            if let name = settings.fontName { b.withFontFamily(name) }
            // Ghostty pads inside the surface; the window layer adds none for this pane.
            b.withWindowPaddingX(Int(settings.padding))
            b.withWindowPaddingY(Int(settings.padding))
            // Ghostty's scrollback is sized in bytes. ~200 bytes per line is generous.
            b.withCustom("scrollback-limit", String(settings.scrollback * 200))
            // Raw keys last, so a project can override anything above.
            for (key, value) in settings.ghostty.sorted(by: { $0.key < $1.key }) {
                b.withCustom(key, value)
            }
        }
        super.init(frame: frame)
        delegate = self
        controller = ghosttyController
        // quit and close_all_windows are addressed to the app, not the surface.
        ghosttyController.windowActionDelegate = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func start(shell: String, directory: String, env: [String: String]) {
        configuration = TerminalSurfaceOptions(backend: .exec,
                                               workingDirectory: directory,
                                               envVars: env,
                                               command: shell)
        shellAlive = true
    }

    var isShellRunning: Bool { shellAlive }

    /// Dropping the controller tears the surface down, which frees the pty
    /// and hangs up the shell. Removing the view alone does not: the package
    /// keeps the surface across detach and reattach.
    func hangUp() {
        shellAlive = false
        controller = nil
    }

    func terminalDidChangeTitle(_ title: String) { onTitle?(title) }
    func terminalDidChangeWorkingDirectory(_ path: String) { onDirectory?(path) }

    func runBindingAction(_ name: String) -> Bool { performBindingAction(name) }

    /// Ghostty's keybindings are the authority for shortcuts. The pane
    /// forwards what it cannot do itself.
    func terminalDidRequestWindowAction(_ action: TerminalWindowAction) {
        switch action {
        case .newWindow: onWindowRequest?(.newWindow)
        case .newTab: onWindowRequest?(.newTab)
        case .newSplit: onWindowRequest?(.newSplit)
        case .closeWindow, .closeTab: onWindowRequest?(.closeWindow)
        case .closeAllWindows, .quit: onWindowRequest?(.quit)
        case .toggleFullscreen, .toggleMaximize: onWindowRequest?(.toggleFullscreen)
        }
    }
    func terminalDidClose(processAlive: Bool) {
        shellAlive = false
        onShellExit?()
    }
}
