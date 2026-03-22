#if os(macOS)
import SwiftUI

struct MenuBarContent: View {
    @EnvironmentObject var deviceVM:      DeviceManagerViewModel
    @EnvironmentObject var sessionVM:     SessionViewModel
    @EnvironmentObject var nicknameStore: NicknameStore

    var body: some View {
        if deviceVM.devices.isEmpty {
            Text("No devices connected")
                .foregroundStyle(.secondary)
        } else {
            ForEach(deviceVM.devices) { device in
                let name    = nicknameStore.displayName(for: device)
                let running = sessionVM.isRunning(for: device.id)
                Button {
                    if running {
                        sessionVM.stopSession(for: device.id)
                    } else {
                        sessionVM.startSession(device: device, deviceVM: deviceVM)
                    }
                } label: {
                    Label(
                        running ? "Stop — \(name)" : "Mirror — \(name)",
                        systemImage: running ? "stop.fill" : "play.fill"
                    )
                }
            }
        }

        Divider()

        Button("Open MacDroidControl") {
            NSApp.activate(ignoringOtherApps: true)
            for window in NSApp.windows where window.canBecomeMain {
                window.makeKeyAndOrderFront(nil)
                break
            }
        }

        Divider()

        Button("Quit MacDroidControl") {
            NSApp.terminate(nil)
        }
    }
}
#endif
