#if os(macOS)
import SwiftUI
import Combine
import CoreAudio
import AppKit

// MARK: - Audio Output Device

struct AudioOutputDevice: Identifiable, Equatable {
    let id:   AudioDeviceID
    let name: String
    let uid:  String
}

// MARK: - SessionViewModel

@MainActor
class SessionViewModel: ObservableObject {
    @Published var config: ScrcpyConfig = SessionViewModel.loadConfig()
    @Published var selectedProfile: ScrcpyProfile = .balanced
    @Published private(set) var audioOutputDevices: [AudioOutputDevice] = []
    @Published var selectedAudioDeviceUID: String = ""
    @Published private(set) var activeMirrors: Set<String> = []
    @Published private(set) var applyingConfigs: Set<String> = []
    @Published private(set) var deviceInfoCache: [String: DeviceInfo] = [:]
    @Published private(set) var fetchingDeviceInfo: Set<String> = []

    /// Folder where screenshots are saved.
    @Published var screenshotFolder: URL = SessionViewModel.loadFolder(key: "screenshotFolder",
                                                                       defaultName: "Screenshots")
    /// Folder where recordings are saved.
    @Published var recordingFolder: URL = SessionViewModel.loadFolder(key: "recordingFolder",
                                                                      defaultName: "Movies")

    let adb = ADBService()
    private var services: [String: ScrcpyService] = [:]
    private var recordingURLs: [String: URL] = [:]
    private var serviceSubscriptions: [String: AnyCancellable] = [:]
    private var cancellables = Set<AnyCancellable>()

    init() {
        $config
            .dropFirst()
            .sink { Self.saveConfig($0) }
            .store(in: &cancellables)

        $screenshotFolder
            .dropFirst()
            .sink { Self.saveFolder($0, key: "screenshotFolder") }
            .store(in: &cancellables)

        $recordingFolder
            .dropFirst()
            .sink { Self.saveFolder($0, key: "recordingFolder") }
            .store(in: &cancellables)

        $config
            .dropFirst()
            .debounce(for: .milliseconds(600), scheduler: RunLoop.main)
            .scan((ScrcpyConfig(), ScrcpyConfig())) { ($0.1, $1) }
            .sink { [weak self] old, new in self?.handleConfigChange(from: old, to: new) }
            .store(in: &cancellables)

        $selectedAudioDeviceUID
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.setAudioOutputIfNeeded()
                guard self.config.enableAudio else { return }
                for (deviceId, service) in self.services
                        where service.isRunning && !service.isRecording {
                    self.applyingConfigs.insert(deviceId)
                    let cfg = self.config
                    service.stop {
                        service.start(deviceId: deviceId, config: cfg)
                        self.applyingConfigs.remove(deviceId)
                    }
                }
            }
            .store(in: &cancellables)

