import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Mpris
import "../common"
import "../../services"

Item {
    id: root

    property var hostWindow: null
    property bool expanded: false
    property bool wsPickerOpen: false
    property bool sysReportOpen: false
    property bool termOpen: false
    property bool launcherOpen: false
    property bool launcherHovered: false
    property string launcherQuery: ""
    readonly property var filteredApps: (root.launcherOpen && Apps.apps.length >= 0) ? Apps.search(root.launcherQuery) : []
    property bool agyRunning: false
    property int activeWs: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1

    // CPU telemetry
    property int cpuPct: 0
    property real _prevCpuTotal: 0
    property real _prevCpuIdle: 0
    property int cpuTempC: -1
    property string loadAvg: "--"

    // RAM telemetry (KiB)
    property int memPct: 0
    property real memUsedKiB: 0
    property real memAvailKiB: 0
    property real memTotalKiB: 0

    // Swap & ZRAM telemetry (KiB)
    property int swapPct: 0
    property real swapUsedKiB: 0
    property real swapFreeKiB: 0
    property real swapTotalKiB: 0
    property real zramUsedKiB: 0
    property real zramTotalKiB: 0
    property real swapfileUsedKiB: 0
    property real swapfileTotalKiB: 0

    width: glassPill.width
    height: glassPill.height

    readonly property var activePlayer: {
        const raw = Mpris.players.values;
        const players = [];
        for (let i = 0; i < raw.length; i++) {
            if (String(raw[i].dbusName || "").indexOf("playerctld") < 0)
                players.push(raw[i]);
        }
        const pool = players.length > 0 ? players : raw;
        for (let i = 0; i < pool.length; i++) {
            if (pool[i].playbackState === MprisPlaybackState.Playing)
                return pool[i];
        }
        return pool.length > 0 ? pool[0] : null;
    }

    readonly property bool isPlaying: activePlayer ? (activePlayer.playbackState === MprisPlaybackState.Playing) : false
    readonly property string trackTitle: activePlayer ? (activePlayer.trackTitle || "") : ""
    readonly property string trackArtist: activePlayer ? (activePlayer.trackArtists ? activePlayer.trackArtists.join(", ") : "") : ""
    readonly property string artUrl: activePlayer ? (activePlayer.artUrl || "") : ""
    readonly property bool hasMedia: activePlayer !== null && (trackTitle.length > 0 || isPlaying)

    function fmtSize(kib) {
        if (kib <= 0) return "0 MiB";
        if (kib >= 1048576) return (kib / 1048576).toFixed(1) + " GiB";
        return Math.round(kib / 1024) + " MiB";
    }

    function toRoman(n) {
        const map = ["", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"];
        return (n >= 1 && n < map.length) ? map[n] : String(n);
    }

    function levelColor(pct, normalColor) {
        if (pct >= 85) return "#ff453a";
        if (pct >= 65) return "#ff9f0a";
        return normalColor;
    }

    function swapBreakdownText() {
        const parts = [];
        if (zramTotalKiB > 0)
            parts.push("zram0: " + fmtSize(zramUsedKiB) + "/" + fmtSize(zramTotalKiB));
        if (swapfileTotalKiB > 0)
            parts.push("swapfile: " + fmtSize(swapfileUsedKiB) + "/" + fmtSize(swapfileTotalKiB));
        return parts.length > 0 ? parts.join("  ·  ") : "Tidak ada perangkat swap";
    }

    function openBtop() {
        root.sysReportOpen = false;
        root.wsPickerOpen = false;
        root.launcherOpen = false;
        root.closeChatPopup();
        actionProc.running = false;
        actionProc.command = ["bash", "-c", "setsid -f kitty -e btop </dev/null >/dev/null 2>&1"];
        actionProc.running = true;
    }

    function openQuickTerminal() {
        root.closeChatPopup();
        actionProc.running = false;
        actionProc.command = ["bash", "-c", "setsid -f kitty </dev/null >/dev/null 2>&1"];
        actionProc.running = true;
    }

    function openRofiLauncher() {
        root.launcherOpen = false;
        root.wsPickerOpen = false;
        root.expanded = false;
        root.sysReportOpen = false;
        if (!root.chatPinned) root.closeChatPopup();
        actionProc.running = false;
        actionProc.command = ["bash", "-c", "setsid -f bash ~/.config/hypr/scripts/rofi_show.sh drun </dev/null >/dev/null 2>&1"];
        actionProc.running = true;
    }

    function launchAppEntry(execStr) {
        root.launcherOpen = false;
        root.launcherQuery = "";
        Apps.launch(execStr);
    }

    function closeChatPopup() {
        root.termOpen = false;
        root.chatPinned = false;
        root.chatHovered = false;
        root.resumeMode = false;
    }

    function focusAgyOrNew() {
        root.closeChatPopup();
        actionProc.running = false;
        actionProc.command = [
            "python3", "-c",
            "import json, os, subprocess\n" +
            "clients = json.loads(subprocess.check_output(['hyprctl', 'clients', '-j'], text=True))\n" +
            "anc = set()\n" +
            "for e in os.listdir('/proc'):\n" +
            "    if not e.isdigit(): continue\n" +
            "    try:\n" +
            "        comm = open(f'/proc/{e}/comm').read().strip().lower()\n" +
            "        cmd = open(f'/proc/{e}/cmdline', 'rb').read().replace(b'\\x00', b' ').decode('utf-8', 'ignore').lower()\n" +
            "        if comm == 'agy' or 'antigravity-cli' in cmd or 'agy ' in cmd or cmd.rstrip().endswith('/agy'):\n" +
            "            p = int(e)\n" +
            "            while p > 1 and p not in anc:\n" +
            "                anc.add(p)\n" +
            "                st = open(f'/proc/{p}/status').read()\n" +
            "                pp = [l.split()[1] for l in st.splitlines() if l.startswith('PPid:')]\n" +
            "                p = int(pp[0]) if pp else 0\n" +
            "    except Exception:\n" +
            "        pass\n" +
            "target = None\n" +
            "for c in clients:\n" +
            "    t = (c.get('title') or '').lower()\n" +
            "    it = (c.get('initialTitle') or '').lower()\n" +
            "    if c.get('pid') in anc or 'agy' in t or 'agy' in it or 'antigravity' in t or 'antigravity' in it:\n" +
            "        target = c\n" +
            "        break\n" +
            "if target:\n" +
            "    ws = (target.get('workspace') or {}).get('id', 0)\n" +
            "    addr = target['address']\n" +
            "    if ws and ws > 0:\n" +
            "        subprocess.run(['hyprctl', 'dispatch', f'hl.dsp.focus({{ workspace = {ws} }})'])\n" +
            "    subprocess.run(['hyprctl', 'dispatch', f'hl.dsp.focus({{ window = \"address:{addr}\" }})'])\n" +
            "else:\n" +
            "    subprocess.Popen(['kitty', '-e', 'agy'], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)\n"
        ];
        actionProc.running = true;
    }

    function newAgyTerminal() {
        root.closeChatPopup();
        actionProc.running = false;
        actionProc.command = ["bash", "-c", "setsid -f kitty -e agy </dev/null >/dev/null 2>&1"];
        actionProc.running = true;
    }

    function expandAgyToTerminal() {
        const sid = root.activeConversationId;
        const hasMsgs = root.chatMessages.length > 0;
        root.closeChatPopup();
        actionProc.running = false;
        if (sid !== "") {
            actionProc.command = ["bash", "-c", "setsid -f kitty -e agy --conversation \"$1\" </dev/null >/dev/null 2>&1", "_", sid];
        } else if (hasMsgs) {
            actionProc.command = ["bash", "-c", "setsid -f kitty -e agy -c </dev/null >/dev/null 2>&1"];
        } else {
            actionProc.command = ["bash", "-c", "setsid -f kitty -e agy </dev/null >/dev/null 2>&1"];
        }
        actionProc.running = true;
    }

    Process { id: actionProc; running: false }

    Process {
        id: agyCheckProc
        running: false
        command: ["bash", "-c", "(pgrep -x agy >/dev/null 2>&1 || pgrep -f 'antigravity-cli|agy ' >/dev/null 2>&1) && echo 1 || echo 0"]
        stdout: StdioCollector {
            onStreamFinished: root.agyRunning = (text.trim() === "1")
        }
    }

    property var chatMessages: []
    property bool chatLoading: false
    property string activeConversationId: ""
    property bool resumeMode: false
    property var historyList: []
    property bool chatPinned: false
    property bool chatHovered: false
    property string chatDraft: ""
    property string chatError: ""
    property string lastFailedPrompt: ""
    property string _agyStdout: ""
    property string _agyStderr: ""
    property int _agyExitCode: 0
    property bool _agyOutDone: false
    property bool _agyErrDone: false
    property bool _agyExited: false

    function openResumePicker() {
        root.resumeMode = true;
        historyProc.running = false;
        historyProc.running = true;
    }

    Process {
        id: historyProc
        running: false
        command: [
            "python3", "-c",
            "import os, json, glob, datetime, re\n" +
            "base = os.path.expanduser('~/.gemini/antigravity-cli/brain')\n" +
            "dirs = sorted([d for d in glob.glob(base + '/*') if os.path.isdir(d)], key=os.path.getmtime, reverse=True)[:8]\n" +
            "out = []\n" +
            "for d in dirs:\n" +
            "    sid = os.path.basename(d)\n" +
            "    t = ''\n" +
            "    ts = datetime.datetime.fromtimestamp(os.path.getmtime(d)).strftime('%b %d %H:%M')\n" +
            "    p = os.path.join(d, '.system_generated/logs/transcript.jsonl')\n" +
            "    if os.path.exists(p):\n" +
            "        for line in open(p, errors='ignore'):\n" +
            "            try:\n" +
            "                j = json.loads(line)\n" +
            "                if j.get('type') == 'USER_INPUT' and j.get('content'):\n" +
            "                    c = j['content']\n" +
            "                    c = re.sub(r'<(ADDITIONAL_METADATA|USER_SETTINGS_CHANGE|SYSTEM_MESSAGE)>.*?</\\1>', '', c, flags=re.S)\n" +
            "                    c = re.sub(r'</?USER_REQUEST>', '', c).replace('\\n', ' ').strip()\n" +
            "                    if c:\n" +
            "                        t = c[:45]\n" +
            "                        break\n" +
            "            except Exception:\n" +
            "                pass\n" +
            "    out.append({'id': sid, 'title': t or ('Session ' + sid[:8]), 'time': ts})\n" +
            "print(json.dumps(out))\n"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.historyList = JSON.parse(text.trim());
                } catch (e) {
                    root.historyList = [];
                }
            }
        }
    }

    Process {
        id: loadSessionProc
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.chatMessages = JSON.parse(text.trim());
                } catch (e) {
                    root.chatMessages = [];
                }
            }
        }
    }

    function loadSessionMessages(sid) {
        root.chatError = "";
        loadSessionProc.running = false;
        loadSessionProc.command = [
            "python3", "-c",
            "import os, sys, json, re\n" +
            "sid = sys.argv[1]\n" +
            "p = os.path.expanduser(f'~/.gemini/antigravity-cli/brain/{sid}/.system_generated/logs/transcript.jsonl')\n" +
            "msgs = []\n" +
            "if os.path.exists(p):\n" +
            "    for line in open(p, errors='ignore'):\n" +
            "        try:\n" +
            "            j = json.loads(line)\n" +
            "            tp = j.get('type')\n" +
            "            c = j.get('content', '')\n" +
            "            if not c: continue\n" +
            "            if tp == 'USER_INPUT':\n" +
            "                c = re.sub(r'<(ADDITIONAL_METADATA|USER_SETTINGS_CHANGE|SYSTEM_MESSAGE)>.*?</\\1>', '', c, flags=re.S)\n" +
            "                c = re.sub(r'</?USER_REQUEST>', '', c).strip()\n" +
            "                if c: msgs.append({'role': 'user', 'text': c})\n" +
            "            elif tp == 'PLANNER_RESPONSE':\n" +
            "                msgs.append({'role': 'agy', 'text': c.strip()})\n" +
            "        except Exception:\n" +
            "            pass\n" +
            "print(json.dumps(msgs[-20:]))\n",
            sid
        ];
        loadSessionProc.running = true;
    }

    function _finalizeAgyReply() {
        if (!root._agyOutDone || !root._agyErrDone || !root._agyExited) return;
        root.chatLoading = false;
        const reply = root._agyStdout.trim();
        const errText = root._agyStderr.trim();
        if (root._agyExitCode !== 0 || reply.length === 0) {
            root.chatError = errText.length > 0 ? errText : "Gagal mendapat respons dari agy.";
            return;
        }
        const next = root.chatMessages.slice();
        next.push({ role: "agy", text: reply });
        root.chatMessages = next;
        root.lastFailedPrompt = "";
    }

    function sendAgyChat(prompt) {
        const trimmed = (prompt || "").trim();
        if (!trimmed || root.chatLoading) return;
        if (trimmed === "/resume") {
            root.openResumePicker();
            return;
        }
        root.resumeMode = false;
        const isRetry = root.chatError !== "" && root.lastFailedPrompt === trimmed && root.chatMessages.length > 0 && root.chatMessages[root.chatMessages.length - 1].role === "user" && root.chatMessages[root.chatMessages.length - 1].text === trimmed;
        root.chatError = "";
        root.lastFailedPrompt = trimmed;
        let useContinue = root.chatMessages.length > 0;
        if (!isRetry) {
            const next = root.chatMessages.slice();
            next.push({ role: "user", text: trimmed });
            root.chatMessages = next;
        } else {
            useContinue = root.chatMessages.length > 1;
        }
        root.chatLoading = true;
        root._agyStdout = "";
        root._agyStderr = "";
        root._agyExitCode = 0;
        root._agyOutDone = false;
        root._agyErrDone = false;
        root._agyExited = false;
        agyChatProc.running = false;
        if (root.activeConversationId !== "") {
            agyChatProc.command = ["agy", "--conversation", root.activeConversationId, "-p", trimmed];
        } else {
            agyChatProc.command = useContinue
                ? ["agy", "-c", "-p", trimmed]
                : ["agy", "-p", trimmed];
        }
        agyChatProc.running = true;
    }

    Process {
        id: agyChatProc
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                root._agyStdout = text;
                root._agyOutDone = true;
                root._finalizeAgyReply();
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                root._agyStderr = text;
                root._agyErrDone = true;
                root._finalizeAgyReply();
            }
        }
        onExited: (exitCode, exitStatus) => {
            root._agyExitCode = exitCode;
            root._agyExited = true;
            root._finalizeAgyReply();
        }
    }

    Process {
        id: wsInitProc
        running: false
        command: ["bash", "-c", "hyprctl activeworkspace -j 2>/dev/null | jq -r '.id // 1'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const n = parseInt(text.trim());
                if (!isNaN(n) && n > 0) root.activeWs = n;
            }
        }
    }

    Process {
        id: hwmonInitProc
        running: false
        command: ["bash", "-c", "for d in /sys/class/hwmon/hwmon*; do [ \"$(cat \"$d/name\" 2>/dev/null)\" = \"k10temp\" ] && [ -r \"$d/temp1_input\" ] && echo \"$d/temp1_input\" && exit 0; done; for d in /sys/class/hwmon/hwmon*; do [ -r \"$d/temp1_input\" ] && echo \"$d/temp1_input\" && exit 0; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = text.trim();
                if (p.length > 0) {
                    tempFile.path = p;
                    tempFile.reload();
                }
            }
        }
    }

    Component.onCompleted: {
        wsInitProc.running = true;
        hwmonInitProc.running = true;
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "workspacev2") {
                const id = parseInt(String(event.data).split(",")[0]);
                if (!isNaN(id) && id > 0) root.activeWs = id;
                Hyprland.refreshWorkspaces();
            } else if (event.name === "workspace") {
                const id = parseInt(String(event.data));
                if (!isNaN(id) && id > 0) root.activeWs = id;
                Hyprland.refreshWorkspaces();
            } else if (event.name === "focusedmon" || event.name === "focusedmonv2") {
                wsInitProc.running = true;
                Hyprland.refreshWorkspaces();
            }
        }
        function onFocusedWorkspaceChanged() {
            if (Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.id > 0)
                root.activeWs = Hyprland.focusedWorkspace.id;
        }
    }

    FileView {
        id: memFile
        path: "/proc/meminfo"
        onLoaded: {
            const txt = memFile.text();
            const mTot = txt.match(/MemTotal:\s+(\d+)/);
            const mAvail = txt.match(/MemAvailable:\s+(\d+)/);
            if (mTot && mAvail) {
                const tot = parseInt(mTot[1]);
                const avail = parseInt(mAvail[1]);
                root.memTotalKiB = tot;
                root.memAvailKiB = avail;
                root.memUsedKiB = Math.max(0, tot - avail);
                if (tot > 0) root.memPct = Math.round(((tot - avail) / tot) * 100);
            }
            const sTot = txt.match(/SwapTotal:\s+(\d+)/);
            const sFree = txt.match(/SwapFree:\s+(\d+)/);
            if (sTot && sFree) {
                const tot = parseInt(sTot[1]);
                const free = parseInt(sFree[1]);
                root.swapTotalKiB = tot;
                root.swapFreeKiB = free;
                root.swapUsedKiB = Math.max(0, tot - free);
                root.swapPct = tot > 0 ? Math.round(((tot - free) / tot) * 100) : 0;
            }
        }
    }

    FileView {
        id: cpuFile
        path: "/proc/stat"
        onLoaded: {
            const first = cpuFile.text().split("\n")[0] || "";
            const nums = first.trim().split(/\s+/).slice(1).map(n => parseFloat(n) || 0);
            if (nums.length >= 4) {
                let total = 0;
                for (let i = 0; i < nums.length; i++) total += nums[i];
                const idle = nums[3] + (nums.length > 4 ? nums[4] : 0);
                if (root._prevCpuTotal > 0 && total > root._prevCpuTotal) {
                    const dTotal = total - root._prevCpuTotal;
                    const dIdle = idle - root._prevCpuIdle;
                    root.cpuPct = Math.max(0, Math.min(100, Math.round(((dTotal - dIdle) / dTotal) * 100)));
                }
                root._prevCpuTotal = total;
                root._prevCpuIdle = idle;
            }
        }
    }

    FileView {
        id: loadFile
        path: "/proc/loadavg"
        onLoaded: {
            const parts = loadFile.text().trim().split(/\s+/);
            if (parts.length >= 3) {
                root.loadAvg = parts[0] + "  " + parts[1] + "  " + parts[2];
            }
        }
    }

    FileView {
        id: swapsFile
        path: "/proc/swaps"
        onLoaded: {
            const lines = swapsFile.text().split("\n");
            let zTot = 0, zUsed = 0, fTot = 0, fUsed = 0;
            for (let i = 1; i < lines.length; i++) {
                const line = lines[i].trim();
                if (!line) continue;
                const cols = line.split(/\s+/);
                if (cols.length >= 4) {
                    const sz = parseInt(cols[2]) || 0;
                    const us = parseInt(cols[3]) || 0;
                    if (cols[0].indexOf("zram") >= 0) {
                        zTot += sz;
                        zUsed += us;
                    } else {
                        fTot += sz;
                        fUsed += us;
                    }
                }
            }
            root.zramTotalKiB = zTot;
            root.zramUsedKiB = zUsed;
            root.swapfileTotalKiB = fTot;
            root.swapfileUsedKiB = fUsed;
        }
    }

    FileView {
        id: tempFile
        path: ""
        onLoaded: {
            const v = parseInt(tempFile.text().trim());
            if (!isNaN(v) && v > 0) {
                root.cpuTempC = Math.round(v / 1000);
            }
        }
    }

    Timer {
        interval: 2500
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            memFile.reload();
            cpuFile.reload();
            loadFile.reload();
            swapsFile.reload();
            if (tempFile.path !== "") tempFile.reload();
            if (!agyCheckProc.running) agyCheckProc.running = true;
        }
    }

    Timer {
        id: closeGrace
        interval: 280
        onTriggered: {
            if (!pillHover.hovered && !popupHover.hovered && !launcherSegmentHover.hovered && !root.launcherHovered && !wsSegmentHover.hovered && !wsPopupHover.hovered && !mediaSegmentHover.hovered && !sysSegmentHover.hovered && !sysPopupHover.hovered && !termSegmentHover.hovered && !root.chatHovered) {
                root.expanded = false;
                root.wsPickerOpen = false;
                root.sysReportOpen = false;
                root.launcherOpen = false;
                if (!root.chatPinned) root.termOpen = false;
            } else {
                if (!launcherSegmentHover.hovered && !root.launcherHovered) root.launcherOpen = false;
                if (!wsSegmentHover.hovered && !wsPopupHover.hovered) root.wsPickerOpen = false;
                if (!mediaSegmentHover.hovered && !popupHover.hovered) root.expanded = false;
                if (!sysSegmentHover.hovered && !sysPopupHover.hovered) root.sysReportOpen = false;
                if (!termSegmentHover.hovered && !root.chatHovered && !root.chatPinned) root.termOpen = false;
            }
        }
    }

    TextMetrics {
        id: titleMetrics
        text: root.trackTitle || "Playing"
        font { family: Appearance.fontFamily; pixelSize: 13; weight: Font.DemiBold }
    }

    // ─── Frosted Glass Dynamic Island Pill ─────────────────────────
    Rectangle {
        id: glassPill
        anchors.centerIn: parent
        height: 26
        radius: 13
        width: root.hasMedia
            ? Math.min(520, Math.max(300, mainRow.implicitWidth + 26))
            : Math.max(200, mainRow.implicitWidth + 26)

        color: (root.expanded || root.wsPickerOpen || root.sysReportOpen || root.termOpen || root.launcherOpen)
            ? Qt.rgba(0.14, 0.14, 0.19, 0.74)
            : Qt.rgba(0.10, 0.10, 0.14, 0.52)
        border.color: (root.expanded || root.wsPickerOpen || root.sysReportOpen || root.termOpen || root.launcherOpen)
            ? Qt.rgba(1, 1, 1, 0.30)
            : Qt.rgba(1, 1, 1, 0.20)
        border.width: 1
        clip: true

        Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: 150 } }
        Behavior on border.color { ColorAnimation { duration: 150 } }

        // Top glass sheen matching Dock
        Rectangle {
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 1 }
            height: parent.height * 0.5
            radius: 12
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.14) }
                GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.0) }
            }
        }

        HoverHandler {
            id: pillHover
            onHoveredChanged: {
                if (hovered) {
                    closeGrace.stop();
                    // Media popup hanya muncul saat hover di bagian media (line 515)
                } else {
                    closeGrace.restart();
                }
            }
        }

        // Unified Pill Row: [Launcher] | [WS] | ([equalizer + title] |) [CPU% RAM% SWAP%]
        Row {
            id: mainRow
            anchors.centerIn: parent
            spacing: 10

            // 0. App Launcher (Native 3x3 Launchpad Grid)
            Item {
                id: launcherSegment
                width: 22
                height: 22
                anchors.verticalCenter: parent.verticalCenter

                Grid {
                    anchors.centerIn: parent
                    columns: 3
                    spacing: 2
                    Repeater {
                        model: 9
                        delegate: Rectangle {
                            required property int index
                            width: 3
                            height: 3
                            radius: 1.5
                            color: (launcherMa.containsMouse || root.launcherOpen)
                                ? (index % 3 === 0 ? "#64d2ff" : (index % 3 === 1 ? "#a78bfa" : "#ffffff"))
                                : "#d1d1d6"
                            Behavior on color { ColorAnimation { duration: 120 } }
                        }
                    }
                }

                HoverHandler {
                    id: launcherSegmentHover
                    onHoveredChanged: {
                        if (hovered) {
                            closeGrace.stop();
                            root.wsPickerOpen = false;
                            root.expanded = false;
                            root.sysReportOpen = false;
                            if (!root.chatPinned) root.termOpen = false;
                            root.launcherOpen = true;
                        } else {
                            closeGrace.restart();
                        }
                    }
                }

                MouseArea {
                    id: launcherMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.wsPickerOpen = false;
                        root.expanded = false;
                        root.sysReportOpen = false;
                        if (!root.chatPinned) root.termOpen = false;
                        root.launcherOpen = !root.launcherOpen;
                    }
                }
            }

            Rectangle {
                width: 1; height: 13
                anchors.verticalCenter: parent.verticalCenter
                color: Qt.rgba(1, 1, 1, 0.20)
            }

            // 1. Active Workspace Wrapper
            Item {
                id: wsSegment
                width: wsRow.implicitWidth + 6
                height: 22
                anchors.verticalCenter: parent.verticalCenter

                Row {
                    id: wsRow
                    anchors.centerIn: parent
                    spacing: 5

                    Rectangle {
                        width: 7; height: 7; radius: 3.5
                        anchors.verticalCenter: parent.verticalCenter
                        color: "#0A84FF"
                    }

                    Text {
                        text: root.toRoman(root.activeWs)
                        font { family: Appearance.fontFamily; pixelSize: 13; weight: Font.DemiBold }
                        color: wsBtnMa.containsMouse ? "#ffffff" : "#f5f5f7"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                HoverHandler {
                    id: wsSegmentHover
                    onHoveredChanged: {
                        if (hovered) {
                            closeGrace.stop();
                            root.launcherOpen = false;
                            root.expanded = false;
                            root.sysReportOpen = false;
                            if (!root.chatPinned) root.termOpen = false;
                            root.wsPickerOpen = true;
                        } else {
                            closeGrace.restart();
                        }
                    }
                }

                MouseArea {
                    id: wsBtnMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.launcherOpen = false;
                        root.sysReportOpen = false;
                        root.expanded = false;
                        if (!root.chatPinned) root.termOpen = false;
                        root.wsPickerOpen = !root.wsPickerOpen;
                    }
                    onWheel: (wheel) => {
                        if (wheel.angleDelta.y > 0)
                            Hyprland.dispatch('hl.dsp.focus({ workspace = "-1" })');
                        else if (wheel.angleDelta.y < 0)
                            Hyprland.dispatch('hl.dsp.focus({ workspace = "+1" })');
                    }
                }
            }

            Rectangle {
                width: 1; height: 13
                anchors.verticalCenter: parent.verticalCenter
                color: Qt.rgba(1, 1, 1, 0.20)
            }

            // 2. Media Segment (only visible when media active; hover opens media controls)
            Item {
                id: mediaSegment
                visible: root.hasMedia
                width: visible ? mediaInnerRow.implicitWidth + 6 : 0
                height: 22
                anchors.verticalCenter: parent.verticalCenter

                Row {
                    id: mediaInnerRow
                    anchors.centerIn: parent
                    spacing: 7

                    Row {
                        spacing: 2
                        anchors.verticalCenter: parent.verticalCenter
                        Repeater {
                            model: 3
                            delegate: Rectangle {
                                width: 2.5
                                height: root.isPlaying ? (index === 1 ? 11 : 7) : 3
                                radius: 1.25
                                anchors.verticalCenter: parent.verticalCenter
                                color: root.isPlaying ? "#30d158" : "#8e8e93"
                                SequentialAnimation on height {
                                    running: root.isPlaying && root.hasMedia
                                    loops: Animation.Infinite
                                    NumberAnimation { to: 12; duration: 280 + index * 90 }
                                    NumberAnimation { to: 4; duration: 280 + index * 90 }
                                }
                            }
                        }
                    }

                    Item {
                        width: Math.min(130, Math.max(40, titleMetrics.implicitWidth))
                        height: 20
                        anchors.verticalCenter: parent.verticalCenter

                        Text {
                            anchors.fill: parent
                            text: root.trackTitle || "Playing"
                            font { family: Appearance.fontFamily; pixelSize: 13; weight: Font.DemiBold }
                            color: "#f5f5f7"
                            elide: Text.ElideRight
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }

                HoverHandler {
                    id: mediaSegmentHover
                    onHoveredChanged: {
                        if (hovered) {
                            closeGrace.stop();
                            root.launcherOpen = false;
                            root.wsPickerOpen = false;
                            root.sysReportOpen = false;
                            if (!root.chatPinned) root.termOpen = false;
                            if (root.hasMedia) root.expanded = true;
                        } else {
                            closeGrace.restart();
                        }
                    }
                }
            }

            Rectangle {
                visible: root.hasMedia
                width: 1; height: 13
                anchors.verticalCenter: parent.verticalCenter
                color: Qt.rgba(1, 1, 1, 0.20)
            }

            // 3. Icon-Only Live Telemetry Wrapper (always visible; hover for report, click for btop)
            Item {
                id: sysSegment
                width: sysRow.implicitWidth + 8
                height: 22
                anchors.verticalCenter: parent.verticalCenter

                Row {
                    id: sysRow
                    anchors.centerIn: parent
                    spacing: 9

                    // CPU
                    Row {
                        spacing: 4
                        anchors.verticalCenter: parent.verticalCenter
                        Text {
                            text: "\uF2DB"
                            font { family: "JetBrainsMono Nerd Font"; pixelSize: 12 }
                            color: root.levelColor(root.cpuPct, "#64d2ff")
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: root.cpuPct + "%"
                            font { family: Appearance.fontFamily; pixelSize: 13; weight: Font.DemiBold }
                            color: root.cpuPct >= 85 ? "#ff453a" : (sysMa.containsMouse ? "#ffffff" : "#f5f5f7")
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    // RAM
                    Row {
                        spacing: 4
                        anchors.verticalCenter: parent.verticalCenter
                        Text {
                            text: "\uEFC5"
                            font { family: "JetBrainsMono Nerd Font"; pixelSize: 12 }
                            color: root.levelColor(root.memPct, "#30d158")
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: root.memPct + "%"
                            font { family: Appearance.fontFamily; pixelSize: 13; weight: Font.DemiBold }
                            color: root.memPct >= 85 ? "#ff453a" : (sysMa.containsMouse ? "#ffffff" : "#f5f5f7")
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    // Swap / ZRAM
                    Row {
                        spacing: 4
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.swapTotalKiB > 0
                        Text {
                            text: "\uF0EC"
                            font { family: "JetBrainsMono Nerd Font"; pixelSize: 12 }
                            color: root.levelColor(root.swapPct, "#bf5af2")
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: root.swapPct + "%"
                            font { family: Appearance.fontFamily; pixelSize: 13; weight: Font.DemiBold }
                            color: root.swapPct >= 85 ? "#ff453a" : (sysMa.containsMouse ? "#ffffff" : "#f5f5f7")
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }

                HoverHandler {
                    id: sysSegmentHover
                    onHoveredChanged: {
                        if (hovered) {
                            closeGrace.stop();
                            root.launcherOpen = false;
                            root.wsPickerOpen = false;
                            root.expanded = false;
                            if (!root.chatPinned) root.termOpen = false;
                            root.sysReportOpen = true;
                        } else {
                            closeGrace.restart();
                        }
                    }
                }

                MouseArea {
                    id: sysMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.openBtop()
                }
            }

            Rectangle {
                width: 1; height: 13
                anchors.verticalCenter: parent.verticalCenter
                color: Qt.rgba(1, 1, 1, 0.20)
            }

            // 4. Agy / Quick Terminal Segment (hover for popup, click to focus agy or open kitty)
            Item {
                id: termSegment
                width: termIconText.implicitWidth + 6
                height: 22
                anchors.verticalCenter: parent.verticalCenter

                Text {
                    id: termIconText
                    anchors.centerIn: parent
                    text: "\uF120"
                    font { family: "JetBrainsMono Nerd Font"; pixelSize: 13 }
                    color: root.agyRunning ? "#30d158" : (termMa.containsMouse ? "#ffffff" : "#d1d1d6")
                }

                HoverHandler {
                    id: termSegmentHover
                    onHoveredChanged: {
                        if (hovered) {
                            closeGrace.stop();
                            root.launcherOpen = false;
                            root.wsPickerOpen = false;
                            root.expanded = false;
                            root.sysReportOpen = false;
                            root.termOpen = true;
                        } else {
                            closeGrace.restart();
                        }
                    }
                }

                MouseArea {
                    id: termMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.launcherOpen = false;
                        if (root.termOpen) root.closeChatPopup();
                        else root.termOpen = true;
                    }
                }
            }
        }
    }

    // ─── App Launcher Glass Dropdown (LazyLoader, unloads icons) ─
    LazyLoader {
        id: launcherPopupLoader
        active: root.launcherOpen && !root.wsPickerOpen
        onActiveChanged: {
            if (active) {
                if (!Apps.ready || Apps.apps.length === 0) Apps.refresh();
                root.launcherQuery = "";
            } else {
                root.launcherHovered = false;
                root.launcherQuery = "";
                gc();
            }
        }

        component: PanelWindow {
            id: launcherPopup
            visible: true
            color: "transparent"
            screen: root.hostWindow ? root.hostWindow.screen : null

            anchors.top: true
            margins.top: Appearance.barHeight + 8
            exclusionMode: ExclusionMode.Ignore

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "macos:island-launcher"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

            implicitWidth: 404
            implicitHeight: 384

            Rectangle {
                anchors.fill: parent
                radius: 20
                color: Qt.rgba(0.10, 0.10, 0.13, 0.92)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.16)
                clip: true

                // Top glass sheen
                Rectangle {
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 1 }
                    height: 40
                    radius: 19
                    z: 0
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.10) }
                        GradientStop { position: 1.0; color: "transparent" }
                    }
                }

                HoverHandler {
                    onHoveredChanged: {
                        root.launcherHovered = hovered;
                        if (hovered) closeGrace.stop();
                        else closeGrace.restart();
                    }
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 10
                    z: 1

                    // Search bar + optional Rofi button
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 32
                            radius: 16
                            color: Qt.rgba(1, 1, 1, 0.08)
                            border.width: 1
                            border.color: launcherSearchInput.activeFocus ? Qt.rgba(0.04, 0.52, 1.0, 0.8) : Qt.rgba(1, 1, 1, 0.14)

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.IBeamCursor
                                onClicked: launcherSearchInput.forceActiveFocus()
                            }

                            Text {
                                anchors { fill: parent; leftMargin: 12; rightMargin: 28 }
                                verticalAlignment: Text.AlignVCenter
                                text: "Cari aplikasi..."
                                font { family: Appearance.fontFamily; pixelSize: 12 }
                                color: "#636366"
                                visible: launcherSearchInput.text.length === 0
                            }

                            TextInput {
                                id: launcherSearchInput
                                anchors { fill: parent; leftMargin: 12; rightMargin: 28 }
                                verticalAlignment: TextInput.AlignVCenter
                                color: "#ffffff"
                                font { family: Appearance.fontFamily; pixelSize: 12 }
                                clip: true
                                onTextEdited: root.launcherQuery = text
                                Keys.onEscapePressed: root.launcherOpen = false
                                onAccepted: {
                                    if (root.filteredApps.length > 0)
                                        root.launchAppEntry(root.filteredApps[0].exec);
                                }
                            }

                            Rectangle {
                                visible: launcherSearchInput.text.length > 0
                                width: 18; height: 18; radius: 9
                                anchors { right: parent.right; rightMargin: 7; verticalCenter: parent.verticalCenter }
                                color: clearSearchMa.containsMouse ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.12)
                                Text {
                                    anchors.centerIn: parent
                                    text: "×"
                                    font { family: Appearance.fontFamily; pixelSize: 12; weight: Font.Bold }
                                    color: "#e5e5ea"
                                }
                                MouseArea {
                                    id: clearSearchMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        launcherSearchInput.text = "";
                                        root.launcherQuery = "";
                                        launcherSearchInput.forceActiveFocus();
                                    }
                                }
                            }
                        }

                        Rectangle {
                            width: rofiLbl.implicitWidth + 18
                            height: 32
                            radius: 16
                            color: rofiBtnMa.containsMouse ? Qt.rgba(0.04, 0.52, 1.0, 0.35) : Qt.rgba(1, 1, 1, 0.08)
                            border.width: 1
                            border.color: rofiBtnMa.containsMouse ? Qt.rgba(0.04, 0.52, 1.0, 0.60) : Qt.rgba(1, 1, 1, 0.12)
                            Text {
                                id: rofiLbl
                                anchors.centerIn: parent
                                text: "Rofi"
                                font { family: Appearance.fontFamily; pixelSize: 11; weight: Font.Medium }
                                color: "#e5e5ea"
                            }
                            MouseArea {
                                id: rofiBtnMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.openRofiLauncher()
                            }
                        }
                    }

                    // Loading state
                    Item {
                        visible: !Apps.ready && root.filteredApps.length === 0
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Text {
                            anchors.centerIn: parent
                            text: "Memuat aplikasi..."
                            font { family: Appearance.fontFamily; pixelSize: 12 }
                            color: "#8e8e93"
                        }
                    }

                    // Empty state
                    Item {
                        visible: Apps.ready && root.filteredApps.length === 0
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 10
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: "Aplikasi tidak ditemukan"
                                font { family: Appearance.fontFamily; pixelSize: 12 }
                                color: "#8e8e93"
                            }
                            Rectangle {
                                Layout.alignment: Qt.AlignHCenter
                                width: resetSearchLbl.implicitWidth + 22
                                height: 26
                                radius: 13
                                color: resetSearchMa.containsMouse ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.08)
                                border.width: 1
                                border.color: Qt.rgba(1, 1, 1, 0.12)
                                Text {
                                    id: resetSearchLbl
                                    anchors.centerIn: parent
                                    text: "Reset Pencarian"
                                    font { family: Appearance.fontFamily; pixelSize: 11; weight: Font.Medium }
                                    color: "#e5e5ea"
                                }
                                MouseArea {
                                    id: resetSearchMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        launcherSearchInput.text = "";
                                        root.launcherQuery = "";
                                        launcherSearchInput.forceActiveFocus();
                                    }
                                }
                            }
                        }
                    }

                    // App grid (4 columns)
                    GridView {
                        id: appGrid
                        visible: root.filteredApps.length > 0
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        cacheBuffer: 84
                        cellWidth: Math.max(70, Math.floor(width / 4))
                        cellHeight: 84
                        boundsBehavior: Flickable.StopAtBounds
                        model: root.filteredApps

                        delegate: Item {
                            required property var modelData
                            width: appGrid.cellWidth
                            height: appGrid.cellHeight

                            Rectangle {
                                anchors { fill: parent; margins: 3 }
                                radius: 12
                                color: appItemMa.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : "transparent"
                                Behavior on color { ColorAnimation { duration: 100 } }

                                ColumnLayout {
                                    anchors { fill: parent; margins: 6 }
                                    spacing: 5

                                    Item {
                                        Layout.alignment: Qt.AlignHCenter
                                        width: 38
                                        height: 38

                                        Rectangle {
                                            visible: appImg.status !== Image.Ready
                                            anchors.fill: parent
                                            radius: 10
                                            color: Qt.rgba(0.04, 0.52, 1.0, 0.25)
                                            border.width: 1
                                            border.color: Qt.rgba(0.04, 0.52, 1.0, 0.40)
                                            Text {
                                                anchors.centerIn: parent
                                                text: (modelData.name || "?").slice(0, 1).toUpperCase()
                                                font { family: Appearance.fontFamily; pixelSize: 16; weight: Font.Bold }
                                                color: "#ffffff"
                                            }
                                        }

                                        Image {
                                            id: appImg
                                            anchors.fill: parent
                                            fillMode: Image.PreserveAspectFit
                                            sourceSize: Qt.size(38, 38)
                                            asynchronous: true
                                            cache: false
                                            smooth: true
                                            source: modelData.icon
                                                ? (modelData.icon.indexOf("/") === 0 ? "file://" + modelData.icon : modelData.icon)
                                                : ""
                                        }
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.name || ""
                                        elide: Text.ElideRight
                                        horizontalAlignment: Text.AlignHCenter
                                        font { family: Appearance.fontFamily; pixelSize: 11; weight: Font.Medium }
                                        color: "#f5f5f7"
                                    }
                                }

                                MouseArea {
                                    id: appItemMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.launchAppEntry(modelData.exec)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ─── Quick Workspace Picker Popup (on WS hover/click) ──────────
    PopupWindow {
        id: wsPopup
        visible: root.wsPickerOpen && !root.launcherOpen
        color: "transparent"

        anchor.window: root.hostWindow
        anchor.rect.x: root.hostWindow ? Math.round((root.hostWindow.width - implicitWidth) / 2) : 0
        anchor.rect.y: Appearance.barHeight + 4

        implicitWidth: 224
        implicitHeight: 54

        Rectangle {
            anchors.fill: parent
            radius: 14
            color: Qt.rgba(0.10, 0.10, 0.14, 0.88)
            border.color: Qt.rgba(1, 1, 1, 0.20)
            border.width: 1

            HoverHandler {
                id: wsPopupHover
                onHoveredChanged: {
                    if (hovered) closeGrace.stop();
                    else closeGrace.restart();
                }
            }

            WheelHandler {
                onWheel: (wheel) => {
                    if (wheel.angleDelta.y > 0)
                        Hyprland.dispatch('hl.dsp.focus({ workspace = "-1" })');
                    else if (wheel.angleDelta.y < 0)
                        Hyprland.dispatch('hl.dsp.focus({ workspace = "+1" })');
                }
            }

            RowLayout {
                anchors.centerIn: parent
                spacing: 6

                Repeater {
                    model: 5
                    delegate: Rectangle {
                        required property int index
                        readonly property int wsId: index + 1
                        readonly property bool isCur: root.activeWs === wsId
                        Layout.preferredWidth: 34
                        Layout.preferredHeight: 28
                        radius: 9
                        color: isCur ? "#0A84FF" : (wsMa.containsMouse ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.08))

                        Text {
                            anchors.centerIn: parent
                            text: root.toRoman(wsId)
                            font { family: Appearance.fontFamily; pixelSize: 13; weight: Font.Bold }
                            color: "#ffffff"
                        }

                        MouseArea {
                            id: wsMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                Hyprland.dispatch("hl.dsp.focus({ workspace = " + wsId + " })");
                                root.wsPickerOpen = false;
                            }
                        }
                    }
                }
            }
        }
    }

    // ─── Floating System Report Popup (on telemetry hover) ─────────
    PopupWindow {
        id: sysPopup
        visible: root.sysReportOpen && !root.wsPickerOpen && !root.launcherOpen
        color: "transparent"

        anchor.window: root.hostWindow
        anchor.rect.x: root.hostWindow ? Math.round((root.hostWindow.width - implicitWidth) / 2) : 0
        anchor.rect.y: Appearance.barHeight + 4

        implicitWidth: 316
        implicitHeight: sysCardCol.implicitHeight + 28

        Rectangle {
            anchors.fill: parent
            radius: 16
            color: Qt.rgba(0.10, 0.10, 0.14, 0.90)
            border.color: Qt.rgba(1, 1, 1, 0.20)
            border.width: 1
            clip: true

            // Top glass sheen
            Rectangle {
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 1 }
                height: 28
                radius: 15
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.10) }
                    GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.0) }
                }
            }

            HoverHandler {
                id: sysPopupHover
                onHoveredChanged: {
                    if (hovered) closeGrace.stop();
                    else closeGrace.restart();
                }
            }

            ColumnLayout {
                id: sysCardCol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                spacing: 10

                // Header
                RowLayout {
                    Layout.fillWidth: true

                    Text {
                        text: "System Monitor"
                        font { family: Appearance.fontFamily; pixelSize: 13; weight: Font.Bold }
                        color: "#ffffff"
                    }

                    Item { Layout.fillWidth: true }

                    Rectangle {
                        Layout.preferredWidth: btopBtnRow.implicitWidth + 14
                        Layout.preferredHeight: 22
                        radius: 11
                        color: btopBtnMa.containsMouse ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.11)
                        border.color: Qt.rgba(1, 1, 1, 0.16)
                        border.width: 1

                        Row {
                            id: btopBtnRow
                            anchors.centerIn: parent
                            spacing: 5

                            Text {
                                text: "\uF120"
                                font { family: "JetBrainsMono Nerd Font"; pixelSize: 11 }
                                color: "#64d2ff"
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Text {
                                text: "btop"
                                font { family: Appearance.fontFamily; pixelSize: 11; weight: Font.DemiBold }
                                color: "#f5f5f7"
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        MouseArea {
                            id: btopBtnMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.openBtop()
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: Qt.rgba(1, 1, 1, 0.10)
                }

                // CPU Block
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    RowLayout {
                        Layout.fillWidth: true

                        Row {
                            spacing: 6
                            Text {
                                text: "\uF2DB"
                                font { family: "JetBrainsMono Nerd Font"; pixelSize: 13 }
                                color: root.levelColor(root.cpuPct, "#64d2ff")
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: "CPU"
                                font { family: Appearance.fontFamily; pixelSize: 12; weight: Font.DemiBold }
                                color: "#f5f5f7"
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        Item { Layout.fillWidth: true }

                        Row {
                            spacing: 5
                            Text {
                                text: root.cpuPct + "%"
                                font { family: Appearance.fontFamily; pixelSize: 12; weight: Font.DemiBold }
                                color: "#ffffff"
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: "·"
                                font { family: Appearance.fontFamily; pixelSize: 12 }
                                color: "#8e8e93"
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: "\uF2C9"
                                font { family: "JetBrainsMono Nerd Font"; pixelSize: 12 }
                                color: root.cpuTempC >= 80 ? "#ff453a" : (root.cpuTempC >= 65 ? "#ff9f0a" : "#98989f")
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: root.cpuTempC >= 0 ? (root.cpuTempC + "°C") : "--°C"
                                font { family: Appearance.fontFamily; pixelSize: 12; weight: Font.DemiBold }
                                color: root.cpuTempC >= 80 ? "#ff453a" : (root.cpuTempC >= 65 ? "#ff9f0a" : "#d1d1d6")
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 5
                        radius: 2.5
                        color: Qt.rgba(1, 1, 1, 0.10)

                        Rectangle {
                            width: Math.max(0, Math.min(parent.width, parent.width * (root.cpuPct / 100.0)))
                            height: parent.height
                            radius: 2.5
                            color: root.levelColor(root.cpuPct, "#64d2ff")
                            Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: "Load: " + root.loadAvg
                        font { family: Appearance.fontFamily; pixelSize: 11 }
                        color: "#98989f"
                        elide: Text.ElideRight
                    }
                }

                // RAM Block
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    RowLayout {
                        Layout.fillWidth: true

                        Row {
                            spacing: 6
                            Text {
                                text: "\uEFC5"
                                font { family: "JetBrainsMono Nerd Font"; pixelSize: 13 }
                                color: root.levelColor(root.memPct, "#30d158")
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: "RAM"
                                font { family: Appearance.fontFamily; pixelSize: 12; weight: Font.DemiBold }
                                color: "#f5f5f7"
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        Item { Layout.fillWidth: true }

                        Text {
                            text: root.memTotalKiB > 0
                                ? (root.fmtSize(root.memUsedKiB) + " / " + root.fmtSize(root.memTotalKiB) + " (" + root.memPct + "%)")
                                : "Loading..."
                            font { family: Appearance.fontFamily; pixelSize: 12; weight: Font.DemiBold }
                            color: "#e5e5ea"
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 5
                        radius: 2.5
                        color: Qt.rgba(1, 1, 1, 0.10)

                        Rectangle {
                            width: Math.max(0, Math.min(parent.width, parent.width * (root.memPct / 100.0)))
                            height: parent.height
                            radius: 2.5
                            color: root.levelColor(root.memPct, "#30d158")
                            Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: "Tersedia: " + root.fmtSize(root.memAvailKiB)
                        font { family: Appearance.fontFamily; pixelSize: 11 }
                        color: "#98989f"
                        elide: Text.ElideRight
                    }
                }

                // Swap & ZRAM Block
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    RowLayout {
                        Layout.fillWidth: true

                        Row {
                            spacing: 6
                            Text {
                                text: "\uF0EC"
                                font { family: "JetBrainsMono Nerd Font"; pixelSize: 13 }
                                color: root.levelColor(root.swapPct, "#bf5af2")
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: "Swap & ZRAM"
                                font { family: Appearance.fontFamily; pixelSize: 12; weight: Font.DemiBold }
                                color: "#f5f5f7"
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        Item { Layout.fillWidth: true }

                        Text {
                            text: root.swapTotalKiB > 0
                                ? (root.fmtSize(root.swapUsedKiB) + " / " + root.fmtSize(root.swapTotalKiB) + " (" + root.swapPct + "%)")
                                : "Tidak aktif"
                            font { family: Appearance.fontFamily; pixelSize: 12; weight: Font.DemiBold }
                            color: "#e5e5ea"
                        }
                    }

                    Rectangle {
                        visible: root.swapTotalKiB > 0
                        Layout.fillWidth: true
                        Layout.preferredHeight: 5
                        radius: 2.5
                        color: Qt.rgba(1, 1, 1, 0.10)

                        Rectangle {
                            width: Math.max(0, Math.min(parent.width, parent.width * (root.swapPct / 100.0)))
                            height: parent.height
                            radius: 2.5
                            color: root.levelColor(root.swapPct, "#bf5af2")
                            Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: root.swapBreakdownText()
                        font { family: Appearance.fontFamily; pixelSize: 11 }
                        color: "#98989f"
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }

    // ─── ArchLinux AI Chat UI Component (shared by Hover & Pinned) ─
    Component {
        id: chatCardComponent

        Rectangle {
            id: chatCard
            property var dragWindow: null

            anchors.fill: parent
            radius: 22
            color: Qt.rgba(0.10, 0.10, 0.13, 0.90)
            border.width: 1
            border.color: root.chatPinned ? Qt.rgba(0.996, 0.737, 0.180, 0.45) : Qt.rgba(1, 1, 1, 0.16)
            clip: true

            // Top glass sheen
            Rectangle {
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 1 }
                height: 42
                radius: 21
                z: 0
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.10) }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }

            HoverHandler {
                onHoveredChanged: {
                    root.chatHovered = hovered;
                    if (hovered) closeGrace.stop();
                    else if (!root.chatPinned) closeGrace.restart();
                }
            }

            // Direct drag on empty card background when pinned
            MouseArea {
                anchors.fill: parent
                z: 0
                acceptedButtons: Qt.LeftButton
                cursorShape: chatCard.dragWindow ? Qt.OpenHandCursor : Qt.ArrowCursor
                onPressed: {
                    if (chatCard.dragWindow) chatCard.dragWindow.startSystemMove();
                }
            }

            ColumnLayout {
                id: termCol
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12
                z: 1

                // macOS-style Header with Traffic Lights (-, =, o)
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Row {
                        id: trafficLights
                        spacing: 8
                        Layout.alignment: Qt.AlignVCenter

                        HoverHandler { id: trafficHover }

                        // Red (-): Close popup
                        Rectangle {
                            width: 14; height: 14; radius: 7
                            color: redMa.containsMouse ? "#FF6E67" : "#FF5F57"
                            border.width: 0.5
                            border.color: Qt.rgba(0, 0, 0, 0.22)

                            HoverHandler { id: redHover }
                            Text {
                                anchors.centerIn: parent
                                text: "-"
                                font { family: Appearance.fontFamily; pixelSize: 12; weight: Font.Bold }
                                color: Qt.rgba(0, 0, 0, 0.65)
                                opacity: trafficHover.hovered ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: 120 } }
                            }
                            MouseArea {
                                id: redMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.closeChatPopup()
                            }
                        }

                        // Yellow (=): Pin / Tahan until closed with -
                        Rectangle {
                            width: 14; height: 14; radius: 7
                            color: yellowMa.containsMouse ? "#FFC84A" : "#FEBC2E"
                            border.width: root.chatPinned ? 1.5 : 0.5
                            border.color: root.chatPinned ? "#FFF4CC" : Qt.rgba(0, 0, 0, 0.22)

                            HoverHandler { id: yellowHover }
                            Text {
                                anchors.centerIn: parent
                                text: "="
                                font { family: Appearance.fontFamily; pixelSize: 10; weight: Font.Bold }
                                color: Qt.rgba(0, 0, 0, 0.70)
                                opacity: (trafficHover.hovered || root.chatPinned) ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: 120 } }
                            }
                            MouseArea {
                                id: yellowMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.chatPinned = !root.chatPinned;
                                    if (root.chatPinned) {
                                        closeGrace.stop();
                                        root.chatHovered = false;
                                    }
                                }
                            }
                        }

                        // Green (o): Expand / Pop-out to full agy terminal
                        Rectangle {
                            width: 14; height: 14; radius: 7
                            color: greenMa.containsMouse ? "#38D850" : "#28C840"
                            border.width: 0.5
                            border.color: Qt.rgba(0, 0, 0, 0.22)

                            HoverHandler { id: greenHover }
                            Text {
                                anchors.centerIn: parent
                                text: "o"
                                font { family: Appearance.fontFamily; pixelSize: 10; weight: Font.Bold }
                                color: Qt.rgba(0, 0, 0, 0.65)
                                opacity: trafficHover.hovered ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: 120 } }
                            }
                            MouseArea {
                                id: greenMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.expandAgyToTerminal()
                            }
                        }
                    }

                    // Header title & live status (draggable when pinned)
                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 22

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton
                            cursorShape: chatCard.dragWindow ? Qt.OpenHandCursor : Qt.ArrowCursor
                            onPressed: {
                                if (chatCard.dragWindow) chatCard.dragWindow.startSystemMove();
                            }
                        }

                        RowLayout {
                            anchors.fill: parent
                            spacing: 6

                            Rectangle {
                                width: 7; height: 7; radius: 4
                                color: root.chatLoading ? "#ffd60a" : (root.agyRunning ? "#30d158" : "#8e8e93")
                            }
                            Text {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: {
                                    if (redHover.hovered) return "Tutup";
                                    if (yellowHover.hovered) return root.chatPinned ? "Lepas Pin" : "Tahan (Pin)";
                                    if (greenHover.hovered) return "Buka Terminal Penuh";
                                    if (root.chatLoading) return "ArchLinux AI · Thinking...";
                                    return "ArchLinux AI Chat";
                                }
                                font { family: Appearance.fontFamily; pixelSize: 13; weight: Font.DemiBold }
                                color: "#f5f5f7"
                            }
                            Rectangle {
                                visible: root.chatPinned
                                width: pinLbl.implicitWidth + 12
                                height: 18
                                radius: 9
                                color: Qt.rgba(0.996, 0.737, 0.180, 0.20)
                                border.width: 1
                                border.color: Qt.rgba(0.996, 0.737, 0.180, 0.45)
                                Text {
                                    id: pinLbl
                                    anchors.centerIn: parent
                                    text: "Pinned"
                                    font { family: Appearance.fontFamily; pixelSize: 10; weight: Font.Medium }
                                    color: "#FEBC2E"
                                }
                            }
                        }
                    }

                    Rectangle {
                        width: 56; height: 22; radius: 11
                        color: root.resumeMode
                            ? Qt.rgba(0.04, 0.52, 1.0, 0.35)
                            : (histMa.containsMouse ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.08))
                        Text {
                            anchors.centerIn: parent
                            text: root.resumeMode ? "Back" : "History"
                            font { family: Appearance.fontFamily; pixelSize: 10; weight: Font.Medium }
                            color: "#e5e5ea"
                        }
                        MouseArea {
                            id: histMa
                            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.resumeMode) root.resumeMode = false;
                                else root.openResumePicker();
                            }
                        }
                    }

                    Rectangle {
                        visible: root.chatMessages.length > 0 || root.activeConversationId !== "" || root.chatError !== ""
                        width: 44; height: 22; radius: 11
                        color: clearChatMa.containsMouse ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.08)
                        Text {
                            anchors.centerIn: parent
                            text: "Clear"
                            font { family: Appearance.fontFamily; pixelSize: 10; weight: Font.Medium }
                            color: "#aeaeb2"
                        }
                        MouseArea {
                            id: clearChatMa
                            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.chatMessages = [];
                                root.activeConversationId = "";
                                root.resumeMode = false;
                                root.chatError = "";
                                root.lastFailedPrompt = "";
                                root.chatDraft = "";
                                chatInput.text = "";
                            }
                        }
                    }
                }

                // Segmented Terminal Quick Actions
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 30
                    radius: 10
                    color: Qt.rgba(1, 1, 1, 0.06)
                    border.color: Qt.rgba(1, 1, 1, 0.08)
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 3
                        spacing: 4

                        Rectangle {
                            Layout.fillWidth: true; Layout.fillHeight: true; radius: 7
                            color: goAgyMa.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : "transparent"
                            Text {
                                anchors.centerIn: parent
                                text: "Go to agy Terminal"
                                font { family: Appearance.fontFamily; pixelSize: 11; weight: Font.Medium }
                                color: "#e5e5ea"
                            }
                            MouseArea {
                                id: goAgyMa
                                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: root.focusAgyOrNew()
                            }
                        }

                        Rectangle {
                            width: 1; Layout.fillHeight: true; Layout.topMargin: 4; Layout.bottomMargin: 4
                            color: Qt.rgba(1, 1, 1, 0.10)
                        }

                        Rectangle {
                            Layout.fillWidth: true; Layout.fillHeight: true; radius: 7
                            color: newAgyMa.containsMouse ? Qt.rgba(0.04, 0.52, 1.0, 0.35) : "transparent"
                            Text {
                                anchors.centerIn: parent
                                text: "New agy Terminal"
                                font { family: Appearance.fontFamily; pixelSize: 11; weight: Font.Medium }
                                color: newAgyMa.containsMouse ? "#ffffff" : "#64d2ff"
                            }
                            MouseArea {
                                id: newAgyMa
                                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: root.newAgyTerminal()
                            }
                        }
                    }
                }

                // Resume History Picker
                Flickable {
                    visible: root.resumeMode
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    contentHeight: histCol.implicitHeight

                    ColumnLayout {
                        id: histCol
                        width: parent.width
                        spacing: 6

                        Text {
                            text: "Pilih session untuk /resume:"
                            font { family: Appearance.fontFamily; pixelSize: 11; weight: Font.Medium }
                            color: "#8e8e93"
                        }

                        Text {
                            visible: root.historyList.length === 0
                            text: "Belum ada riwayat session."
                            font { family: Appearance.fontFamily; pixelSize: 12 }
                            color: "#636366"
                            Layout.topMargin: 24
                            Layout.alignment: Qt.AlignHCenter
                        }

                        Repeater {
                            model: root.historyList
                            delegate: Rectangle {
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.preferredHeight: 38
                                radius: 10
                                color: histItemMa.containsMouse ? Qt.rgba(0.04, 0.52, 1.0, 0.25) : Qt.rgba(1, 1, 1, 0.06)
                                border.color: root.activeConversationId === modelData.id ? Qt.rgba(0.04, 0.52, 1.0, 0.6) : Qt.rgba(1, 1, 1, 0.08)
                                border.width: 1

                                RowLayout {
                                    anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                                    spacing: 8
                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.title
                                        elide: Text.ElideRight
                                        font { family: Appearance.fontFamily; pixelSize: 12; weight: Font.Medium }
                                        color: "#f5f5f7"
                                    }
                                    Text {
                                        text: modelData.time
                                        font { family: Appearance.fontFamily; pixelSize: 10 }
                                        color: "#8e8e93"
                                    }
                                }

                                MouseArea {
                                    id: histItemMa
                                    anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.activeConversationId = modelData.id;
                                        root.resumeMode = false;
                                        root.loadSessionMessages(modelData.id);
                                    }
                                }
                            }
                        }
                    }
                }

                // Chat history
                Flickable {
                    id: chatFlick
                    visible: !root.resumeMode
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    contentHeight: chatListCol.implicitHeight
                    onContentHeightChanged: {
                        if (contentHeight > height) contentY = contentHeight - height;
                    }

                    ColumnLayout {
                        id: chatListCol
                        width: chatFlick.width
                        spacing: 8

                        // Empty state with next action
                        ColumnLayout {
                            visible: root.chatMessages.length === 0 && !root.chatLoading
                            Layout.fillWidth: true
                            Layout.topMargin: 44
                            spacing: 10

                            Text {
                                text: "Tanya sesuatu untuk mulai"
                                font { family: Appearance.fontFamily; pixelSize: 12 }
                                color: "#8e8e93"
                                Layout.alignment: Qt.AlignHCenter
                            }

                            Rectangle {
                                Layout.alignment: Qt.AlignHCenter
                                width: emptyHistLbl.implicitWidth + 24
                                height: 26
                                radius: 13
                                color: emptyHistMa.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.08)
                                border.width: 1
                                border.color: Qt.rgba(1, 1, 1, 0.12)
                                Text {
                                    id: emptyHistLbl
                                    anchors.centerIn: parent
                                    text: "Buka History (/resume)"
                                    font { family: Appearance.fontFamily; pixelSize: 11; weight: Font.Medium }
                                    color: "#d1d1d6"
                                }
                                MouseArea {
                                    id: emptyHistMa
                                    anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: root.openResumePicker()
                                }
                            }
                        }

                        Repeater {
                            model: root.chatMessages
                            delegate: Item {
                                required property var modelData
                                readonly property int maxTextW: Math.max(120, Math.floor(chatFlick.width * 0.82) - 24)
                                Layout.fillWidth: true
                                implicitHeight: bubbleRect.implicitHeight

                                Rectangle {
                                    id: bubbleRect
                                    width: Math.min(parent.maxTextW, Math.ceil(msgText.paintedWidth)) + 24
                                    implicitHeight: Math.ceil(msgText.paintedHeight) + 16
                                    anchors.right: modelData.role === "user" ? parent.right : undefined
                                    anchors.left: modelData.role === "user" ? undefined : parent.left
                                    radius: 14
                                    clip: true
                                    color: modelData.role === "user"
                                        ? "#0A84FF"
                                        : Qt.rgba(1, 1, 1, 0.09)

                                    Text {
                                        id: msgText
                                        x: 12
                                        y: 8
                                        width: parent.parent.maxTextW
                                        text: modelData.text
                                        textFormat: modelData.role === "agy" ? Text.MarkdownText : Text.PlainText
                                        font { family: Appearance.fontFamily; pixelSize: 12 }
                                        lineHeight: 1.25
                                        color: "#ffffff"
                                        wrapMode: Text.Wrap
                                    }
                                }
                            }
                        }

                        // Loading state bubble
                        Rectangle {
                            visible: root.chatLoading
                            width: loadingLbl.implicitWidth + 24
                            height: 30
                            radius: 14
                            color: Qt.rgba(1, 1, 1, 0.08)
                            border.width: 1
                            border.color: Qt.rgba(1, 1, 1, 0.10)
                            Text {
                                id: loadingLbl
                                anchors.centerIn: parent
                                text: "agy sedang berpikir..."
                                font { family: Appearance.fontFamily; pixelSize: 12 }
                                color: "#aeaeb2"
                            }
                        }
                    }
                }

                // Error state banner with retry action
                Rectangle {
                    visible: root.chatError !== "" && !root.resumeMode
                    Layout.fillWidth: true
                    Layout.preferredHeight: errRow.implicitHeight + 12
                    radius: 12
                    color: Qt.rgba(1.0, 0.27, 0.23, 0.16)
                    border.width: 1
                    border.color: Qt.rgba(1.0, 0.27, 0.23, 0.42)

                    RowLayout {
                        id: errRow
                        anchors { fill: parent; margins: 6; leftMargin: 10; rightMargin: 8 }
                        spacing: 8

                        Text {
                            Layout.fillWidth: true
                            text: root.chatError
                            elide: Text.ElideRight
                            maximumLineCount: 2
                            wrapMode: Text.Wrap
                            font { family: Appearance.fontFamily; pixelSize: 11 }
                            color: "#ffd0cd"
                        }

                        Rectangle {
                            visible: root.lastFailedPrompt !== ""
                            width: retryLbl.implicitWidth + 16
                            height: 22
                            radius: 11
                            color: retryMa.containsMouse ? Qt.rgba(1.0, 0.27, 0.23, 0.45) : Qt.rgba(1.0, 0.27, 0.23, 0.30)
                            Text {
                                id: retryLbl
                                anchors.centerIn: parent
                                text: "Coba Lagi"
                                font { family: Appearance.fontFamily; pixelSize: 10; weight: Font.DemiBold }
                                color: "#ffffff"
                            }
                            MouseArea {
                                id: retryMa
                                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: root.sendAgyChat(root.lastFailedPrompt)
                            }
                        }
                    }
                }

                // macOS-style Input Pill
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 36
                        radius: 18
                        color: Qt.rgba(1, 1, 1, 0.08)
                        border.color: chatInput.activeFocus ? Qt.rgba(0.04, 0.52, 1.0, 0.8) : Qt.rgba(1, 1, 1, 0.14)
                        border.width: 1

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.IBeamCursor
                            onClicked: chatInput.forceActiveFocus()
                        }

                        Text {
                            anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
                            verticalAlignment: Text.AlignVCenter
                            text: "Tanya sesuatu... (/resume)"
                            font { family: Appearance.fontFamily; pixelSize: 12 }
                            color: "#636366"
                            visible: chatInput.text.length === 0
                        }

                        TextInput {
                            id: chatInput
                            anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
                            verticalAlignment: TextInput.AlignVCenter
                            color: "#ffffff"
                            font { family: Appearance.fontFamily; pixelSize: 12 }
                            clip: true
                            Component.onCompleted: text = root.chatDraft
                            onTextEdited: root.chatDraft = text
                            Keys.onEscapePressed: {
                                if (!root.chatPinned) root.closeChatPopup();
                            }
                            onAccepted: {
                                if (root.chatLoading) return;
                                root.sendAgyChat(text);
                                root.chatDraft = "";
                                text = "";
                            }
                        }
                    }

                    Rectangle {
                        width: 36; height: 36; radius: 18
                        opacity: root.chatLoading ? 0.45 : 1.0
                        color: sendMa.containsMouse && !root.chatLoading ? "#007AFF" : "#0A84FF"
                        Text {
                            anchors.centerIn: parent
                            text: "↑"
                            font { family: Appearance.fontFamily; pixelSize: 15; weight: Font.Bold }
                            color: "#ffffff"
                        }
                        MouseArea {
                            id: sendMa
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: !root.chatLoading
                            cursorShape: root.chatLoading ? Qt.ArrowCursor : Qt.PointingHandCursor
                            onClicked: {
                                if (root.chatLoading) return;
                                root.sendAgyChat(chatInput.text);
                                root.chatDraft = "";
                                chatInput.text = "";
                            }
                        }
                    }
                }
            }
        }
    }

    // ─── Unpinned Hover Popup (LazyLoader) ────────────────────────
    LazyLoader {
        id: termPopupLoader
        active: root.termOpen && !root.chatPinned && !root.wsPickerOpen && !root.launcherOpen
        onActiveChanged: if (!active) root.chatHovered = false
        component: PanelWindow {
            id: termPopup
            visible: true
            color: "transparent"
            screen: root.hostWindow ? root.hostWindow.screen : null

            anchors.top: true
            margins.top: Appearance.barHeight + 8
            exclusionMode: ExclusionMode.Ignore

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "macos:arch-ai-chat"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

            implicitWidth: 396
            implicitHeight: 440

            Loader {
                anchors.fill: parent
                sourceComponent: chatCardComponent
                onLoaded: item.dragWindow = null
            }
        }
    }

    // ─── Pinned Floating Window (native Super+Drag & header drag) ─
    LazyLoader {
        id: pinnedChatLoader
        active: root.termOpen && root.chatPinned
        component: FloatingWindow {
            id: pinnedWin
            title: "ArchLinux AI Chat"
            implicitWidth: 396
            implicitHeight: 440
            minimumSize: Qt.size(340, 320)
            color: "transparent"
            visible: true
            onClosed: {
                if (root.chatPinned) root.closeChatPopup();
            }

            Loader {
                anchors.fill: parent
                sourceComponent: chatCardComponent
                onLoaded: item.dragWindow = pinnedWin
            }
        }
    }

    // ─── Media Controls Glass Popup (on hover when media active) ───
    PopupWindow {
        id: islandPopup
        visible: root.expanded && root.hasMedia && !root.termOpen && !root.wsPickerOpen && !root.launcherOpen
        color: "transparent"

        anchor.window: root.hostWindow
        anchor.rect.x: root.hostWindow ? Math.round((root.hostWindow.width - implicitWidth) / 2) : 0
        anchor.rect.y: Appearance.barHeight + 4

        implicitWidth: 310
        implicitHeight: 96

        Rectangle {
            anchors.fill: parent
            radius: 16
            color: Qt.rgba(0.10, 0.10, 0.14, 0.88)
            border.color: Qt.rgba(1, 1, 1, 0.20)
            border.width: 1

            HoverHandler {
                id: popupHover
                onHoveredChanged: {
                    if (hovered) closeGrace.stop();
                    else closeGrace.restart();
                }
            }

            RowLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 12

                Rectangle {
                    Layout.preferredWidth: 68
                    Layout.preferredHeight: 68
                    radius: 12
                    color: Qt.rgba(1, 1, 1, 0.08)
                    clip: true

                    Image {
                        anchors.fill: parent
                        source: root.artUrl
                        fillMode: Image.PreserveAspectCrop
                        cache: false
                        visible: root.artUrl !== ""
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: root.artUrl === ""
                        text: "\uF001"
                        font { family: "JetBrainsMono Nerd Font"; pixelSize: 22 }
                        color: "#8e8e93"
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 2

                    Text {
                        Layout.fillWidth: true
                        text: root.trackTitle || "Playing"
                        font { family: Appearance.fontFamily; pixelSize: 13; weight: Font.Bold }
                        color: "#ffffff"
                        elide: Text.ElideRight
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: root.trackArtist.length > 0
                        text: root.trackArtist
                        font { family: Appearance.fontFamily; pixelSize: 11 }
                        color: "#a0a0a8"
                        elide: Text.ElideRight
                    }

                    Item { Layout.fillHeight: true }

                    RowLayout {
                        spacing: 18
                        Layout.alignment: Qt.AlignLeft

                        Text {
                            text: "\uF048"
                            font { family: "JetBrainsMono Nerd Font"; pixelSize: 15 }
                            color: prevMa.containsMouse ? "#ffffff" : "#d1d1d6"
                            MouseArea {
                                id: prevMa
                                anchors.fill: parent; anchors.margins: -5
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (root.activePlayer) root.activePlayer.previous()
                            }
                        }

                        Rectangle {
                            Layout.preferredWidth: 28
                            Layout.preferredHeight: 28
                            radius: 14
                            color: playMa.containsMouse ? Qt.rgba(1, 1, 1, 0.24) : Qt.rgba(1, 1, 1, 0.14)

                            Text {
                                anchors.centerIn: parent
                                text: root.isPlaying ? "\uF04C" : "\uF04B"
                                font { family: "JetBrainsMono Nerd Font"; pixelSize: 13 }
                                color: "#ffffff"
                            }

                            MouseArea {
                                id: playMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (root.activePlayer) root.activePlayer.playPause()
                            }
                        }

                        Text {
                            text: "\uF051"
                            font { family: "JetBrainsMono Nerd Font"; pixelSize: 15 }
                            color: nextMa.containsMouse ? "#ffffff" : "#d1d1d6"
                            MouseArea {
                                id: nextMa
                                anchors.fill: parent; anchors.margins: -5
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (root.activePlayer) root.activePlayer.next()
                            }
                        }
                    }
                }
            }
        }
    }
}
