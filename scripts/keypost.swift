// Posts one key press to a process by pid, no Accessibility permission needed.
// The target must be the frontmost app: AppKit routes key events to the key
// window, and a background app has none. Build: swiftc -O scripts/keypost.swift -o /tmp/keypost
// Key codes: n=45 w=13 q=12 t=17 d=2 c=8 v=9. Example: /tmp/keypost PID 45 cmd

import CoreGraphics
import Foundation
// usage: keypost PID KEYCODE [cmd] [shift]
let args = CommandLine.arguments
guard args.count >= 3, let pid = pid_t(args[1]), let code = UInt16(args[2]) else { print("usage: keypost PID KEYCODE [cmd] [shift]"); exit(64) }
var flags: CGEventFlags = []
if args.contains("cmd") { flags.insert(.maskCommand) }
if args.contains("shift") { flags.insert(.maskShift) }
guard let down = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true),
      let up = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false) else { print("no event"); exit(1) }
down.flags = flags; up.flags = flags
down.postToPid(pid); usleep(30_000); up.postToPid(pid)
print("posted key \(code) flags \(flags.rawValue) to \(pid)")
