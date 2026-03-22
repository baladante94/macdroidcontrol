#if os(macOS)
import SwiftUI

struct MainView: View {
    @ObservedObject var deviceVM: DeviceManagerViewModel
    @ObservedObject var sessionVM: SessionViewModel

    var body: some View {
        Group {
            if !deviceVM.adbAvailable {
                ADBNotInstalledView(deviceVM: deviceVM)
            } else if let device = deviceVM.selectedDevice {
                deviceContent(for: device)
            } else {
                noSelectionPlaceholder
            }
        }
        .frame(minWidth: 480, minHeight: 400)
    }

    @ViewBuilder
    private func deviceContent(for device: Device) -> some View {
        switch device.status {
        case .connected:
            MirrorView(device: device, sessionVM: sessionVM, deviceVM: deviceVM)
        case .unauthorized:
            unauthorizedPlaceholder
        case .offline:
            offlinePlaceholder
        case .unknown:
            unknownPlaceholder
        }
    }

    // MARK: - Placeholders

    private var noSelectionPlaceholder: some View {
        VStack(spacing: 16) {
            Image(systemName: "candybarphone")
                .font(.system(size: 56, weight: .ultraLight))
                .foregroundStyle(.tertiary)

            VStack(spacing: 6) {
                Text("No Device Selected")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("Connect an Android device via USB,\nor use the Wi‑Fi button in the toolbar.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var unauthorizedPlaceholder: some View {
        VStack(spacing: 20) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.orange.opacity(0.12))
                    .frame(width: 72, height: 72)
                Image(systemName: "lock.shield")
                    .font(.system(size: 32))
                    .foregroundStyle(.orange)
            }

            VStack(spacing: 7) {
                Text("Device Unauthorized")
                    .font(.title2.weight(.semibold))
                Text("Unlock your Android device and accept\nthe USB debugging prompt.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button("Refresh") {
                Task { await deviceVM.refreshDevices() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var offlinePlaceholder: some View {
        EmptyStatePlaceholder(
            systemImage: "cable.connector.slash",
            tint: .red,
            title: "Device Offline",
            message: "Check your USB cable or reconnect the device."
        )
    }

    private var unknownPlaceholder: some View {
        EmptyStatePlaceholder(
            systemImage: "questionmark.circle",
            tint: .secondary,
            title: "Unknown State",
            message: "The device reported an unrecognized status."
        )
    }
}

// MARK: - ADB Not Installed Card

private struct ADBNotInstalledView: View {
    @ObservedObject var deviceVM: DeviceManagerViewModel

    var body: some View {
        ZStack {
            Color(.windowBackgroundColor).ignoresSafeArea()
            card
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var card: some View {
        VStack(spacing: 28) {
            // Icon badge
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color(red: 0.18, green: 0.46, blue: 0.96),
                                 Color(red: 0.13, green: 0.78, blue: 0.87)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 80, height: 80)
                    .shadow(color: .blue.opacity(0.3), radius: 16, y: 6)
                Image(systemName: "cable.connector")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(.white)
            }

            // Headline
            VStack(spacing: 8) {
                Text("Android Tools Not Found")
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                Text("ADB (Android Debug Bridge) is required to detect\nand communicate with your Android device.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Action
            VStack(spacing: 12) {
                Button {
                    Task { await deviceVM.installADB() }
                } label: {
                    Group {
                        if deviceVM.isInstallingADB {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small).tint(.white)
                                Text("Downloading & Installing…")
                            }
                        } else {
                            Label("Install Android Tools", systemImage: "arrow.down.circle.fill")
                        }
                    }
                    .frame(minWidth: 220)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(deviceVM.isInstallingADB)

                if let error = deviceVM.errorMessage {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
                        Text(error).font(.callout).foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 4)
                }
            }

            // Hint
            VStack(spacing: 4) {
                Text("Installs via Homebrew · \(Text("brew install android-platform-tools").fontDesign(.monospaced))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                if !deviceVM.isInstallingADB {
                    Button("Recheck") {
                        Task { await deviceVM.refreshDevices() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(48)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(.controlBackgroundColor))
                .shadow(color: .black.opacity(0.10), radius: 28, y: 8)
        )
        .frame(maxWidth: 400)
        .padding(40)
    }
}

// MARK: - Reusable Empty State

struct EmptyStatePlaceholder: View {
    let systemImage: String
    var tint: Color = .secondary
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(tint.opacity(0.10))
                    .frame(width: 72, height: 72)
                Image(systemName: systemImage)
                    .font(.system(size: 30))
                    .foregroundStyle(tint)
            }
            VStack(spacing: 6) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
#endif
