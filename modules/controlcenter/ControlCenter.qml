import QtQuick
import Quickshell
import qs
import "../../services"
import "eqsh" as EqCC

// Wrapper hosting eqsh's Control Center on demand, bridged to ShellController state.
Scope {
    id: host

    property bool _keepAlive: false

    Timer {
        id: unloadTimer
        interval: 400
        onTriggered: {
            if (!ShellController.controlCenterOpen) {
                host._keepAlive = false;
                gc();
            }
        }
    }

    Component.onCompleted: {
        Ipc.mixin("eqdesktop.controlCenter", "open", () => { ShellController.controlCenterOpen = true; });
        Ipc.mixin("eqdesktop.controlCenter", "close", () => { ShellController.controlCenterOpen = false; });
    }

    Loader {
        id: ccLoader
        active: ShellController.controlCenterOpen || host._keepAlive
        onLoaded: {
            Ipc.mixins["eqdesktop.controlCenter"].open = [() => { ShellController.controlCenterOpen = true; }];
            Ipc.mixins["eqdesktop.controlCenter"].close = [() => { ShellController.controlCenterOpen = false; }];
        }
        sourceComponent: EqCC.ControlCenter {
            id: cc
            screen: Quickshell.screens[0]
            Component.onCompleted: {
                if (ShellController.controlCenterOpen)
                    Qt.callLater(() => cc.openCC());
            }
            onOpenedChanged: {
                if (ShellController.controlCenterOpen !== cc.opened)
                    ShellController.controlCenterOpen = cc.opened;
                if (!cc.opened) unloadTimer.restart();
            }
        }
    }

    Connections {
        target: ShellController
        function onControlCenterOpenChanged() {
            if (ShellController.controlCenterOpen) {
                unloadTimer.stop();
                host._keepAlive = true;
                if (ccLoader.item) ccLoader.item.openCC();
            } else {
                if (ccLoader.item) ccLoader.item.closeCC();
                unloadTimer.restart();
            }
        }
    }
}
