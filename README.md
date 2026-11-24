# Quickshell macOS Shell — Lightweight Edition

A **performance-tuned, lightweight personal modification** of the macOS-inspired Quickshell desktop shell for **Hyprland on Arch Linux**.

This repository keeps the clean macOS desktop aesthetic (TopBar, Dock, Dynamic Pill, Spotlight, Control Center, and Lock Screen) while **cutting idle overhead, eliminating background polling, fixing broken theme behaviors, and turning the shell into a practical daily-driver for tiling-WM + CLI-first workflows**.

---

## Credits & Attribution

All original theme architecture, base QML components, shaders, and visual assets belong to their respective creators. This repository makes **no claim of original ownership** over the base theme and is published purely as a documented, lightweight personal configuration:

- **Base Shell / Theme:** Revo / `eqsh` macOS Quickshell theme
- **Referenced Components:**
  - `AvengeMedia/DankMaterialShell` (`CompositorService.qml` reference)
  - `macos-tahoe-liquid-kde` (`AboutWindow.qml` reference)

---

## Performance & RAM Footprint

Measured on **Arch Linux (Hyprland 0.56.2, 1920×1080, AMD Radeon Lucienne, 7.1 GiB total RAM)**:

| State | `quickshell` RSS | Idle Wayland Layers | Notes |
| :--- | ---: | :--- | :--- |
| **Before Optimization** (original preloaded shell) | **694.8 MiB** (9.5%) | `macos:topbar`, `macos:dock`, `eqsh:spotlight` (1920×1038) | Fullscreen Spotlight layer & Control Center stayed alive 24/7; GPU `ShaderEffect`/`MultiEffect` loaded Mesa LLVM (~124 MiB) + GPU buffers. |
| **After Optimization** (this Lightweight Edition) | **291.5 MiB** (3.9%) | `macos:topbar`, `macos:dock` | **~403.3 MiB saved (-58% RAM at idle!).** Pure-QML frosted glass (`QT_QUICK_BACKEND=software` + `MALLOC_ARENA_MAX=2`), lazy-loaded overlays + `gc()`, and no idle fullscreen layer. |

> **What remains in ~291.5 MiB:** Qt6/QtQuick runtime, SF Pro fonts, Wayland compositor surfaces, and the always-visible TopBar + Dock icon assets—with zero GPU shader compiler (`libLLVM.so` / `libgallium`) bloat.

### How the Footprint Was Reduced
1. **On-Demand Lazy Loading (`shell.qml`, `ControlCenter.qml`, `DynamicIsland.qml`):**
   - **Spotlight**, **Control Center** (1,391 lines of Bluetooth/PipeWire/Glass UI), **Lock Screen**, **Session Menu**, **ConfirmDialog**, **ForceQuit**, **App Launcher Grid**, and **AI Chat** are wrapped in `Loader` / `LazyLoader`.
   - Overlays only allocate memory when opened, keep a short `300–400ms` grace window for close animations to finish, and immediately unload + trigger `gc()`.
   - Removed eager `Apps.ready` preloading on shell startup.
2. **Zero GPU Shader Bloat & Bounded Texture Caching (`DockGlass.qml`, `Dock.qml`, `DynamicIsland.qml`):**
   - Replaced heavy `ShaderEffect` (`grxframe.frag.qsb`) and `MultiEffect` offscreen FBOs in the Dock with pure-QML frosted glass `Rectangle`s (preserving the macOS translucent look, top sheen, and 1px rim highlight without triggering Mesa/LLVM shader compilation).
   - Disabled persistent `QPixmapCache` retention (`cache: false`) on app launcher icons and MPRIS media cover art, and bounded `GridView` `cacheBuffer: 84` (1 off-screen row).
