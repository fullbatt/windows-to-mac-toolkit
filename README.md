# Windows to Mac Toolkit

`Windows to Mac Toolkit` is a small macOS menu-bar helper for Windows users who want familiar keyboard behavior on a Mac.

## Download

Download the latest full macOS installer from the [GitHub Releases page](https://github.com/fullbatt/windows-to-mac-toolkit/releases/latest):

[Download Windows to Mac Toolkit 0.1.0](https://github.com/fullbatt/windows-to-mac-toolkit/releases/download/v0.1.0/Windows-to-Mac-Toolkit-0.1.0-macOS.zip)

Unzip the download and move **F Key Mapper.app** to your Applications folder. macOS may require Accessibility permission before keyboard mappings can work.

The menu-bar item is named **Win->Mac**. Open **Settings...** to configure the modules in separate tabs.

## Modules

### Function Keys

Assign any function key from **F1** through **F12** to:

- `None`
- `Delete`
- `Home`
- `End`
- `Custom Shortcut`

Each row shows the F key, the matching Mac keyboard icon, the Mac function name, and the command dropdown.
When `Custom Shortcut` is selected, click the shortcut value, press the shortcut, and the app saves it. Examples include `cmd+shift+4`, `cmd+option+esc`, or `ctrl+cmd+space`.

- `Delete` sends Command-Backspace, which moves selected Finder items to Trash and matches the original F9 Delete helper.
- `Home` sends Command-Left.
- `End` sends Command-Right.
- `None` leaves the original F key alone.

### Windows Ctrl Shortcuts

Optional toggle that translates common Windows muscle-memory shortcuts:

- `Ctrl-A/C/F/S/V/X/Z` -> `Command-A/C/F/S/V/X/Z`

### Finder Fixes

Optional toggle for Finder-only behavior:

- `Enter` opens selected files.
- `F2` renames selected files.
- `Delete` moves selected files to Trash.

### Alt-Tab

Placeholder for the next module: Windows-style switching across individual windows.

Settings are saved automatically with macOS `UserDefaults`.

## Source

- `/Users/andre/Desktop/Codex/local-code/keymapping/F Key Mapper.swift`
- `/Users/andre/Desktop/Codex/local-code/keymapping/Info.plist`
- `/Users/andre/Desktop/Codex/local-code/keymapping/com.andre.fkeymapper.plist`

## Build

```sh
mkdir -p '/Users/andre/Applications/F Key Mapper.app/Contents/MacOS'
cp '/Users/andre/Desktop/Codex/local-code/keymapping/Info.plist' '/Users/andre/Applications/F Key Mapper.app/Contents/Info.plist'
xcrun swiftc '/Users/andre/Desktop/Codex/local-code/keymapping/F Key Mapper.swift' -o '/Users/andre/Applications/F Key Mapper.app/Contents/MacOS/FKeyMapper'
codesign --force --sign - '/Users/andre/Applications/F Key Mapper.app'
```

## Run

```sh
open '/Users/andre/Applications/F Key Mapper.app'
```

## Accessibility Permission

macOS requires Accessibility permission before the helper can listen for keys and send replacements.

Open **System Settings -> Privacy & Security -> Accessibility**, then enable **F Key Mapper**.

The app also has an **Accessibility Settings...** menu item.

## Start at Login

Install the launch agent:

```sh
cp '/Users/andre/Desktop/Codex/local-code/keymapping/com.andre.fkeymapper.plist' '/Users/andre/Library/LaunchAgents/com.andre.fkeymapper.plist'
launchctl bootstrap gui/$(id -u) '/Users/andre/Library/LaunchAgents/com.andre.fkeymapper.plist'
```

## Stop or Remove

```sh
launchctl bootout gui/$(id -u)/com.andre.fkeymapper
rm -rf '/Users/andre/Applications/F Key Mapper.app'
rm -f '/Users/andre/Library/LaunchAgents/com.andre.fkeymapper.plist'
```
