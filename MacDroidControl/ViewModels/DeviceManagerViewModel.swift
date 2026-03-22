#if os(macOS)
import SwiftUI
import AppKit
import Combine
import IOKit

@MainActor
class DeviceManagerViewModel: ObservableObject {
    @Published var devices: [Device] = []
    @Published var selectedDevice: Device? = nil
    @Published var isRefreshing: Bool = false
    @Published var isConnecting: Bool = false
    @Published var errorMessage: String? = nil
    @Published var adbAvailable: Bool = true
    @Published var isInstallingADB: Bool = false

    private let adbService = ADBService()
    private var notificationPort: IONotificationPortRef?
    private var addedIterator:   io_iterator_t = 0
    private var removedIterator: io_iterator_t = 0

    init() {
        Task { await refreshDevices() }
        startUSBMonitoring()
    }

    // MARK: - USB Device Monitoring

    func startUSBMonitoring() {
        guard notificationPort == nil else { return }
        notificationPort = IONotificationPortCreate(kIOMainPortDefault)
        guard let port = notificationPort else { return }

        let rl = IONotificationPortGetRunLoopSource(port).takeUnretainedValue()
        CFRunLoopAddSource(CFRunLoopGetMain(), rl, .defaultMode)

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        // Callback: drain the iterator, then trigger a device refresh.
        let cb: IOServiceMatchingCallback = { userData, iterator in
            while case let svc = IOIteratorNext(iterator), svc != IO_OBJECT_NULL {
                IOObjectRelease(svc)
            }
            guard let ptr = userData else { return }
            let vm = Unmanaged<DeviceManagerViewModel>.fromOpaque(ptr).takeUnretainedValue()
            Task { await vm.refreshDevices() }
        }

        // Watch for USB devices being attached.
        IOServiceAddMatchingNotification(
            port, kIOFirstMatchNotification,
            IOServiceMatching("IOUSBDevice"), cb, selfPtr, &addedIterator
        )
        // Drain the seed iterator so we don't get spurious callbacks.
        while case let s = IOIteratorNext(addedIterator), s != IO_OBJECT_NULL { IOObjectRelease(s) }

        // Watch for USB devices being detached.
        IOServiceAddMatchingNotification(
            port, kIOTerminatedNotification,
            IOServiceMatching("IOUSBDevice"), cb, selfPtr, &removedIterator
        )
        while case let s = IOIteratorNext(removedIterator), s != IO_OBJECT_NULL { IOObjectRelease(s) }
    }

    // MARK: - Device Refresh

    func refreshDevices() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        if errorMessage?.contains("not found") == false {
            errorMessage = nil
        }

        do {
            let fetched = try await adbService.listDevices()
            devices = fetched
            adbAvailable = true
            errorMessage = nil
            if let selected = selectedDevice,
               !devices.contains(where: { $0.id == selected.id }) {
                selectedDevice = nil
            }
        } catch CommandError.executableNotFound {
            adbAvailable = false
            errorMessage = "adb not found. Install via: brew install android-platform-tools"
            devices = []
        } catch {
            errorMessage = error.localizedDescription
        }

        isRefreshing = false
    }

    // MARK: - Wireless Connection

    func connectViaIP(ip: String) async {
        guard validateIP(ip) else {
            errorMessage = "Invalid IP address format."
            return
        }

        errorMessage = nil
        isConnecting = true
        defer { isConnecting = false }

        if let usbDevice = selectedDevice, usbDevice.status == .connected,
           !usbDevice.id.contains(":") {
            do {
                try await adbService.enableTCPIP(deviceId: usbDevice.id)
            } catch {
                errorMessage = "Could not switch device to TCP/IP mode: \(error.localizedDescription)"
                return
            }
        }

        do {
            try await adbService.connect(ip: ip)
            await refreshDevices()
        } catch {
            let msg = error.localizedDescription
            if msg.lowercased().contains("refused") || msg.lowercased().contains("failed") {
                errorMessage = "Could not reach \(ip):5555 — check that phone and Mac are on the same Wi-Fi, and that USB Debugging is enabled. Try 'Enable Wireless ADB' first with USB connected."
            } else {
                errorMessage = msg
            }
        }
    }

    // MARK: - ADB Installation

    func installADB() async {
        let brewCandidates = [
            "/opt/homebrew/bin/brew",
            "/usr/local/bin/brew",
        ]
        guard let brewPath = brewCandidates.first(where: {
            FileManager.default.isExecutableFile(atPath: $0)
        }) else {
            errorMessage = "Homebrew not found. Visit brew.sh to install it, then relaunch the app."
            return
        }

        isInstallingADB = true
        errorMessage = nil
        defer { isInstallingADB = false }

        do {
            _ = try await CommandRunner.run(path: brewPath, arguments: ["install", "android-platform-tools"])
            await refreshDevices()
        } catch {
            errorMessage = "Installation failed: \(error.localizedDescription)"
        }
    }

    // MARK: - ADB Helpers

    func enableWireless(for device: Device) async {
        errorMessage = nil
        isConnecting = true
        defer { isConnecting = false }
        do {
            try await adbService.enableTCPIP(deviceId: device.id)
        } catch {
            errorMessage = "Failed to enable wireless: \(error.localizedDescription)"
        }
    }

    func disconnectWireless(device: Device) async {
        guard device.id.contains(":") else { return }
        errorMessage = nil
        do {
            try await adbService.disconnect(deviceId: device.id)
            if selectedDevice?.id == device.id { selectedDevice = nil }
            await refreshDevices()
        } catch {
            errorMessage = "Failed to disconnect: \(error.localizedDescription)"
        }
    }

    func takeScreenshot(for device: Device, to folder: URL) async {
        errorMessage = nil
        do {
            let url = try await adbService.screenshot(deviceId: device.id, to: folder)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            errorMessage = "Screenshot failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Validation

    private func validateIP(_ ip: String) -> Bool {
        let base = ip.contains(":") ? String(ip.split(separator: ":").first ?? Substring(ip)) : ip
        let parts = base.split(separator: ".")
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard let n = Int(part) else { return false }
            return (0...255).contains(n)
        }
    }
}
#endif
