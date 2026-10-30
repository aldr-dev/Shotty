<p align="center">
  <img src="Resources/AppIcon.svg" width="128" alt="Shotty icon">
</p>

<h1 align="center">Shotty</h1>

<p align="center">
  A native macOS app for screenshots, annotations and screen recording — with upload to your own server.
</p>

<p align="center">
  <a href="https://github.com/aldr-dev/Shotty/releases"><img src="https://img.shields.io/github/v/release/aldr-dev/Shotty?include_prereleases&label=download" alt="Download"></a>
  <img src="https://img.shields.io/badge/macOS-15%2B-blue" alt="macOS 15+">
  <img src="https://img.shields.io/badge/Swift-AppKit%20%2B%20SwiftUI-orange" alt="Swift">
</p>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/editor-dark.png">
  <img src="docs/screenshots/editor.png" alt="Shotty editor with arrows, frames, text, blur and emoji">
</picture>

## Download

**[Shotty.dmg](https://github.com/aldr-dev/Shotty/releases/download/v1.1.1-beta/Shotty.dmg)** — universal build (Apple Silicon + Intel), macOS 15 or later.

Open the DMG and drag Shotty into Applications. All versions are on the [Releases](https://github.com/aldr-dev/Shotty/releases) page.

## Features

- **Screenshots** — area, window or whole screen, each with its own global hotkey
- **Editor** — arrows, frames, text, highlighter, emoji, blur and pixelate; undo/redo and zoom
- **Text recognition (OCR)** — select an area and the text goes straight to the clipboard
- **Screen recording** — full screen or an area, system audio and microphone, pause, 5‑second countdown before start
- **Upload** — FTP, FTPS and SFTP, several server profiles, passwords stored in Keychain, public link copied after upload
- **Notifications** — upload progress with Cancel, "link copied", "saved" with Show in Finder, errors with Retry
- Russian and English UI, light and dark theme, launch at login

## Screenshots

### Home

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/home-dark.png">
  <img src="docs/screenshots/home.png" width="600" alt="Shotty home window">
</picture>

### Screen recording

Pick full screen or an area, toggle system audio, microphone and cursor, then a countdown gives you time to get ready.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/recording-dark.png">
  <img src="docs/screenshots/recording.png" width="680" alt="Recording toolbar, countdown and recording controls">
</picture>

### Settings

<table>
  <tr>
    <td>
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/settings-general-dark.png">
        <img src="docs/screenshots/settings-general.png" alt="General settings: language, theme and keyboard shortcuts">
      </picture>
    </td>
    <td>
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/settings-servers-dark.png">
        <img src="docs/screenshots/settings-servers.png" alt="Server settings: FTP, FTPS and SFTP profiles">
      </picture>
    </td>
  </tr>
</table>

## Keyboard shortcuts

| Action | Default |
|---|---|
| Capture area | <kbd>⇧</kbd><kbd>⌘</kbd><kbd>7</kbd> |
| Capture window | <kbd>⇧</kbd><kbd>⌘</kbd><kbd>8</kbd> |
| Capture full screen | <kbd>⇧</kbd><kbd>⌘</kbd><kbd>9</kbd> |
| Recognize text | <kbd>⌥</kbd><kbd>⇧</kbd><kbd>⌘</kbd><kbd>T</kbd> |
| Start / stop recording | <kbd>⌥</kbd><kbd>⇧</kbd><kbd>⌘</kbd><kbd>R</kbd> |
| Switch upload server | <kbd>⌥</kbd><kbd>⇧</kbd><kbd>⌘</kbd><kbd>U</kbd> |
| Open Shotty | <kbd>⌥</kbd><kbd>⇧</kbd><kbd>⌘</kbd><kbd>O</kbd> |

All shortcuts can be changed in Settings → General.

## First launch

Shotty is not notarized by Apple yet, so macOS will warn that the developer cannot be verified. To open it:

- right‑click Shotty in Applications → **Open** → **Open**, or
- run in Terminal:

  ```bash
  xattr -dr com.apple.quarantine /Applications/Shotty.app
  ```

Then allow **Screen & System Audio Recording** for Shotty in System Settings → Privacy & Security, and restart the app.

## Build from source

No Xcode project needed — only the Swift toolchain (Command Line Tools).

```bash
./build.sh
```

The script compiles a universal binary, generates the icon and packs `build/Shotty.app` and `build/Shotty.dmg`.

## Feedback

This is a beta — please report bugs and ideas in [Issues](https://github.com/aldr-dev/Shotty/issues).
