#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Brand Colors

private enum Brand {
    static let blue    = Color(red: 0.039, green: 0.518, blue: 1.0)
    static let cyan    = Color(red: 0.196, green: 0.824, blue: 1.0)
    static let green   = Color(red: 0.188, green: 0.820, blue: 0.345)
    static let red     = Color(red: 1.0,   green: 0.231, blue: 0.188)
    static let orange  = Color(red: 1.0,   green: 0.624, blue: 0.039)
    static let purple  = Color(red: 0.749, green: 0.353, blue: 0.949)
    static let indigo  = Color(red: 0.345, green: 0.337, blue: 0.839)
}

// MARK: - MirrorView

struct MirrorView: View {
    let device: Device
    @ObservedObject var sessionVM: SessionViewModel
    @ObservedObject var deviceVM: DeviceManagerViewModel
    @EnvironmentObject var nicknameStore: NicknameStore

    @State private var showFileBrowser   = false
    @State private var showAppManager    = false
    @State private var isApkTargeted     = false
    @State private var apkStatus: String?
    @State private var apkStatusIsError  = false
    @State private var isInstallingAPK   = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                // MARK: Device Hero
                deviceHero
                    .padding(.bottom, 12)

                // MARK: Device Info Bar
                deviceInfoBar
                    .padding(.bottom, 22)

                // MARK: Active Session Banner
                if sessionVM.isRunning(for: device.id) || sessionVM.isApplyingConfig(for: device.id) {
                    activeSessionBanner
                        .padding(.bottom, 24)
                }

                // MARK: scrcpy availability warning
                if !sessionVM.scrcpyAvailable {
                    InlineError(message: "scrcpy not found. Install via: brew install scrcpy")
                        .padding(.bottom, 16)
                }

                // MARK: Actions
                actionSection
                    .padding(.bottom, 32)

                // MARK: File Transfer
                PremiumSection(title: "File Transfer") {
                    fileTransferSection
                }
                .padding(.bottom, 32)

                // MARK: APK Installer
                PremiumSection(title: "App Installer") {
                    apkInstallerSection
                }
                .padding(.bottom, 32)

                // MARK: App Manager
                PremiumSection(title: "App Manager") {
                    appManagerSection
                }
                .padding(.bottom, 32)

                // MARK: Configuration — General
                PremiumSection(title: "Configuration") {
                    generalConfigGrid
                }
                .padding(.bottom, 32)

                // MARK: Configuration — Wireless (only for wireless devices)
                if device.id.contains(":") {
                    PremiumSection(title: "Wireless Settings") {
                        wirelessConfigGrid
                    }
                    .padding(.bottom, 32)
                }

                // MARK: ADB
                PremiumSection(title: "ADB Controls") {
                    adbControls
                }
                .padding(.bottom, 24)

