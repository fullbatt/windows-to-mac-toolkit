import AppKit
import ApplicationServices

enum KeyAction: String, CaseIterable {
    case none
    case delete
    case home
    case end
    case custom

    var title: String {
        switch self {
        case .none: return "None"
        case .delete: return "Delete"
        case .home: return "Home"
        case .end: return "End"
        case .custom: return "Custom Shortcut"
        }
    }

    var output: (keyCode: CGKeyCode, flags: CGEventFlags) {
        switch self {
        case .none: return (0, [])
        case .delete: return (51, .maskCommand)
        case .home: return (123, .maskCommand)
        case .end: return (124, .maskCommand)
        case .custom: return (0, [])
        }
    }
}

struct FunctionKey: CaseIterable {
    let title: String
    let macFunctionTitle: String
    let symbolName: String
    let keyCode: CGKeyCode
    let mediaKeyTypes: Set<Int>

    static let allCases: [FunctionKey] = [
        FunctionKey(title: "F1", macFunctionTitle: "Brightness Down", symbolName: "sun.min", keyCode: 122, mediaKeyTypes: [0]),
        FunctionKey(title: "F2", macFunctionTitle: "Brightness Up", symbolName: "sun.max", keyCode: 120, mediaKeyTypes: [1]),
        FunctionKey(title: "F3", macFunctionTitle: "Mission Control", symbolName: "rectangle.3.group", keyCode: 99, mediaKeyTypes: [160]),
        FunctionKey(title: "F4", macFunctionTitle: "Spotlight", symbolName: "magnifyingglass", keyCode: 118, mediaKeyTypes: [131]),
        FunctionKey(title: "F5", macFunctionTitle: "Dictation", symbolName: "mic", keyCode: 96, mediaKeyTypes: [20]),
        FunctionKey(title: "F6", macFunctionTitle: "Do Not Disturb", symbolName: "moon", keyCode: 97, mediaKeyTypes: [21]),
        FunctionKey(title: "F7", macFunctionTitle: "Rewind", symbolName: "backward.fill", keyCode: 98, mediaKeyTypes: [16]),
        FunctionKey(title: "F8", macFunctionTitle: "Play/Pause", symbolName: "playpause.fill", keyCode: 100, mediaKeyTypes: []),
        FunctionKey(title: "F9", macFunctionTitle: "Fast Forward", symbolName: "forward.fill", keyCode: 101, mediaKeyTypes: [17, 19]),
        FunctionKey(title: "F10", macFunctionTitle: "Mute", symbolName: "speaker.slash.fill", keyCode: 109, mediaKeyTypes: [7]),
        FunctionKey(title: "F11", macFunctionTitle: "Volume Down", symbolName: "speaker.wave.1.fill", keyCode: 103, mediaKeyTypes: [8]),
        FunctionKey(title: "F12", macFunctionTitle: "Volume Up", symbolName: "speaker.wave.3.fill", keyCode: 111, mediaKeyTypes: [9])
    ]

    var defaultsKey: String { "mapping.\(title.lowercased())" }
    var shortcutDefaultsKey: String { "shortcut.\(title.lowercased())" }
}

struct ShortcutMapping {
    let keyCode: CGKeyCode
    let name: String
}

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