        refreshAudioDevices()

        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.forceKillAll() }
    }

    // MARK: - Per-Device Access

    private func getService(for deviceId: String) -> ScrcpyService {
        if let existing = services[deviceId] { return existing }
        let service = ScrcpyService()
        services[deviceId] = service
        serviceSubscriptions[deviceId] = service.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                guard let self else { return }
                self.objectWillChange.send()
                self.syncActiveMirrors()
            }
        return service
    }

    private func syncActiveMirrors() {
        activeMirrors = Set(services.filter { $0.value.isRunning }.keys)
    }

    func isRunning(for deviceId: String) -> Bool  { services[deviceId]?.isRunning   ?? false }
    func isRecording(for deviceId: String) -> Bool { services[deviceId]?.isRecording ?? false }
    func isApplyingConfig(for deviceId: String) -> Bool { applyingConfigs.contains(deviceId) }
    func errorMessage(for deviceId: String) -> String? { services[deviceId]?.lastError }

    var scrcpyAvailable: Bool { CommandRunner.findExecutable("scrcpy") != nil }

    // MARK: - Mirror

    func startSession(device: Device, deviceVM: DeviceManagerViewModel) {
        let service = getService(for: device.id)
        guard !service.isRunning else { return }
        setAudioOutputIfNeeded()
        Task {
            let id = device.id

            // For wireless devices, verify the device is actually reachable before
            // launching scrcpy — gives an immediate, clear error instead of silent retries.
            if id.contains(":") {
                let state = try? await CommandRunner.run(executable: "adb",
                    arguments: ["-s", id, "get-state"])
                if state?.trimmingCharacters(in: .whitespacesAndNewlines) != "device" {
                    service.reportError("Cannot reach \(id). Make sure your phone is on the same Wi-Fi network and Wireless Debugging is still active.")
                    return
                }
            }

            if config.stayAwake {
                _ = try? await CommandRunner.run(executable: "adb",
                    arguments: ["-s", id, "shell", "settings", "put",
                                "global", "stay_on_while_plugged_in", "3"])
            }
            _ = try? await CommandRunner.run(executable: "adb",
                arguments: ["-s", id, "shell", "service", "call", "SurfaceFlinger", "1008", "i32", "1"])
            _ = try? await CommandRunner.run(executable: "adb",
                arguments: ["-s", id, "shell", "settings", "put", "system", "screenshot_allow_secure", "1"])
            _ = try? await CommandRunner.run(executable: "adb",
                arguments: ["-s", id, "shell", "settings", "put", "global", "policy_control", "null*"])
            service.start(deviceId: id, config: config)
        }
    }

    func stopSession(for deviceId: String) {
        recordingURLs.removeValue(forKey: deviceId)
        let service = getService(for: deviceId)
        service.stop()
        applyingConfigs.remove(deviceId)
        syncActiveMirrors()
        Task {
            _ = try? await CommandRunner.run(executable: "adb",
                arguments: ["-s", deviceId, "shell", "service", "call",
                            "SurfaceFlinger", "1008", "i32", "0"])
        }
    }

    // MARK: - Recording (scrcpy --record flag)

    func startRecording(device: Device) {
        let service = getService(for: device.id)
        guard !service.isRecording else { return }
        let folder   = recordingFolder
        let deviceId = device.id
        let cfg      = config
        let url = folder.appendingPathComponent(
            "recording_\(Int(Date().timeIntervalSince1970)).mp4"
        )
        recordingURLs[deviceId] = url
        // Stop the current mirror (if running) then relaunch with --record.
        service.stop {
            service.startRecording(deviceId: deviceId, config: cfg, to: url)
        }
    }

    func stopRecording(device: Device) {
        let service  = getService(for: device.id)
        guard service.isRecording else { return }
        let url      = recordingURLs[device.id]
        let deviceId = device.id
        let cfg      = config
        recordingURLs.removeValue(forKey: deviceId)
        // Stop scrcpy (this finalises the recording file), then restart mirror.
        service.stop {
            if let url, FileManager.default.fileExists(atPath: url.path) {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            service.start(deviceId: deviceId, config: cfg)
        }
    }

    // MARK: - Smart Config Change

    private func handleConfigChange(from old: ScrcpyConfig, to new: ScrcpyConfig) {
        if old.stayAwake != new.stayAwake {
            let value = new.stayAwake ? "3" : "0"
            for (deviceId, service) in services where service.isRunning {
                Task {
                    _ = try? await CommandRunner.run(executable: "adb",
                        arguments: ["-s", deviceId, "shell", "settings", "put",
                                    "global", "stay_on_while_plugged_in", value])
                }
            }
        }

        let needsRestart = old.fps           != new.fps
                        || old.bitrate       != new.bitrate
                        || old.maxSize       != new.maxSize
                        || old.turnScreenOff != new.turnScreenOff
                        || old.enableAudio   != new.enableAudio
                        || old.alwaysOnTop   != new.alwaysOnTop
        guard needsRestart else { return }

        setAudioOutputIfNeeded()
        for (deviceId, service) in services where service.isRunning && !service.isRecording {
            applyingConfigs.insert(deviceId)
            service.stop {
                service.start(deviceId: deviceId, config: new)
                self.applyingConfigs.remove(deviceId)
            }
        }
    }

    // MARK: - Screenshot

    func takeScreenshot(for device: Device, deviceVM: DeviceManagerViewModel) {
        let folder = screenshotFolder
        Task {
            deviceVM.errorMessage = nil
            do {
                let url = try await adb.screenshot(deviceId: device.id, to: folder)
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                deviceVM.errorMessage = "Screenshot failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Device Info

    func fetchDeviceInfo(for deviceId: String) {
        guard !fetchingDeviceInfo.contains(deviceId) else { return }
        fetchingDeviceInfo.insert(deviceId)
        Task {
            let info = await adb.fetchDeviceInfo(deviceId: deviceId)
            deviceInfoCache[deviceId] = info
            fetchingDeviceInfo.remove(deviceId)
        }
    }

    // MARK: - Cleanup

    func forceKillAll() {
        services.values.forEach { $0.stop() }
        try? Process.run(URL(fileURLWithPath: "/usr/bin/pkill"), arguments: ["-9", "-x", "scrcpy"])
        try? Process.run(URL(fileURLWithPath: "/usr/bin/pkill"), arguments: ["-9", "-f", "screenrecord"])
    }

    // MARK: - Audio Output Devices

    func refreshAudioDevices() {
        Task.detached(priority: .userInitiated) {
            let devices = Self.listOutputDevices()
            await MainActor.run { self.audioOutputDevices = devices }
        }
    }

    nonisolated private static func listOutputDevices() -> [AudioOutputDevice] {
        var propAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope:    kAudioObjectPropertyScopeGlobal,
            mElement:  kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &propAddr, 0, nil, &dataSize
        ) == noErr else { return [] }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &propAddr, 0, nil, &dataSize, &ids
        ) == noErr else { return [] }

        return ids.compactMap { deviceID -> AudioOutputDevice? in
            var outAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamConfiguration,
                mScope:    kAudioDevicePropertyScopeOutput,
                mElement:  0
            )
            var outSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(deviceID, &outAddr, 0, nil, &outSize) == noErr,
                  outSize > 0 else { return nil }

            var nameAddr = AudioObjectPropertyAddress(
                mSelector: kAudioObjectPropertyName,
                mScope:    kAudioObjectPropertyScopeGlobal,
                mElement:  kAudioObjectPropertyElementMain
            )
            var nameRef: CFString = "" as CFString
            var nameSize = UInt32(MemoryLayout<CFString>.size)
            guard AudioObjectGetPropertyData(
                deviceID, &nameAddr, 0, nil, &nameSize, &nameRef
            ) == noErr else { return nil }

            var uidAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope:    kAudioObjectPropertyScopeGlobal,
                mElement:  kAudioObjectPropertyElementMain
            )
            var uidRef: CFString = "" as CFString
            var uidSize = UInt32(MemoryLayout<CFString>.size)
            guard AudioObjectGetPropertyData(
                deviceID, &uidAddr, 0, nil, &uidSize, &uidRef
            ) == noErr else { return nil }

            let name = nameRef as String
            let uid  = uidRef  as String
            guard !name.isEmpty, !uid.isEmpty else { return nil }
            return AudioOutputDevice(id: deviceID, name: name, uid: uid)
        }
    }

    private func setAudioOutputIfNeeded() {
        guard config.enableAudio, !selectedAudioDeviceUID.isEmpty,
              let device = audioOutputDevices.first(where: { $0.uid == selectedAudioDeviceUID })
        else { return }
        var deviceID = device.id
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope:    kAudioObjectPropertyScopeGlobal,
            mElement:  kAudioObjectPropertyElementMain
        )
        AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &addr, 0, nil,
            UInt32(MemoryLayout<AudioDeviceID>.size), &deviceID
        )
    }

    // MARK: - Profiles

    func applyProfile(_ profile: ScrcpyProfile) {
        selectedProfile = profile
        config = profile.config
    }

    // MARK: - Config Persistence

    private static let configKey = "savedScrcpyConfig"

    private static func loadConfig() -> ScrcpyConfig {
        guard let str = UserDefaults.standard.string(forKey: configKey),
              let config = ScrcpyConfig(rawValue: str) else { return ScrcpyConfig() }
        return config
    }

    private static func saveConfig(_ config: ScrcpyConfig) {
        UserDefaults.standard.set(config.rawValue, forKey: configKey)
    }

    // MARK: - Folder Persistence

    private static func loadFolder(key: String, defaultName: String) -> URL {
        if let path = UserDefaults.standard.string(forKey: key) {
            let url = URL(fileURLWithPath: path)
            if (try? url.checkResourceIsReachable()) == true { return url }
        }
        // Default: ~/Pictures for screenshots, ~/Movies for recordings
        let search: FileManager.SearchPathDirectory = defaultName == "Screenshots"
            ? .picturesDirectory : .moviesDirectory
        return FileManager.default.urls(for: search, in: .userDomainMask)[0]
    }

    private static func saveFolder(_ url: URL, key: String) {
        UserDefaults.standard.set(url.path, forKey: key)
    }
}
#endif