                // MARK: Errors
                if let error = sessionVM.errorMessage(for: device.id) ?? deviceVM.errorMessage {
                    InlineError(message: error)
                }
            }
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: device.id) { sessionVM.fetchDeviceInfo(for: device.id) }
        .sheet(isPresented: $showFileBrowser) {
            FileBrowserView(device: device, adb: sessionVM.adb)
        }
        .sheet(isPresented: $showAppManager) {
            AppManagerView(device: device, adb: sessionVM.adb)
        }
    }

    // MARK: - Device Hero

    private var deviceHero: some View {
        HStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Brand.blue, Brand.cyan],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 60, height: 60)
                    .shadow(color: Brand.blue.opacity(0.35), radius: 12, y: 4)
                Image(systemName: "candybarphone")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(nicknameStore.displayName(for: device))
                    .font(.title2.weight(.bold))
                HStack(spacing: 6) {
                    Circle()
                        .fill(device.status == .connected ? Brand.green : Brand.orange)
                        .frame(width: 7, height: 7)
                        .shadow(color: device.status == .connected ? Brand.green.opacity(0.5) : .clear, radius: 3)
                    Text(device.status.label)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()

            if sessionVM.isRunning(for: device.id) {
                liveBadge
            }
        }
    }

    private var liveBadge: some View {
        HStack(spacing: 5) {
            PulsingDot(color: sessionVM.isRecording(for: device.id) ? Brand.red : Brand.green)
            Text(sessionVM.isRecording(for: device.id) ? "REC" : "LIVE")
                .font(.caption.weight(.bold))
                .foregroundStyle(sessionVM.isRecording(for: device.id) ? Brand.red : Brand.green)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            (sessionVM.isRecording(for: device.id) ? Brand.red : Brand.green)
                .opacity(0.10),
            in: Capsule()
        )
        .overlay(
            Capsule()
                .strokeBorder(
                    (sessionVM.isRecording(for: device.id) ? Brand.red : Brand.green).opacity(0.3),
                    lineWidth: 1
                )
        )
    }

    // MARK: - Device Info Bar

    private var deviceInfoBar: some View {
        Group {
            if let info = sessionVM.deviceInfoCache[device.id] {
                HStack(spacing: 8) {
                    InfoChip(icon: "iphone", text: info.model)
                    InfoChip(icon: "gear", text: "Android \(info.androidVersion)")
                    InfoChip(icon: info.batteryIcon,
                             text: "\(info.batteryLevel)%" + (info.isCharging ? " ⚡" : ""))
                    if info.storageTotalBytes > 0 {
                        InfoChip(icon: "internaldrive",
                                 text: "\(info.storageUsedFormatted) / \(info.storageTotalFormatted)")
                    }
                    Spacer()
                    Button { sessionVM.fetchDeviceInfo(for: device.id) } label: {
                        Image(systemName: "arrow.clockwise").font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
                    .help("Refresh device info")
                }
            } else if sessionVM.fetchingDeviceInfo.contains(device.id) {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("Fetching device info…")
                        .font(.caption).foregroundStyle(.tertiary)
                    Spacer()
                }
            } else {
                EmptyView()
            }
        }
    }

    // MARK: - File Transfer Section

    private var fileTransferSection: some View {
        HStack(spacing: 14) {
            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Brand.blue)
            VStack(alignment: .leading, spacing: 3) {
                Text("Device File Manager")
                    .font(.callout.weight(.medium))
                Text("Browse folders, push files from Mac, pull files to Mac")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            Spacer()
            Button {
                showFileBrowser = true
            } label: {
                Label("Browse Files", systemImage: "folder")
                    .font(.callout.weight(.medium))
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(.controlBackgroundColor).opacity(0.6),
                    in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .strokeBorder(Color(.separatorColor).opacity(0.6), lineWidth: 0.5))
    }

    // MARK: - APK Installer Section

    private var apkInstallerSection: some View {
        VStack(spacing: 10) {
            // Drop zone
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        isApkTargeted ? Color.green : Color(.separatorColor),
                        style: StrokeStyle(lineWidth: isApkTargeted ? 2 : 1, dash: [5, 3])
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isApkTargeted ? Color.green.opacity(0.07) : Color.clear)
                    )

                if isInstallingAPK {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Installing…").font(.callout).foregroundStyle(.secondary)
                    }
                } else {
                    HStack(spacing: 14) {
                        Image(systemName: "app.badge.plus")
                            .font(.system(size: 22, weight: .light))
                            .foregroundStyle(isApkTargeted ? Color.green : Color(.tertiaryLabelColor))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Drop APK / XAPK / APKM here")
                                .font(.callout)
                                .foregroundStyle(isApkTargeted ? Color.green : Color.secondary)
                            Text("Supports single APKs and split-APK bundles")
                                .font(.caption).foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Button("Choose File…") { pickAPK() }
                            .buttonStyle(.bordered)
                            .disabled(isInstallingAPK)
                    }
                    .padding(.horizontal, 16)
                }
            }
            .frame(height: 60)
            .onDrop(of: [.fileURL], isTargeted: $isApkTargeted) { providers in
                handleAPKDrop(providers: providers)
            }

            // Status
            if let msg = apkStatus {
                HStack(spacing: 6) {
                    Image(systemName: apkStatusIsError
                          ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(apkStatusIsError ? Color.red : Color.green)
                    Text(msg).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
    }

    private static let supportedPackageExtensions: Set<String> = ["apk", "xapk", "apkm"]

    private func pickAPK() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.item]
        panel.message = "Select an APK, XAPK, or APKM file"
        panel.prompt = "Install"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard Self.supportedPackageExtensions.contains(url.pathExtension.lowercased()) else {
            apkStatus = "Unsupported file. Please select a .apk, .xapk, or .apkm file."
            apkStatusIsError = true
            return
        }
        installPackage(url: url)
    }

    private func handleAPKDrop(providers: [NSItemProvider]) -> Bool {
        guard !isInstallingAPK else { return false }
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
            guard let data = item as? Data,
                  let url  = URL(dataRepresentation: data, relativeTo: nil),
                  Self.supportedPackageExtensions.contains(url.pathExtension.lowercased()) else {
                DispatchQueue.main.async {
                    self.apkStatus = "Only .apk, .xapk, and .apkm files can be installed."
                    self.apkStatusIsError = true
                }
                return
            }
            DispatchQueue.main.async { self.installPackage(url: url) }
        }
        return true
    }

    private func installPackage(url: URL) {
        isInstallingAPK = true
        apkStatus = nil
        Task {
            do {
                try await sessionVM.adb.installPackage(url: url, deviceId: device.id)
                apkStatus = "'\(url.lastPathComponent)' installed successfully."
                apkStatusIsError = false
            } catch {
                apkStatus = error.localizedDescription
                apkStatusIsError = true
            }
            isInstallingAPK = false
        }
    }

    // MARK: - App Manager Section

    private var appManagerSection: some View {
        HStack(spacing: 14) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Brand.purple)
            VStack(alignment: .leading, spacing: 3) {
                Text("Installed Apps")
                    .font(.callout.weight(.medium))
                Text("Browse, launch, or uninstall third-party apps")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            Spacer()
            Button {
                showAppManager = true
            } label: {
                Label("Browse Apps", systemImage: "square.grid.2x2")
                    .font(.callout.weight(.medium))
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(.controlBackgroundColor).opacity(0.6),
                    in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .strokeBorder(Color(.separatorColor).opacity(0.6), lineWidth: 0.5))
    }

    // MARK: - Active Session Banner

    private var activeSessionBanner: some View {
        HStack(spacing: 14) {
            HStack(spacing: 8) {
                if sessionVM.isApplyingConfig(for: device.id) {
                    ProgressView().controlSize(.small)
                    Text("Applying…")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)
                } else {
                    PulsingDot(color: Brand.green)
                    Text(sessionVM.isRecording(for: device.id) ? "Recording" : "Mirroring Active")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                }
            }

            Spacer()

            if sessionVM.isRecording(for: device.id) && !sessionVM.isApplyingConfig(for: device.id) {
                HStack(spacing: 5) {
                    Circle().fill(Brand.red).frame(width: 6, height: 6)
                    Text("REC")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Brand.red)
                }
            }

            Button {
                sessionVM.stopSession(for: device.id)
            } label: {
                Label("Stop", systemImage: "stop.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Brand.red)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Brand.green.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Brand.green.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - Action Section

    private var actionSection: some View {
        HStack(spacing: 12) {
            // Mirror card — blue→cyan gradient
            ActionCard(
                symbol: sessionVM.isRunning(for: device.id) ? "stop.fill" : "play.fill",
                gradient: [Brand.blue, Brand.cyan],
                title: sessionVM.isRunning(for: device.id) ? "Stop Mirror" : "Start Mirror",
                subtitle: sessionVM.isRunning(for: device.id)
                    ? "End the scrcpy session"
                    : "Open device mirror via scrcpy"
            ) {
                if sessionVM.isRunning(for: device.id) {
                    sessionVM.stopSession(for: device.id)
                } else {
                    sessionVM.startSession(device: device, deviceVM: deviceVM)
                }
            }

            // Record card — red→orange gradient
            ActionCard(
                symbol: sessionVM.isRecording(for: device.id) ? "stop.circle.fill" : "record.circle.fill",
                gradient: [Brand.red, Brand.orange],
                title: sessionVM.isRecording(for: device.id) ? "Stop Recording" : "Record",
                subtitle: sessionVM.isRecording(for: device.id)
                    ? "Finish & open file in Finder"
                    : "Record mirror · \(sessionVM.recordingFolder.lastPathComponent)"
            ) {
                if sessionVM.isRecording(for: device.id) {
                    sessionVM.stopRecording(device: device)
                } else {
                    sessionVM.startRecording(device: device)
                }
            }

            // Screenshot card — purple→indigo gradient
            ActionCard(
                symbol: "camera.fill",
                gradient: [Brand.purple, Brand.indigo],
                title: "Screenshot",
                subtitle: "Save PNG · \(sessionVM.screenshotFolder.lastPathComponent)"
            ) {
                sessionVM.takeScreenshot(for: device, deviceVM: deviceVM)
            }
        }
    }

    // MARK: - General Config Grid (USB + Wireless)

    private var generalConfigGrid: some View {
        configCard {
            accentConfigRow(label: "Always on Top", help: "Mirror window stays above all other windows", accentColor: Brand.blue) {
                Toggle("", isOn: $sessionVM.config.alwaysOnTop).labelsHidden()
            }
            configDivider
            accentConfigRow(label: "Stay Awake", help: "Keep device screen on while mirroring", accentColor: Brand.green) {
                Toggle("", isOn: $sessionVM.config.stayAwake).labelsHidden()
            }
            configDivider
            accentConfigRow(label: "Turn Screen Off", help: "Disable the device display during mirroring", accentColor: Brand.orange) {
                Toggle("", isOn: $sessionVM.config.turnScreenOff).labelsHidden()
            }
            configDivider
            accentConfigRow(label: "Audio", help: "Stream device audio to this Mac", accentColor: Brand.purple) {
                Toggle("", isOn: $sessionVM.config.enableAudio).labelsHidden()
            }
            if sessionVM.config.enableAudio {
                configDivider
                VStack(spacing: 0) {
                    accentConfigRow(label: "Output Device", help: "Mac speaker / headphones to use", accentColor: Brand.indigo) {
                        Picker("", selection: $sessionVM.selectedAudioDeviceUID) {
                            Text("System Default").tag("")
                            ForEach(sessionVM.audioOutputDevices) { d in
                                Text(d.name).tag(d.uid)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 170)
                    }
                    HStack {
                        Text("Mirror restarts briefly when output changes.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Spacer()
                    }
                    .padding(.leading, 28)
                    .padding(.bottom, 8)
                }
            }
            configDivider
            accentConfigRow(label: "Screenshots", help: "Folder where screenshots are saved", accentColor: Brand.purple) {
                folderPicker(url: $sessionVM.screenshotFolder)
            }
            configDivider
            accentConfigRow(label: "Recordings", help: "Folder where recordings are saved", accentColor: Brand.red) {
                folderPicker(url: $sessionVM.recordingFolder)
            }
        }
    }

    // MARK: - Wireless Config Grid (only for wireless devices)

    private var wirelessConfigGrid: some View {
        configCard {
            accentConfigRow(label: "Max FPS", help: "Frames per second — lower reduces Wi-Fi load", accentColor: Brand.blue) {
                Picker("", selection: $sessionVM.config.fps) {
                    Text("15 fps").tag(15)
                    Text("30 fps").tag(30)
                    Text("60 fps").tag(60)
                }
                .labelsHidden()
                .frame(width: 100)
            }
            configDivider
            accentConfigRow(label: "Bitrate", help: "Lower bitrate reduces lag on Wi-Fi", accentColor: Brand.cyan) {
                Picker("", selection: $sessionVM.config.bitrate) {
                    Text("2 Mbps").tag("2M")
                    Text("4 Mbps").tag("4M")
                    Text("8 Mbps").tag("8M")
                    Text("16 Mbps").tag("16M")
                }
                .labelsHidden()
                .frame(width: 110)
            }
        }
    }

    private func folderPicker(url: Binding<URL>) -> some View {
        HStack(spacing: 8) {
            Text(url.wrappedValue.lastPathComponent)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 100, alignment: .trailing)
            Button("Choose…") {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.allowsMultipleSelection = false
                panel.prompt = "Select"
                if panel.runModal() == .OK, let picked = panel.url {
                    url.wrappedValue = picked
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private func configCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(Color(.controlBackgroundColor).opacity(0.6),
                        in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color(.separatorColor).opacity(0.6), lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var configDivider: some View {
        Divider().padding(.leading, 28)
    }

    private func accentConfigRow<Content: View>(
        label: String,
        help: String,
        accentColor: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 0) {
            // Left accent border
            RoundedRectangle(cornerRadius: 2)
                .fill(accentColor)
                .frame(width: 3, height: 34)
                .padding(.leading, 12)
                .padding(.trailing, 13)

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.callout)
                Text(help)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            content()
                .padding(.trailing, 16)
        }
        .padding(.vertical, 10)
    }

    // MARK: - ADB Controls

    private var adbControls: some View {
        HStack(spacing: 12) {
            if device.id.contains(":") {
                // Wireless device — badge + disconnect button
                HStack(spacing: 10) {
                    HStack(spacing: 7) {
                        ZStack {
                            Circle()
                                .fill(Brand.green.opacity(0.25))
                                .frame(width: 20, height: 20)
                            Image(systemName: "wifi")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Brand.green)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Wireless ADB Active")
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(Brand.green)
                            Text(device.id)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Brand.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Brand.green.opacity(0.25), lineWidth: 1)
                    )

                    Button {
                        sessionVM.stopSession(for: device.id)
                        Task { await deviceVM.disconnectWireless(device: device) }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "wifi.slash")
                            Text("Remove")
                        }
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Brand.red)
                    }
                    .buttonStyle(.bordered)
                    .help("Disconnect this wireless device and remove it from the sidebar")
                }
            } else {
                // USB device — show enable button
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        Task { await deviceVM.enableWireless(for: device) }
                    } label: {
                        HStack(spacing: 6) {
                            if deviceVM.isConnecting {
                                ProgressView().controlSize(.small)
                                Text("Enabling…")
                            } else {
                                Image(systemName: "wifi")
                                Text("Prepare for Wi-Fi")
                            }
                        }
                        .font(.callout.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                    .disabled(deviceVM.isConnecting)
                    .help("Switches ADB to TCP/IP mode over USB — do this once, then unplug and connect via Wi-Fi")

                    Text("Step 1 of 2 · Do this once while USB is plugged in, then use the Wi-Fi button in the toolbar to connect wirelessly.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()

            Menu {
                ForEach(ScrcpyProfile.allCases, id: \.self) { profile in
                    Button(profile.rawValue) { sessionVM.applyProfile(profile) }
                }
            } label: {
                Label("Presets", systemImage: "slider.horizontal.3")
                    .font(.callout.weight(.medium))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Apply a quality preset")
        }
    }
}

// MARK: - Info Chip

private struct InfoChip: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.caption2)
            Text(text).font(.caption)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.controlBackgroundColor), in: Capsule())
        .overlay(Capsule().strokeBorder(Color(.separatorColor).opacity(0.5), lineWidth: 0.5))
    }
}