final class MapperApp: NSObject, NSApplicationDelegate {
    static let eventMarker: Int64 = 0xF12D_EE1
    static var shared: MapperApp?
    private static let preferencesDomain = "com.andre.fkeymapper" as CFString

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var tap: CFMachPort?
    private var settingsWindow: NSWindow?
    private var popupButtons: [String: NSPopUpButton] = [:]
    private var shortcutControls: [String: NSButton] = [:]
    private var recordingShortcutKey: String?
    private var shortcutRecorderMonitor: Any?
    private let windowsShortcutMappings: [ShortcutMapping] = [
        ShortcutMapping(keyCode: 0, name: "Ctrl-A -> Command-A"),
        ShortcutMapping(keyCode: 8, name: "Ctrl-C -> Command-C"),
        ShortcutMapping(keyCode: 3, name: "Ctrl-F -> Command-F"),
        ShortcutMapping(keyCode: 1, name: "Ctrl-S -> Command-S"),
        ShortcutMapping(keyCode: 9, name: "Ctrl-V -> Command-V"),
        ShortcutMapping(keyCode: 7, name: "Ctrl-X -> Command-X"),
        ShortcutMapping(keyCode: 6, name: "Ctrl-Z -> Command-Z")
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        MapperApp.shared = self
        NSApplication.shared.setActivationPolicy(.accessory)
        registerDefaults()
        configureStatusMenu()
        requestAccessibilityPermission()
        startTap()
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.startTap() }
    }

    private func registerDefaults() {
        for key in FunctionKey.allCases {
            registerStringDefault(KeyAction.none.rawValue, for: key.defaultsKey)
            registerStringDefault("", for: key.shortcutDefaultsKey)
        }
        registerStringDefault("false", for: "module.windowsShortcuts.enabled")
        registerStringDefault("true", for: "module.finderFixes.enabled")
        registerStringDefault("true", for: "finder.enterOpens")
        registerStringDefault("true", for: "finder.f2Renames")
        registerStringDefault("true", for: "finder.deleteTrashes")
    }

    private func configureStatusMenu() {
        statusItem.button?.title = "Win->Mac"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Accessibility Settings...", action: #selector(openAccessibilitySettings), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func startTap() {
        guard tap == nil, AXIsProcessTrusted() else { return }

        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.keyUp.rawValue)
            | (CGEventMask(1) << 14)

        tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: eventCallback,
            userInfo: nil
        )

        guard let tap else { return }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        NSLog("Windows to Mac Toolkit: keyboard mapping active")
    }

    func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        if event.getIntegerValueField(.eventSourceUserData) == MapperApp.eventMarker {
            return Unmanaged.passUnretained(event)
        }

        if let input = functionKeyEvent(type: type, event: event),
           let action = action(for: input.key),
           action != .none {
            if input.keyDown {
                NSLog("Windows to Mac Toolkit: %@ -> %@", input.key.title, action.title)
            }
            if action == .custom {
                postCustomShortcut(for: input.key, keyDown: input.keyDown)
            } else {
                post(action: action, keyDown: input.keyDown)
            }
            return nil
        }

        if handleWindowsShortcut(type: type, event: event) { return nil }
        if handleFinderFix(type: type, event: event) { return nil }

        return Unmanaged.passUnretained(event)
    }

    private func handleWindowsShortcut(type: CGEventType, event: CGEvent) -> Bool {
        guard boolPreference(for: "module.windowsShortcuts.enabled"),
              type == .keyDown || type == .keyUp else { return false }

        let flags = event.flags
        guard flags.contains(.maskControl),
              !flags.contains(.maskCommand),
              !flags.contains(.maskAlternate) else { return false }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        guard let mapping = windowsShortcutMappings.first(where: { $0.keyCode == keyCode }) else {
            return false
        }

        if type == .keyDown {
            NSLog("Windows to Mac Toolkit: %@", mapping.name)
        }
        post(keyCode: keyCode, flags: flagsWithoutControl(flags).union(.maskCommand), keyDown: type == .keyDown)
        return true
    }

    private func handleFinderFix(type: CGEventType, event: CGEvent) -> Bool {
        guard boolPreference(for: "module.finderFixes.enabled"),
              type == .keyDown || type == .keyUp,
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder" else {
            return false
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let keyDown = type == .keyDown

        if keyCode == 36, boolPreference(for: "finder.enterOpens") {
            if keyDown { NSLog("Windows to Mac Toolkit: Finder Enter -> Command-O") }
            post(keyCode: 31, flags: .maskCommand, keyDown: keyDown)
            return true
        }

        if keyCode == 120, boolPreference(for: "finder.f2Renames") {
            if keyDown { NSLog("Windows to Mac Toolkit: Finder F2 -> Return") }
            post(keyCode: 36, flags: [], keyDown: keyDown)
            return true
        }

        if keyCode == 117, boolPreference(for: "finder.deleteTrashes") {
            if keyDown { NSLog("Windows to Mac Toolkit: Finder Forward Delete -> Command-Backspace") }
            post(keyCode: 51, flags: .maskCommand, keyDown: keyDown)
            return true
        }

        return false
    }

    private func functionKeyEvent(type: CGEventType, event: CGEvent) -> (key: FunctionKey, keyDown: Bool)? {
        if type == .keyDown || type == .keyUp {
            let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            if let key = FunctionKey.allCases.first(where: { $0.keyCode == keyCode }) {
                return (key, type == .keyDown)
            }
        }

        guard type.rawValue == 14,
              let nsEvent = NSEvent(cgEvent: event),
              nsEvent.subtype.rawValue == 8 else { return nil }

        let mediaKeyType = (nsEvent.data1 >> 16) & 0xffff
        let mediaKeyState = (nsEvent.data1 >> 8) & 0xff
        guard mediaKeyState == 0xA || mediaKeyState == 0xB,
              let key = FunctionKey.allCases.first(where: { $0.mediaKeyTypes.contains(mediaKeyType) }) else {
            return nil
        }

        return (key, mediaKeyState == 0xA)
    }

    private func action(for key: FunctionKey) -> KeyAction? {
        KeyAction(rawValue: preferenceString(for: key.defaultsKey) ?? KeyAction.none.rawValue)
    }

    private func flagsWithoutControl(_ flags: CGEventFlags) -> CGEventFlags {
        CGEventFlags(rawValue: flags.rawValue & ~CGEventFlags.maskControl.rawValue)
    }

    private func post(action: KeyAction, keyDown: Bool) {
        let output = action.output
        guard action != .none && action != .custom else { return }
        post(keyCode: output.keyCode, flags: output.flags, keyDown: keyDown)
    }

    private func postCustomShortcut(for key: FunctionKey, keyDown: Bool) {
        let shortcut = preferenceString(for: key.shortcutDefaultsKey) ?? ""
        guard let parsed = parseShortcut(shortcut) else {
            if keyDown {
                NSLog("Windows to Mac Toolkit: ignored invalid shortcut '%@' for %@", shortcut, key.title)
            }
            return
        }
        post(keyCode: parsed.keyCode, flags: parsed.flags, keyDown: keyDown)
    }

    private func parseShortcut(_ shortcut: String) -> (keyCode: CGKeyCode, flags: CGEventFlags)? {
        let pieces = shortcut
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "⌘", with: "cmd")
            .replacingOccurrences(of: "⌥", with: "option")
            .replacingOccurrences(of: "⌃", with: "ctrl")
            .replacingOccurrences(of: "⇧", with: "shift")
            .split(separator: "+")
            .map(String.init)

        guard let keyName = pieces.last else { return nil }

        var flags: CGEventFlags = []
        for modifier in pieces.dropLast() {
            switch modifier {
            case "cmd", "command", "win", "windows": flags.insert(.maskCommand)
            case "ctrl", "control": flags.insert(.maskControl)
            case "alt", "option", "opt": flags.insert(.maskAlternate)
            case "shift": flags.insert(.maskShift)
            default: return nil
            }
        }

        guard let keyCode = keyCode(for: keyName) else { return nil }
        return (keyCode, flags)
    }

    private func keyCode(for keyName: String) -> CGKeyCode? {
        let keyCodes: [String: CGKeyCode] = [
            "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7,
            "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
            "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22,
            "5": 23, "equal": 24, "=": 24, "9": 25, "7": 26, "minus": 27,
            "-": 27, "8": 28, "0": 29, "rightbracket": 30, "]": 30, "o": 31,
            "u": 32, "leftbracket": 33, "[": 33, "i": 34, "p": 35, "return": 36,
            "enter": 36, "l": 37, "j": 38, "quote": 39, "'": 39, "k": 40,
            "semicolon": 41, ";": 41, "backslash": 42, "\\": 42, "comma": 43,
            ",": 43, "slash": 44, "/": 44, "n": 45, "m": 46, "period": 47,
            ".": 47, "tab": 48, "space": 49, "grave": 50, "`": 50, "backspace": 51,
            "delete": 51, "escape": 53, "esc": 53, "left": 123, "leftarrow": 123,
            "right": 124, "rightarrow": 124, "down": 125, "downarrow": 125,
            "up": 126, "uparrow": 126
        ]
        return keyCodes[keyName]
    }

    private func post(keyCode: CGKeyCode, flags: CGEventFlags, keyDown: Bool) {
        guard let replacement = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: keyDown) else { return }
        replacement.flags = flags
        replacement.setIntegerValueField(.eventSourceUserData, value: MapperApp.eventMarker)
        replacement.post(tap: .cghidEventTap)
    }

    private func registerStringDefault(_ value: String, for key: String) {
        if preferenceString(for: key) == nil {
            setPreferenceString(value, for: key)
        }
    }

    private func boolPreference(for key: String) -> Bool {
        preferenceString(for: key) == "true"
    }

    private func preferenceString(for key: String) -> String? {
        CFPreferencesCopyAppValue(key as CFString, MapperApp.preferencesDomain) as? String
    }

    private func setPreferenceString(_ value: String, for key: String) {
        CFPreferencesSetAppValue(key as CFString, value as CFString, MapperApp.preferencesDomain)
        CFPreferencesAppSynchronize(MapperApp.preferencesDomain)
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            settingsWindow = makeSettingsWindow()
        }
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func makeSettingsWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 620),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Windows to Mac Toolkit"
        window.isReleasedWhenClosed = false

        let tabView = NSTabView()
        tabView.translatesAutoresizingMaskIntoConstraints = false
        tabView.addTabViewItem(tab(title: "Function Keys", view: functionKeysTab()))
        tabView.addTabViewItem(tab(title: "Ctrl Shortcuts", view: ctrlShortcutsTab()))
        tabView.addTabViewItem(tab(title: "Finder", view: finderTab()))
        tabView.addTabViewItem(tab(title: "Alt-Tab", view: altTabTab()))

        let content = NSView()
        content.addSubview(tabView)
        NSLayoutConstraint.activate([
            tabView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            tabView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            tabView.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            tabView.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16)
        ])

        window.contentView = content
        return window
    }

    private func tab(title: String, view: NSView) -> NSTabViewItem {
        let item = NSTabViewItem(identifier: title)
        item.label = title
        item.view = view
        return item
    }

    private func functionKeysTab() -> NSView {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 640, height: 540))
        scrollView.hasVerticalScroller = true

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "Function Keys")
        title.font = .boldSystemFont(ofSize: 20)
        let subtitle = NSTextField(labelWithString: "Choose a built-in command or record a custom shortcut.")
        subtitle.textColor = .secondaryLabelColor

        stack.addArrangedSubview(title)
        stack.addArrangedSubview(subtitle)
        for key in FunctionKey.allCases {
            stack.addArrangedSubview(functionKeyRow(for: key))
        }

        let note = NSTextField(wrappingLabelWithString: "Tip: enable Accessibility permission for Windows to Mac Toolkit if mappings do not work.")
        note.textColor = .secondaryLabelColor
        note.font = .systemFont(ofSize: 12)
        note.preferredMaxLayoutWidth = 560
        stack.addArrangedSubview(note)

        let content = FlippedView(frame: NSRect(x: 0, y: 0, width: 620, height: 720))
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -20)
        ])

        scrollView.documentView = content
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: 0))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        return scrollView
    }

    private func ctrlShortcutsTab() -> NSView {
        let stack = tabStack(title: "Windows Ctrl Shortcuts", subtitle: "Keep the copy/paste/save muscle memory you brought from Windows.")
        stack.addArrangedSubview(toggleRow(
            title: "Translate Ctrl shortcuts to Command shortcuts",
            detail: "Ctrl-A/C/F/S/V/X/Z become Command-A/C/F/S/V/X/Z.",
            defaultsKey: "module.windowsShortcuts.enabled"
        ))
        return paddedView(containing: stack)
    }

    private func finderTab() -> NSView {
        let stack = tabStack(title: "Finder Fixes", subtitle: "Make Finder feel more like File Explorer.")
        stack.addArrangedSubview(toggleRow(title: "Enable Finder fixes", detail: "Master switch for all Finder behavior below.", defaultsKey: "module.finderFixes.enabled"))
        stack.addArrangedSubview(toggleRow(title: "Enter opens selected files", detail: "Enter sends Command-O in Finder.", defaultsKey: "finder.enterOpens"))
        stack.addArrangedSubview(toggleRow(title: "F2 renames selected files", detail: "F2 sends Return in Finder.", defaultsKey: "finder.f2Renames"))
        stack.addArrangedSubview(toggleRow(title: "Delete moves selected files to Trash", detail: "Forward Delete sends Command-Backspace in Finder.", defaultsKey: "finder.deleteTrashes"))
        return paddedView(containing: stack)
    }

    private func altTabTab() -> NSView {
        let stack = tabStack(title: "Alt-Tab", subtitle: "Windows-style window switching will live here.")
        let comingSoon = NSTextField(wrappingLabelWithString: "Coming next: Windows-style switching across individual windows.")
        comingSoon.textColor = .secondaryLabelColor
        comingSoon.preferredMaxLayoutWidth = 600
        stack.addArrangedSubview(comingSoon)
        return paddedView(containing: stack)
    }

    private func tabStack(title: String, subtitle: String) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .boldSystemFont(ofSize: 20)
        let subtitleLabel = NSTextField(labelWithString: subtitle)
        subtitleLabel.textColor = .secondaryLabelColor

        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(subtitleLabel)
        return stack
    }

    private func paddedView(containing stack: NSStackView) -> NSView {
        let view = NSView()
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 20)
        ])
        return view
    }

    private func toggleRow(title: String, detail: String, defaultsKey: String) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 12

        let checkbox = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleChanged(_:)))
        checkbox.identifier = NSUserInterfaceItemIdentifier(defaultsKey)
        checkbox.state = boolPreference(for: defaultsKey) ? .on : .off

        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2

        let titleLabel = NSTextField(labelWithString: title)
        let detailLabel = NSTextField(wrappingLabelWithString: detail)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.font = .systemFont(ofSize: 12)
        detailLabel.preferredMaxLayoutWidth = 560

        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(detailLabel)
        row.addArrangedSubview(checkbox)
        row.addArrangedSubview(textStack)
        return row
    }

    private func functionKeyRow(for key: FunctionKey) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 14

        let label = NSTextField(labelWithString: key.title)
        label.font = .monospacedSystemFont(ofSize: 14, weight: .medium)
        label.widthAnchor.constraint(equalToConstant: 44).isActive = true

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: key.symbolName, accessibilityDescription: key.macFunctionTitle)
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        icon.contentTintColor = .labelColor
        icon.widthAnchor.constraint(equalToConstant: 28).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 22).isActive = true

        let macFunctionLabel = NSTextField(labelWithString: key.macFunctionTitle)
        macFunctionLabel.textColor = .secondaryLabelColor
        macFunctionLabel.lineBreakMode = .byTruncatingTail
        macFunctionLabel.widthAnchor.constraint(equalToConstant: 150).isActive = true

        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        for action in KeyAction.allCases {
            popup.addItem(withTitle: action.title)
            popup.lastItem?.representedObject = action.rawValue
        }

        let selectedRawValue = preferenceString(for: key.defaultsKey) ?? KeyAction.none.rawValue
        if let selectedIndex = KeyAction.allCases.firstIndex(where: { $0.rawValue == selectedRawValue }) {
            popup.selectItem(at: selectedIndex)
        }

        popup.target = self
        popup.action = #selector(mappingChanged(_:))
        popup.identifier = NSUserInterfaceItemIdentifier(key.defaultsKey)
        popup.widthAnchor.constraint(equalToConstant: 160).isActive = true
        popupButtons[key.defaultsKey] = popup

        let shortcutControl = NSButton(title: shortcutDisplayValue(for: key), target: self, action: #selector(recordShortcut(_:)))
        shortcutControl.bezelStyle = .rounded
        shortcutControl.identifier = NSUserInterfaceItemIdentifier(key.shortcutDefaultsKey)
        shortcutControl.isHidden = selectedRawValue != KeyAction.custom.rawValue
        shortcutControl.widthAnchor.constraint(equalToConstant: 150).isActive = true
        shortcutControls[key.defaultsKey] = shortcutControl

        row.addArrangedSubview(label)
        row.addArrangedSubview(icon)
        row.addArrangedSubview(macFunctionLabel)
        row.addArrangedSubview(popup)
        row.addArrangedSubview(shortcutControl)
        return row
    }

    @objc private func toggleChanged(_ sender: NSButton) {
        guard let defaultsKey = sender.identifier?.rawValue else { return }
        setPreferenceString(sender.state == .on ? "true" : "false", for: defaultsKey)
        if sender.state == .on && defaultsKey.hasPrefix("finder.") {
            setPreferenceString("true", for: "module.finderFixes.enabled")
        }
    }

    @objc private func mappingChanged(_ sender: NSPopUpButton) {
        guard let defaultsKey = sender.identifier?.rawValue,
              let rawValue = sender.selectedItem?.representedObject as? String else { return }
        setPreferenceString(rawValue, for: defaultsKey)
        shortcutControls[defaultsKey]?.isHidden = rawValue != KeyAction.custom.rawValue
    }

    @objc private func recordShortcut(_ sender: NSButton) {
        guard let shortcutDefaultsKey = sender.identifier?.rawValue else { return }
        recordingShortcutKey = shortcutDefaultsKey
        sender.title = "Press shortcut..."

        if shortcutRecorderMonitor == nil {
            shortcutRecorderMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.captureShortcut(event)
                return nil
            }
        }
    }

    private func captureShortcut(_ event: NSEvent) {
        guard let shortcutDefaultsKey = recordingShortcutKey else { return }
        let shortcut = shortcutString(from: event)
        setPreferenceString(shortcut, for: shortcutDefaultsKey)

        if let functionKey = FunctionKey.allCases.first(where: { $0.shortcutDefaultsKey == shortcutDefaultsKey }) {
            shortcutControls[functionKey.defaultsKey]?.title = shortcutDisplayValue(for: functionKey)
        }

        recordingShortcutKey = nil
        if let shortcutRecorderMonitor {
            NSEvent.removeMonitor(shortcutRecorderMonitor)
            self.shortcutRecorderMonitor = nil
        }
    }

    private func shortcutDisplayValue(for key: FunctionKey) -> String {
        let value = preferenceString(for: key.shortcutDefaultsKey) ?? ""
        return value.isEmpty ? "Not set" : value
    }

    private func shortcutString(from event: NSEvent) -> String {
        var parts: [String] = []
        let flags = event.modifierFlags
        if flags.contains(.command) { parts.append("cmd") }
        if flags.contains(.control) { parts.append("ctrl") }
        if flags.contains(.option) { parts.append("option") }
        if flags.contains(.shift) { parts.append("shift") }
        parts.append(keyName(for: CGKeyCode(event.keyCode)) ?? (event.charactersIgnoringModifiers?.lowercased() ?? ""))
        return parts.filter { !$0.isEmpty }.joined(separator: "+")
    }

    private func keyName(for keyCode: CGKeyCode) -> String? {
        let names: [CGKeyCode: String] = [
            0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x",
            8: "c", 9: "v", 11: "b", 12: "q", 13: "w", 14: "e", 15: "r",
            16: "y", 17: "t", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "o", 32: "u", 33: "[", 34: "i", 35: "p", 36: "enter",
            37: "l", 38: "j", 39: "'", 40: "k", 41: ";", 42: "\\", 43: ",",
            44: "/", 45: "n", 46: "m", 47: ".", 48: "tab", 49: "space",
            50: "`", 51: "backspace", 53: "esc", 123: "left", 124: "right",
            125: "down", 126: "up"
        ]
        return names[keyCode]
    }

    @objc private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

private func eventCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    info: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    MapperApp.shared?.handle(proxy: proxy, type: type, event: event) ?? Unmanaged.passUnretained(event)
}

let app = NSApplication.shared
let delegate = MapperApp()
app.delegate = delegate
app.run()
