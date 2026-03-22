#if os(macOS)
import SwiftUI
import AppKit

struct SidebarView: View {
    @ObservedObject var viewModel: DeviceManagerViewModel
    @ObservedObject var sessionVM: SessionViewModel
    @EnvironmentObject var nicknameStore: NicknameStore
    @EnvironmentObject var savedDevicesStore: SavedDevicesStore
    @EnvironmentObject var appSettings: AppSettings

    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            deviceList
            Divider()
            statusFooter
        }
    }

    // MARK: - Device List

    /// Wireless devices that are offline should be hidden from Devices and shown in Saved instead.
    private var visibleDevices: [Device] {
        viewModel.devices.filter { device in
            guard device.id.contains(":") else { return true }  // always show USB devices
            return device.status == .connected || device.status == .unauthorized
        }
    }

    /// Saved entries to display: saved device is not currently online as a wireless device.
    private var offlineSaved: [SavedDevice] {
        savedDevicesStore.devices.filter { saved in
            !viewModel.devices.contains(where: {
                $0.id == saved.ip && ($0.status == .connected || $0.status == .unauthorized)
            })
        }
    }

    private var deviceList: some View {
        List(selection: $viewModel.selectedDevice) {
            // Active devices (hides offline wireless — they move to Saved)
            Section {
                if visibleDevices.isEmpty {
                    emptyState
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(visibleDevices) { device in
                        DeviceRowView(
                            device: device,
                            displayName: nicknameStore.displayName(for: device),
                            isMirroring: sessionVM.activeMirrors.contains(device.id)
                        )
                        .tag(device)
                        .contextMenu {
                            Button { renameDevice(device) } label: {
                                Label("Rename…", systemImage: "pencil")
                            }
                            if device.id.contains(":") {
                                let isSaved = savedDevicesStore.devices.contains(where: { $0.ip == device.id })
                                if !isSaved {
                                    Button {
                                        savedDevicesStore.add(
                                            ip: device.id,
                                            name: nicknameStore.displayName(for: device)
                                        )
                                    } label: {
                                        Label("Save Device", systemImage: "bookmark")
                                    }
                                }
                                Divider()
                                Button(role: .destructive) {
                                    sessionVM.stopSession(for: device.id)
                                    Task { await viewModel.disconnectWireless(device: device) }
                                } label: {
                                    Label("Remove Wireless Device", systemImage: "wifi.slash")
                                }
                            }
                        }
                    }
                }
            } header: {
                Text("Devices")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .textCase(nil)
            }

            // Saved — only shown when at least one saved device is offline
            if !offlineSaved.isEmpty {
                Section {
                    ForEach(offlineSaved) { saved in
                        SavedDeviceRow(
                            saved: saved,
                            isConnecting: viewModel.isConnecting
                        ) {
                            Task { await viewModel.connectViaIP(ip: saved.ip) }
                        }
                        .listRowBackground(Color.clear)
                        .contextMenu {
                            Button { editSavedDevice(saved) } label: {
                                Label("Edit…", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                savedDevicesStore.remove(saved)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    Text("Saved")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .textCase(nil)
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 210)
        // Deselect if the selected device has been hidden (went offline wirelessly)
        .onChange(of: visibleDevices) { _, visible in
            if let sel = viewModel.selectedDevice, !visible.contains(sel) {
                viewModel.selectedDevice = nil
            }
        }
    }

    // MARK: - Edit Saved Device

    private func editSavedDevice(_ saved: SavedDevice) {
        let alert = NSAlert()
        alert.messageText = "Edit Saved Device"
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let stack = NSStackView(frame: NSRect(x: 0, y: 0, width: 280, height: 58))
        stack.orientation = .vertical
        stack.spacing = 8

        let nameField = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 22))
        nameField.placeholderString = "Name (optional)"
        nameField.stringValue = saved.name == saved.ip ? "" : saved.name
        nameField.bezelStyle = .roundedBezel

        let ipField = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 22))
        ipField.placeholderString = "192.168.1.100 or 192.168.1.100:5555"
        ipField.stringValue = saved.ip
        ipField.bezelStyle = .roundedBezel

        stack.addArrangedSubview(nameField)
        stack.addArrangedSubview(ipField)
        alert.accessoryView = stack
        alert.window.initialFirstResponder = nameField

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let newIP   = ipField.stringValue.trimmingCharacters(in: .whitespaces)
        let newName = nameField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !newIP.isEmpty else { return }
        savedDevicesStore.update(saved, name: newName, ip: newIP)
    }

    // MARK: - Rename

    private func renameDevice(_ device: Device) {
        let alert = NSAlert()
        alert.messageText = "Rename Device"
        alert.informativeText = "Enter a custom name for \(device.displayName)."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = device.displayName
        field.stringValue = nicknameStore.displayName(for: device) == device.displayName
            ? "" : nicknameStore.displayName(for: device)
        field.bezelStyle = .roundedBezel
        alert.accessoryView = field

        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        nicknameStore.set(nickname: field.stringValue, for: device.id)
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer().frame(height: 20)

            if !viewModel.adbAvailable {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 22))
                    .foregroundStyle(.orange)
                Text("ADB Not Found")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                Text("See setup instructions →")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else if viewModel.isInstallingADB {
                ProgressView().controlSize(.small)
                Text("Installing ADB…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if viewModel.isRefreshing {
                ProgressView().controlSize(.small)
                Text("Scanning…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "iphone.slash")
                    .font(.system(size: 22))
                    .foregroundStyle(.tertiary)
                Text("No Devices")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                Text("Connect via USB or Wi-Fi")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer().frame(height: 20)
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }

    // MARK: - Footer

    private var statusFooter: some View {
        HStack(spacing: 6) {
            // ADB status dot
            Circle()
                .fill(viewModel.adbAvailable ? Color.green : Color.orange)
                .frame(width: 6, height: 6)
                .shadow(color: viewModel.adbAvailable ? .green.opacity(0.5) : .clear, radius: 3)

            Text(viewModel.adbAvailable ? "ADB Ready" : "ADB Not Found")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Spacer()

            if viewModel.isRefreshing {
                ProgressView().controlSize(.mini)
            }

            // Settings gear
            Button {
                showSettings.toggle()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Settings")
            .popover(isPresented: $showSettings, arrowEdge: .top) {
                SettingsPopover()
                    .environmentObject(appSettings)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Saved Device Row

struct SavedDeviceRow: View {
    let saved: SavedDevice
    let isConnecting: Bool
    let onConnect: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onConnect) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.gray.opacity(0.18))
                        .frame(width: 30, height: 30)
                    Image(systemName: "candybarphone")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(saved.name)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    HStack(spacing: 4) {
                        Image(systemName: "wifi.slash")
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                        Text(saved.ip)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                if isConnecting {
                    ProgressView().controlSize(.mini)
                } else if isHovered {
                    Image(systemName: "arrow.right.circle.fill")
                        .foregroundStyle(Color.accentColor.opacity(0.8))
                        .font(.system(size: 14))
                }
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .disabled(isConnecting)
        .help("Tap to connect to \(saved.ip)")
    }
}

// MARK: - Device Row

struct DeviceRowView: View {
    let device: Device
    let displayName: String
    let isMirroring: Bool
    @State private var isHovered = false
    @State private var mirrorDotPulse = false

    init(device: Device, displayName: String? = nil, isMirroring: Bool = false) {
        self.device = device
        self.displayName = displayName ?? device.displayName
        self.isMirroring = isMirroring
    }

    var body: some View {
        HStack(spacing: 10) {
            // Colored rounded-rect badge
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [statusColor, statusColor.opacity(0.65)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 30, height: 30)
                    .shadow(color: statusColor.opacity(0.3), radius: 4, y: 2)
                Image(systemName: "candybarphone")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(displayName)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if device.id.contains(":") {
                        Image(systemName: "wifi")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.blue)
                    }
                }

                if isMirroring {
                    HStack(spacing: 4) {
                        ZStack {
                            Circle()
                                .fill(Color(red: 0.188, green: 0.820, blue: 0.345).opacity(0.3))
                                .frame(width: 10, height: 10)
                                .scaleEffect(mirrorDotPulse ? 1.7 : 1.0)
                                .opacity(mirrorDotPulse ? 0.0 : 0.7)
                                .animation(
                                    .easeOut(duration: 1.1).repeatForever(autoreverses: false),
                                    value: mirrorDotPulse
                                )
                            Circle()
                                .fill(Color(red: 0.188, green: 0.820, blue: 0.345))
                                .frame(width: 5, height: 5)
                        }
                        Text("Mirroring")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color(red: 0.188, green: 0.820, blue: 0.345))
                    }
                    .onAppear { mirrorDotPulse = true }
                    .onDisappear { mirrorDotPulse = false }
                } else {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 5, height: 5)
                        let isWireless = device.id.contains(":")
                        let label = isWireless && device.status == .connected ? "Wireless" : device.status.label
                        Text(label)
                            .font(.caption)
                            .foregroundStyle(isWireless && device.status == .connected ? Color.blue : Color.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 3)
    }

    private var statusColor: Color {
        switch device.status {
        case .connected:    return Color(red: 0.188, green: 0.820, blue: 0.345)
        case .unauthorized: return .orange
        case .offline:      return .red
        case .unknown:      return .gray
        }
    }
}
#endif