// MARK: - Pulsing Dot

private struct PulsingDot: View {
    let color: Color
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.3))
                .frame(width: 14, height: 14)
                .scaleEffect(pulse ? 1.6 : 1.0)
                .opacity(pulse ? 0.0 : 0.6)
                .animation(
                    .easeOut(duration: 1.2).repeatForever(autoreverses: false),
                    value: pulse
                )
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .shadow(color: color.opacity(0.7), radius: 3)
        }
        .onAppear { pulse = true }
    }
}

// MARK: - Action Card

private struct ActionCard: View {
    let symbol: String
    let gradient: [Color]
    let title: String
    let subtitle: String
    let action: () -> Void

    @State private var isHovered = false
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(LinearGradient(
                            colors: gradient,
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                        .frame(width: 44, height: 44)
                        .shadow(color: gradient[0].opacity(0.45), radius: 8, y: 3)
                    Image(systemName: symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.controlBackgroundColor))
                    .shadow(
                        color: .black.opacity(isHovered ? 0.13 : 0.06),
                        radius: isHovered ? 12 : 5,
                        y: isHovered ? 5 : 2
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color(.separatorColor).opacity(0.7), lineWidth: 0.5)
            )
            .scaleEffect(isPressed ? 0.96 : isHovered ? 1.02 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovered)
            .animation(.spring(response: 0.12, dampingFraction: 0.8), value: isPressed)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded   { _ in isPressed = false }
        )
    }
}

// MARK: - Premium Section

struct PremiumSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                    .kerning(0.5)
                Rectangle()
                    .fill(Color(.separatorColor))
                    .frame(height: 0.5)
            }
            content()
        }
    }
}

// MARK: - Inline Error

struct InlineError: View {
    let message: String
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.callout)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}
#endif
