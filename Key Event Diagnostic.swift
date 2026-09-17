import AppKit
import ApplicationServices

final class Diagnostic {
    var sawF9 = false
    var sawCommandBackspace = false
    var tap: CFMachPort?

    func run() {
        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.keyUp.rawValue)
            | (CGEventMask(1) << 14)

        tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: diagnosticCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let tap else {
            print("Could not create diagnostic event tap. Check Accessibility permission for Terminal/Codex.")
            exit(2)
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.postF9()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            print("saw_f9=\(self.sawF9)")
            print("saw_command_backspace=\(self.sawCommandBackspace)")
            exit(self.sawCommandBackspace ? 0 : 1)
        }

        CFRunLoopRun()
    }

    private func postF9() {
        CGEvent(keyboardEventSource: nil, virtualKey: 101, keyDown: true)?.post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: nil, virtualKey: 101, keyDown: false)?.post(tap: .cghidEventTap)
    }

    func handle(type: CGEventType, event: CGEvent) {
        guard type == .keyDown || type == .keyUp else { return }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        if keyCode == 101 {
            sawF9 = true
        }

        if keyCode == 51 && event.flags.contains(.maskCommand) {
            sawCommandBackspace = true
        }
    }
}

private func diagnosticCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    info: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if let info {
        let diagnostic = Unmanaged<Diagnostic>.fromOpaque(info).takeUnretainedValue()
        diagnostic.handle(type: type, event: event)
    }
    return Unmanaged.passUnretained(event)
}

Diagnostic().run()
