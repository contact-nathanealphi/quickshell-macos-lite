# Quickshell macOS Shell — Lightweight Edition

A **lightweight, performance-tuned personal modification** of the macOS-inspired Quickshell desktop shell for Hyprland (Arch Linux).

This fork is engineered to **preserve the clean macOS aesthetic while significantly reducing RAM and GPU overhead** by trimming heavy motion effects, stripping unnecessary background polling/liquid-glass layers, and lazy-loading heavy overlays on demand.

---

## Credits & Attribution

All original theme architecture, base QML components, shaders, and assets belong to their respective creators. This repository makes **no claim of original ownership** over the base theme and is published purely as a lightweight, modified personal dotfiles configuration:

- **Base Shell / Theme:** Revo / `eqsh` macOS Quickshell theme
- **Referenced Components:**
  - `AvengeMedia/DankMaterialShell` (`CompositorService.qml` reference)
  - `macos-tahoe-liquid-kde` (`AboutWindow.qml` reference)

---

## Why This Version Is Lighter

- **On-Demand Lazy Loading (`shell.qml`, `ControlCenter.qml`, `DynamicIsland.qml`):**
  - Heavy modules—**Spotlight**, **Control Center**, **Lock Screen**, **Session**, **ConfirmDialog**, **ForceQuit**, **App Launcher Grid**, and **AI Chat**—are wrapped in `Loader` / `LazyLoader` and only instantiated when opened, then unloaded with `gc()` after closing.
  - Eliminates idle fullscreen Wayland overlay layers (`eqsh:spotlight`) and saves ~75+ MiB of idle RSS (plus `MALLOC_ARENA_MAX=2` heap tuning).
- **Reduced Texture & Shader Overhead:**
  - App icons and media cover art use `cache: false` and bounded `GridView` `cacheBuffer` so decoded bitmaps are not retained in memory after closing popups.
  - Replaced heavy transparent/liquid-glass surfaces in popups with crisp, readable dark-glass panels (`100%` opaque Spotlight for legibility).
- **Removed Unneeded Background Polling & Modules:**
  - Removed the `A` / `ع` keyboard layout switcher (which polled `hyprctl` + `python3` every second), removed the duplicate Dynamic Island notification bell, and disabled Spotlight's in-memory clipboard history mode.

---

## Custom Modifications & Features

### 1. Dynamic Island (`modules/topbar/DynamicIsland.qml`)
- **Native Launchpad App Launcher (`3×3` Grid Icon):**
  - Hovering or clicking opens a compact 4-column macOS glass app grid backed by `Apps.qml` with live search, `Enter` to launch, `Esc` to close, optional **Rofi** shortcut, and instant auto-close when the cursor leaves.
- **Roman Numeral Workspace Switcher (`I–V`):**
  - Hovering or clicking opens the workspace picker (works even when media is playing); scrolling with the mouse wheel on either the pill or popup switches Hyprland workspaces (`-1` / `+1`).
- **ArchLinux AI Chat (`>_` Terminal Icon):**
  - Integrated mini AI chat room powered by `agy -p` / `agy -c -p` with Markdown rendering and clean iMessage-style bubbles.
  - **`/resume` & History Picker:** Lists recent sessions by their first prompt and timestamp, and reloads previous conversation messages from `transcript.jsonl`.
  - **macOS Traffic Lights (`-`, `=`, `o`):**
    - **Red (`-`):** Close the chat popup.
    - **Yellow (`=`):** Pin the chat as a native Hyprland `FloatingWindow` (`Super + Left-Drag` / header drag to move anywhere on screen, `Super + Right-Drag` to resize) that stays open until closed with `-`.
    - **Green (`o`):** Pop out the active session into a full `kitty -e agy` terminal window.
  - **Terminal Quick Actions:** `Go to agy Terminal` (focuses an active `agy` terminal window across workspaces or launches one) and `New agy Terminal`.

### 2. TopBar & Popups (`modules/topbar/TopBar.qml`, `eqsh/TrayMenu.qml`, `eqsh/SysTrayItem.qml`)
- **Hover Auto-Open & Grace Delay (`600ms`):** Battery, Wi-Fi, and Notification Center (clock/date) popups open on hover and stay open long enough for the cursor to move into the menu before auto-closing.
- **Battery Percentage Indicator:** Displays the live battery percentage (`XX%`) directly beside the battery icon.
- **Fixed Notification Center:** Fixed `Column` delegate width (`width: notifCol.width`) so incoming notifications render properly, synced initial history with `Notifications.recent`, and improved dark-glass readability.
- **System Tray Improvements:** Auto-opens tray menus on hover (`650ms` grace delay), supports right-click toggle, and adds a dark-glass backdrop so menus don't overlap transparently.

### 3. Spotlight (`modules/spotlight/Spotlight.qml`, `ContentView.qml`, `ContentGlobal.qml`, `ContentItem.qml`)
- **100% Opaque Dark Surface & Auto-Focus:** Instant keyboard focus (`forceActiveFocus()`) on open with zero background bleed-through.
- **Full Keyboard Navigation:** Working `Up`, `Down`, `PageUp`, `PageDown`, `Enter`, and `Esc` with active item highlighting and `Apps.launch(...)` execution.
- **Working Modes (`Applications`, `Files`, `Actions`):**
  - **Applications (`Ctrl+1`):** Shows all desktop apps immediately when selected.
  - **Files (`Ctrl+2`):** Searches files and folders in `$HOME` (skipping `.git`, `node_modules`, `.cache`) and opens them via `xdg-open`.
  - **Actions (`Ctrl+3`):** Quick system actions (Terminal, Thunar, `btop`, Control Center, Notification Center, Screenshots, Wi-Fi/Audio/Bluetooth settings, Lock, Reload Quickshell, Sleep, Restart, Shutdown, Log Out) with real macOS icons.
