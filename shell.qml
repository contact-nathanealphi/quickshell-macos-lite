import QtQuick
import Quickshell
import qs
import qs.config
import qs.ui.components.lockscreen
import "./services"
import "./modules/topbar"
import "./modules/spotlight"
import "./modules/dock"
import "./modules/genie"
import "./modules/about"
import "./modules/notification"
import "./modules/session"
import "./modules/controlcenter"
import "./modules/desktop"
import "./modules/settings"
import "./modules/launcher"
import "./modules/siri"
import "./modules/hotcorners"

ShellRoot {
    id: root

    property bool _spotlightKeepAlive: false

    Timer {
        id: spotlightUnloadTimer
        interval: 300
        onTriggered: {
            if (!ShellController.spotlightOpen && !Runtime.spotlightOpen) {
                root._spotlightKeepAlive = false;
                gc();
            }
        }
    }

    TopBar { id: topBar }
    Loader {
        id: spotlightLoader
        active: Config.spotlight.enable && (ShellController.spotlightOpen || Runtime.spotlightOpen || root._spotlightKeepAlive)
        sourceComponent: Spotlight {}
    }
    Loader { active: false; sourceComponent: Launcher {} }
    Loader { active: Config.dock.enable; sourceComponent: Dock {} }
    // Genie {}
    // AboutWindow { parentWindow: topBar }
    NotificationPopup {}
    Loader { active: ShellController.sessionOpen; sourceComponent: Session {} }
    Loader { active: ShellController.pendingConfirm !== ""; sourceComponent: ConfirmDialog {} }
    Loader { active: ShellController.forceQuitOpen; sourceComponent: ForceQuit {} }
    ControlCenter {}
    // Settings {}
    // Siri {}
    // HotCorners {}

    // eqsh LockScreen (ext-session-lock) loaded on demand
    Loader {
        id: lockLoader
        active: Config.lockScreen.enable && (ShellController.locked || Runtime.locked)
        onLoaded: {
            Ipc.mixins["eqdesktop.lock"].lock = [() => ShellController.lock()];
            Ipc.mixins["eqdesktop.lock"].unlock = [() => { Runtime.locked = false; ShellController.unlock(); }];
            Ipc.mixins["eqdesktop.lock"].isLoaded = [() => ShellController.locked || Runtime.locked];
        }
        onActiveChanged: if (!active) gc()
        sourceComponent: Lock {
            id: lockScreen
            Component.onCompleted: lockScreen.lockScreen()
            onLock: ShellController.lock()
            onUnlocking: if (!Config.notch.delayedLockAnim) ShellController.unlock()
            onUnlock: {
                Runtime.locked = false;
                ShellController.unlock();
            }
        }
    }

    Connections {
        target: ShellController
        function onLockedChanged() {
            if (ShellController.locked) {
                if (!Runtime.locked) Runtime.locked = true;
            } else {
                if (Runtime.locked) Runtime.locked = false;
            }
        }
    }

    // eqsh Spotlight reads Runtime.spotlightOpen; macos uses ShellController.spotlightOpen
    Connections {
        target: Runtime
        function onSpotlightOpenChanged() {
            if (Runtime.spotlightOpen) {
                spotlightUnloadTimer.stop();
                root._spotlightKeepAlive = true;
            } else if (!ShellController.spotlightOpen) {
                spotlightUnloadTimer.restart();
            }
            if (ShellController.spotlightOpen !== Runtime.spotlightOpen)
                ShellController.spotlightOpen = Runtime.spotlightOpen;
        }
    }
    Connections {
        target: ShellController
        function onSpotlightOpenChanged() {
            if (ShellController.spotlightOpen) {
                spotlightUnloadTimer.stop();
                root._spotlightKeepAlive = true;
            } else if (!Runtime.spotlightOpen) {
                spotlightUnloadTimer.restart();
            }
            if (Runtime.spotlightOpen !== ShellController.spotlightOpen)
                Runtime.spotlightOpen = ShellController.spotlightOpen;
        }
    }

    Component.onCompleted: {
        Ipc.mixin("eqdesktop.spotlight", "toggle", () => {
            Runtime.spotlightOpen = !Runtime.spotlightOpen;
        });
        Ipc.mixin("eqdesktop.spotlight", "set", (visible) => {
            Runtime.spotlightOpen = visible;
        });
        Ipc.mixin("eqdesktop.lock", "lock", () => ShellController.lock());
        Ipc.mixin("eqdesktop.lock", "unlock", () => {
            Runtime.locked = false;
            ShellController.unlock();
        });
        Ipc.mixin("eqdesktop.lock", "isLoaded", () => ShellController.locked || Runtime.locked);
        Runtime.subscribe("lockscreen", () => {
            if (!Runtime.locked) Runtime.locked = true;
        });
    }
}