3. **Eliminated Wasted Background Work:**
   - Removed the `A` / `ع` keyboard layout switcher from `TopBar.qml` (which spawned `hyprctl` + `python3` every 1 second).
   - Removed the duplicate notification bell & popup from the center pill (centralized into TopBar's Notification Center).
   - Removed Spotlight's in-memory clipboard history mode so copied text/images aren't duplicated in shell RAM.
4. **Software Renderer & Heap Tuning:**
   - Launching with `QT_QUICK_BACKEND=software MALLOC_ARENA_MAX=2` bypasses the ~124 MiB Mesa/LLVM GPU driver overhead and prevents glibc multi-arena heap bloat across worker threads.

---

## Custom Modifications & Features

### 1. Dynamic Island Wannabe (`modules/topbar/DynamicIsland.qml`)
> *Note: Not a 1:1 Apple Dynamic Island clone—just a compact floating command pill tailored for a **tiling-WM + CLI-first workflow**. Unlike heavy Electron/desktop GUI apps where opening a second chat tab consumes hundreds of MBs of RAM, CLI agents (`agy`, `claude`, `codex`, `gemini`) run lightweight directly in the terminal. Having a pinnable overlay AI scratchpad in the top bar gives you that fast, low-memory CLI advantage—letting you run quick queries, `/resume` past sessions, or draft plans **without splitting your tiled layout or spinning up a heavy desktop app**, and pop out to a full terminal session anytime.*

- **Native Launchpad App Launcher (`3×3` Vector Dot Grid):**
  - Replaced the basic font glyph with a crisp QML `3×3` rounded-dot grid that shifts color on hover/active.
  - Hovering or clicking opens a **4-column macOS glass app grid** backed by `Apps.qml` with live search, `Enter` to launch the top match, `Esc` to dismiss, a **Rofi** fallback button, and instant auto-close when the cursor leaves.
  - Properly handles **Loading**, **Empty** (with `"Reset Pencarian"`), and **Overflow** states.
- **Roman Numeral Workspace Switcher (`I–V`):**
  - Fixed a theme bug where the workspace popup refused to open whenever media was active (`&& !root.hasMedia`).
  - Hovering or clicking the Roman numeral opens the `I–V` picker; scrolling the mouse wheel over either the pill or the popup dispatches Hyprland workspace switches (`-1` / `+1`).
- **ArchLinux AI Chat (`>_` Terminal Icon):**
  - Integrated mini AI chat room powered by `agy -p` / `agy -c -p` by default, with Markdown rendering (`Text.MarkdownText`) and iMessage-style bubbles (**adaptable to any other AI CLI** such as `gemini`, `claude`, `codex`, or `ollama`—see [Requirements & Setup](#requirements--setup)).
  - **`/resume` & Session History Picker:** Scans recent sessions in `~/.gemini/antigravity-cli/brain/`, displays each session's actual first prompt and timestamp (stripping internal XML metadata tags), and reloads the last 20 messages from `transcript.jsonl`.
  - **macOS Traffic Lights (`-`, `=`, `o`):**
    - **Red (`-`):** Closes the chat and resets pin state.
    - **Yellow (`=`):** Pins the chat by seamlessly promoting it from a `PanelWindow` overlay to a native Hyprland **`FloatingWindow`** (`Super + Left-Drag` or header drag to move anywhere on screen, `Super + Right-Drag` to resize) while preserving any typed draft text (`chatDraft`) until closed with `-`.
    - **Green (`o`):** Pops out the active conversation (`--conversation <id>` or `-c`) into a full `kitty -e agy` terminal window.
  - **Terminal Quick Actions:**
    - `Go to agy Terminal`: Inspects `/proc` ancestor PIDs and `hyprctl clients -j` to locate a running `agy` terminal across workspaces and focuses it via Hyprland 0.56+ Lua dispatch (`hl.dsp.focus`), or spawns `kitty -e agy` if none is running.
    - `New agy Terminal`: Always launches a fresh `kitty -e agy` instance.
- **Live System Telemetry & Media Controls:**
  - Displays live CPU%, RAM%, and Swap/ZRAM% (hover for detailed breakdown popup including `k10temp` CPU temperature and load average; click to open `btop` in `kitty`) plus MPRIS media equalizer & playback controls.

### 2. TopBar, Notification Center & System Tray (`modules/topbar/TopBar.qml`, `eqsh/TrayMenu.qml`, `eqsh/SysTrayItem.qml`)
- **Hover Auto-Open with 600ms Grace Delay:**
  - **Battery**, **Wi-Fi**, and **Clock / Notification Center** popups open automatically on hover and use a shared `600ms` `rightBarCloseTimer` + popup `HoverHandler`s so the cursor has plenty of time to travel from the bar into the menu before auto-closing.
- **Live Battery & Functional Wi-Fi Picker:**
  - Added `Math.round(Battery.percentage * 100) + "%"` directly next to the SVG battery icon in the TopBar.
  - Replaced the static Wi-Fi placeholder items (`Privacy Warning…`, `Other Networks ▶`) with live connection status, a scrollable **Available Networks** list (`Network.wifiNetworks` + click to connect), and a **Wi-Fi Settings...** shortcut.
- **Fixed Notification Center:**
  - Fixed a theme bug where notification cards inside `Column` used `Layout.fillWidth: true` without `width`, causing every notification card to render at `width: 0` (invisible even when `"Clear All"` was visible).
  - Synced initial history with `Notifications.recent` on startup and replaced the overly transparent background with a readable dark-glass panel (`rgba(0.10, 0.10, 0.14, 0.92)`).
- **System Tray Usability Fixes:**
  - Enabled hover-to-open (`onEntered`) and right-click toggle on tray icons, added a `650ms` `anchorHovered` grace timer so menus stay open while moving the pointer into them, and added a dark-glass backdrop behind `BoxGlass` so overlapping menus remain legible.

### 3. Spotlight Overhaul (`modules/spotlight/Spotlight.qml`, `ContentView.qml`, `ContentGlobal.qml`, `ContentItem.qml`)
- **100% Opaque Dark Surface & Auto-Focus:**
  - Increased `glassColor` opacity to `100%` (`#ff1a1a20` dark / `#ffffffff` light) to eliminate background text bleed-through, and added `Qt.callLater(() => search.forceActiveFocus())` so typing works immediately without clicking.
- **Full Keyboard Navigation & App Launching:**
  - Implemented `Up`, `Down`, `PageUp`, `PageDown`, `Enter`/`Return`, and `Esc` navigation in `ContentGlobal.qml` with automatic top-item selection (`currentIndex = 0`) and active-row highlighting in `ContentItem.qml`.
  - Switched app launching from `entry.execute()` to `Apps.launch(entry.execString)` (`setsid -f`) so selected apps launch reliably on Hyprland.
- **Three Working Modes (`Applications`, `Files`, `Actions`):**
  - **Applications (`Ctrl+1`):** Immediately lists all desktop applications when selected (filtering live as you type).
  - **Files (`Ctrl+2`):** Walks `$HOME` (skipping `.git`, `node_modules`, `.cache`, `.local`, `.cargo`, `.npm`, `venv`, `__pycache__`; capped at 25 results) and opens files/folders via `xdg-open`.
  - **Actions (`Ctrl+3`):** 17 ready-to-use system actions (*Open Terminal, File Manager, System Monitor `btop`, Control Center, Notification Center, Screenshot Region/Fullscreen/Window, Wi-Fi Settings, Audio Mixer, Bluetooth Manager, Lock Screen, Reload Quickshell, Sleep/Suspend, Restart PC, Shutdown PC, Log Out*).
  - Mapped all `Files` and `Actions` items to local macOS PNG/SVG assets (`assets/icons/` and `media/icons/`) and added local-path handling in `ContentItem.qml` to eliminate missing-icon checkerboards.

---

## Requirements & Setup

### 1. AI Chat Backend (`agy` CLI or Custom CLI)
The **ArchLinux AI Chat** popup inside the Dynamic Island Wannabe is **not a built-in LLM**—it is a lightweight frontend wrapper around a terminal AI CLI running in non-interactive print mode:
- **Default (`agy` CLI):** Requires `agy` (Antigravity CLI) installed in `$PATH` and authenticated for chat, `/resume`, `Go to agy Terminal`, and `New agy Terminal` to work.
- **Session History (`/resume`):** Reads recent conversation transcripts from `~/.gemini/antigravity-cli/brain/<session-id>/.system_generated/logs/transcript.jsonl`.
- **Using Another CLI (e.g., `gemini`, `claude`, `codex`, `ollama`):**
  - Edit `modules/topbar/DynamicIsland.qml` in `sendAgyChat()`, `expandAgyToTerminal()`, `focusAgyOrNew()`, and `newAgyTerminal()` to swap `agy -p` / `agy -c -p` for your preferred CLI's non-interactive flags.

### 2. Running the Shell (Hyprland)
1. Clone or copy this repository to `~/.config/quickshell/macos`.
2. Ensure no competing D-Bus notification daemon (`swaync`, `dunst`, `mako`) is holding `org.freedesktop.Notifications` if you want Quickshell's Notification Center to receive notifications:
   ```bash
   pkill -x swaync 2>/dev/null || true
   ```
3. Launch Quickshell with `QT_QUICK_BACKEND=software` and `MALLOC_ARENA_MAX=2` to achieve the ~291 MiB lightweight footprint:
   ```bash
   QT_QUICK_BACKEND=software MALLOC_ARENA_MAX=2 quickshell -p ~/.config/quickshell/macos
   ```
4. *(Optional)* Add a Hyprland window rule (`~/.config/hypr/configs/windowrule.lua`) so the pinned AI Chat (`=` yellow button) floats cleanly across all workspaces:
   ```lua
   hl.window_rule({
       match = { title = "^ArchLinux AI Chat$" },
       float = true,
       center = true,
       pin = true,
       size = "396 440",
       border_size = 0,
       rounding = 20,
       opacity = "1 1",
   })
   ```
