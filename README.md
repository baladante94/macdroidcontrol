# MacDroidControl

A native macOS app to mirror, control, and manage Android devices from your Mac — built on top of [scrcpy](https://github.com/Genymobile/scrcpy) and ADB.

> **License:** Proprietary — All Rights Reserved. Source code is visible for evaluation purposes only. See [LICENSE](LICENSE) for full terms.

---

## Features

### Device Mirroring
- Mirror any connected Android device in real time via scrcpy
- Full touch and keyboard input passthrough from your Mac
- Auto-restarts the mirror session on unexpected disconnects (phone lock, USB glitch, etc.)
- Live "MIRRORING" badge in the sidebar while a session is active

### Screen Recording
- Record the device mirror directly to a file on your Mac
- Choose a custom save folder per device
- Recording file is automatically revealed in Finder when stopped
- Live "REC" badge shown in the sidebar during recording

### Screenshot
- Captures the scrcpy window directly — works even for DRM-protected and banking apps
- Falls back to ADB `screencap` if scrcpy is not running
- Saves as PNG to a configurable folder

### Wireless ADB
- **Prepare for Wi-Fi** button (USB connected) — switches the device to TCP/IP mode in one click
- Connect wirelessly by entering the device's IP address
- Pre-flight connectivity check before launching: shows a clear error if the device is unreachable, instead of silently hanging
- Saved wireless devices reconnect in one tap; offline devices stay visible in the Saved section of the sidebar

### File Transfer
- Full file browser starting at `/sdcard` (Internal Storage)
- Breadcrumb navigation bar with back button
- **Push** files to the device by drag-and-drop or file picker (multiple files at once)
- **Pull** individual files or batch-pull selected files with up to 4 parallel transfers
- Live progress indicator for batch pulls
- "Show in Finder" shortcut after a successful transfer

### App Installer
- Install `.apk`, `.xapk`, and `.apkm` packages
- Drag-and-drop or file picker
- XAPK and APKM (split-APK bundles) are automatically unpacked and installed using `adb install-multiple`

### App Manager
- Lists all third-party apps installed on the device
- Search by app name or package name
- Launch any app directly from your Mac
- Uninstall apps with a confirmation prompt

### Device Information
- Displays model name, Android version, battery level (with charging indicator ⚡), and storage usage
- Refreshable with a single click

### Saved Devices
- Save a device's name and IP so you never retype it
- Edit saved name or IP via right-click context menu
- Saved devices that come online automatically move to the active Devices list
- Offline saved devices stay in the Saved section for quick one-tap reconnect

### Device Nicknames
- Rename any device (USB or wireless) via right-click → Rename
- Nickname shown everywhere in the UI instead of the raw device ID or IP address

### Mirror Configuration

| Setting | Description |
|---|---|
| Always on Top | Mirror window stays above all other windows |
| Stay Awake | Prevents the device screen from sleeping during mirroring |
| Turn Screen Off | Blacks out the device display while mirroring (saves battery) |
| Audio | Streams device audio to your Mac with selectable output device |
| Screenshots Folder | Custom save location for screenshots |
| Recordings Folder | Custom save location for recordings |

### Wireless Settings (per device)
| Setting | Options |
|---|---|
| Max FPS | 15 / 30 / 60 fps |
| Bitrate | 2 / 4 / 8 / 16 Mbps |

Lower FPS and bitrate reduce lag and Wi-Fi load on busy networks.

### Quality Presets

| Preset | Bitrate | Resolution | FPS |
|---|---|---|---|
| Low Latency | 2 Mbps | 720p max | 60 |
| Balanced | 8 Mbps | Full | 60 |
| High Quality | 16 Mbps | Full | 60 |

### App Settings
- **Theme** — System, Light, or Dark
- **Launch at Login** — adds MacDroidControl to macOS login items via `SMAppService`

### Menu Bar App
- MacDroidControl lives in the menu bar — always one click away
- Closing the window hides it; the app keeps running in the background
- One-time hint on first close explains the menu bar behavior

---

## Requirements

- macOS 13 or later
- [scrcpy](https://github.com/Genymobile/scrcpy) installed via Homebrew:
  ```
  brew install scrcpy
  ```
  This also installs `adb` automatically.

### Android Device Setup
1. Enable **Developer Options** (tap Build Number 7 times in Settings → About Phone)
2. Enable **USB Debugging** in Developer Options
3. Connect via USB and tap **Allow** on the authorization prompt on your phone

---

## Wireless Setup (Step by Step)

1. Connect your Android phone via USB
2. Select the device in the MacDroidControl sidebar
3. Scroll to **ADB Controls** and click **Prepare for Wi-Fi**
   - This switches ADB to TCP/IP mode over USB (do this once per device)
4. Unplug the USB cable
5. Click the **Wi-Fi button** in the toolbar, enter the phone's local IP address, and click Connect
6. The device appears in **Devices** — right-click and choose **Save Device** to save it for future sessions

---

## Tech Stack

| Component | Purpose |
|---|---|
| SwiftUI | Native macOS UI |
| scrcpy | Device mirroring and screen recording |
| ADB (Android Debug Bridge) | Device communication, file transfer, app management |
| SMAppService | Launch at Login (macOS 13+) |
| NSWindowDelegate | Menu bar and window lifecycle management |

---

## Third-Party Acknowledgements

**scrcpy** — [github.com/Genymobile/scrcpy](https://github.com/Genymobile/scrcpy)
Licensed under the [Apache License 2.0](https://github.com/Genymobile/scrcpy/blob/master/LICENSE).
scrcpy is not bundled with MacDroidControl — it is installed separately by the user via Homebrew.
MacDroidControl launches scrcpy as an external process and does not modify or redistribute its code.

---

## License

Copyright (c) 2026 Dante. All Rights Reserved.

This software is proprietary. The source code is made available for viewing and evaluation purposes only. You may not copy, modify, distribute, or use any part of this code in your own projects without explicit written permission from the author.

See the [LICENSE](LICENSE) file for full terms.
