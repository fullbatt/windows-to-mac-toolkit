import AppKit
import ApplicationServices

final class PhysicalKeyListener {
    private var tap: CFMachPort?

    func run() {
        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.keyUp.rawValue)
            | (CGEventMask(1) << 14)

        tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: listenerCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let tap else {
            print("Could not create event tap. Give Terminal/Codex Accessibility permission and try again.")
            exit(2)
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        print("Listening for 12 seconds. Press the physical fast-forward/F9 key now.")
        fflush(stdout)

        DispatchQueue.main.asyncAfter(deadline: .now() + 12) {
            print("Done listening.")
            exit(0)
        }

        CFRunLoopRun()
    }

    func handle(type: CGEventType, event: CGEvent) {
        if type == .keyDown || type == .keyUp {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let direction = type == .keyDown ? "down" : "up"
            print("keyboard \(direction): keyCode=\(keyCode) flags=\(event.flags.rawValue)")
            fflush(stdout)
            return
        }

        if type.rawValue == 14, let nsEvent = NSEvent(cgEvent: event) {
            let key = (nsEvent.data1 >> 16) & 0xffff
            let state = (nsEvent.data1 >> 8) & 0xff
            let direction = state == 0xA ? "down" : state == 0xB ? "up" : "state-\(state)"
            print("system media \(direction): keyType=\(key) data1=\(nsEvent.data1) flags=\(event.flags.rawValue)")
            fflush(stdout)
        }
    }
}

private func listenerCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    info: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if let info {
        let listener = Unmanaged<PhysicalKeyListener>.fromOpaque(info).takeUnretainedValue()
        listener.handle(type: type, event: event)
    }
    return Unmanaged.passUnretained(event)
}

PhysicalKeyListener().run()
