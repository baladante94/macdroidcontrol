#if os(macOS)
import Foundation
import AppKit

@MainActor
class ADBService {
    private let executable = "adb"

    var isAvailable: Bool {
        CommandRunner.findExecutable(executable) != nil
    }

    // MARK: - Device Discovery

    func listDevices() async throws -> [Device] {
        let output = try await CommandRunner.run(executable: executable, arguments: ["devices"])
        return parseDevices(from: output)
    }

    // MARK: - Wireless Connection

    /// Switches the given USB-connected device into TCP/IP mode on port 5555.
    func enableTCPIP(deviceId: String) async throws {
        _ = try await CommandRunner.run(
            executable: executable,
            arguments: ["-s", deviceId, "tcpip", "5555"]
        )
        // Give the device time to restart its ADB daemon in TCP/IP mode.
        // 3 s is safer — some phones (especially with OEM ROMs) take longer.
        try await Task.sleep(nanoseconds: 3_000_000_000)
    }

    /// Connects to a device over Wi-Fi.
    /// - Parameter ip: IPv4 address, optionally including port (e.g. "192.168.1.5" or "192.168.1.5:5555")
    func connect(ip: String) async throws {
        let address = ip.contains(":") ? ip : "\(ip):5555"
        let output = try await CommandRunner.run(
            executable: executable,
            arguments: ["connect", address]
        )
        // adb exits 0 even on failure; check the output text
        let lower = output.lowercased()
        if lower.contains("failed") || lower.contains("refused") || lower.contains("unable") || lower.contains("error") {
            let clean = output.trimmingCharacters(in: .whitespacesAndNewlines)
            throw CommandError.executionFailed(clean)
        }
    }

    // MARK: - Wireless Disconnect

    func disconnect(deviceId: String) async throws {
        _ = try await CommandRunner.run(executable: executable, arguments: ["disconnect", deviceId])
    }

    // MARK: - Screenshot

    func screenshot(deviceId: String, to folder: URL) async throws -> URL {
        let filename = "screenshot_\(Int(Date().timeIntervalSince1970)).png"
        let dest = folder.appendingPathComponent(filename)

        // Primary: capture the scrcpy window on this Mac.
        // scrcpy already captures at the compositor level, bypassing FLAG_SECURE for
        // all apps (DRM video, banking, OTT). We just grab what scrcpy is showing.
        if let data = Self.captureScrcpyWindowPNG() {
            try data.write(to: dest)
            return dest
        }

        // Fallback: ADB screencap (FLAG_SECURE apps will be black on some devices)
        let remote = "/sdcard/\(filename)"
        _ = try await CommandRunner.run(executable: executable,
            arguments: ["-s", deviceId, "shell", "screencap", "-p", remote])
        _ = try await CommandRunner.run(executable: executable,
            arguments: ["-s", deviceId, "pull", remote, dest.path])
        _ = try? await CommandRunner.run(executable: executable,
            arguments: ["-s", deviceId, "shell", "rm", remote])

        guard FileManager.default.fileExists(atPath: dest.path) else {
            throw CommandError.executionFailed("Screenshot failed — start the mirror first, or grant Screen Recording permission in System Settings → Privacy.")
        }
        return dest
    }

    /// Captures the running scrcpy window as PNG data.
    /// Uses `screencapture -R` with the window bounds from CGWindowListCopyWindowInfo.
    /// Returns nil if scrcpy is not running or Screen Recording permission is not granted.
    static func captureScrcpyWindowPNG() -> Data? {
        // Prompt for Screen Recording permission if not yet granted.
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
            return nil
        }

        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return nil }

        guard let info = list.first(where: {
                  ($0[kCGWindowOwnerName as String] as? String) == "scrcpy"
              }),
              let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
              let x = bounds["X"], let y = bounds["Y"],
              let w = bounds["Width"], let h = bounds["Height"],
              w > 0, h > 0
        else { return nil }

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("macdroid_cap_\(Int(Date().timeIntervalSince1970)).png")
        defer { try? FileManager.default.removeItem(at: tmp) }

        // screencapture -R captures a screen region without requiring extra entitlements.
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = ["-R\(Int(x)),\(Int(y)),\(Int(w)),\(Int(h))", "-o", tmp.path]
        p.standardOutput = FileHandle.nullDevice
        p.standardError  = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }

        return try? Data(contentsOf: tmp)
    }

    // MARK: - Device Resolution

    /// Returns the physical screen resolution as (width, height) in pixels.
    func screenResolution(deviceId: String) async -> CGSize? {
        guard let output = try? await CommandRunner.run(
            executable: executable,
            arguments: ["-s", deviceId, "shell", "wm", "size"]
        ) else { return nil }
        // Output: "Physical size: 1080x2400"
        let parts = output
            .components(separatedBy: .whitespacesAndNewlines)
            .last?
            .split(separator: "x")
        guard let parts, parts.count == 2,
              let w = Double(parts[0]), let h = Double(parts[1]) else { return nil }
        return CGSize(width: w, height: h)
    }

    // MARK: - Generic Command

    @discardableResult
    func runCommand(_ args: [String]) async throws -> String {
        try await CommandRunner.run(executable: executable, arguments: args)
    }

    // MARK: - Device Info

    func fetchDeviceInfo(deviceId: String) async -> DeviceInfo {
        let model = (try? await CommandRunner.run(executable: executable,
            arguments: ["-s", deviceId, "shell", "getprop ro.product.model"]))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown"

        let version = (try? await CommandRunner.run(executable: executable,
            arguments: ["-s", deviceId, "shell", "getprop ro.build.version.release"]))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "?"

        let batteryOutput = (try? await CommandRunner.run(executable: executable,
            arguments: ["-s", deviceId, "shell", "dumpsys battery"])) ?? ""

        let dfOutput = (try? await CommandRunner.run(executable: executable,
            arguments: ["-s", deviceId, "shell", "df /sdcard"])) ?? ""

        let (level, charging) = parseBattery(from: batteryOutput)
        let (used, total)     = parseStorage(from: dfOutput)

        return DeviceInfo(model: model, androidVersion: version, batteryLevel: level,
                          isCharging: charging, storageUsedBytes: used, storageTotalBytes: total)
    }

    // MARK: - File Transfer

    func push(files: [URL], to remotePath: String, deviceId: String) async throws {
        let args = ["-s", deviceId, "push"] + files.map(\.path) + [remotePath]
        _ = try await CommandRunner.run(executable: executable, arguments: args)
    }

    // MARK: - File Browser

    func listFiles(at path: String, deviceId: String) async throws -> [DeviceFile] {
        let escapedPath = path.replacingOccurrences(of: "'", with: "'\\''")
        // Trailing slash dereferences symlinks (e.g. /sdcard -> /storage/emulated/0)
        // so ls shows folder *contents* rather than the symlink entry itself.
        let lsPath = escapedPath.hasSuffix("/") ? escapedPath : escapedPath + "/"
        let output = try await CommandRunner.run(executable: executable,
            arguments: ["-s", deviceId, "shell", "TERM=dumb ls -la '\(lsPath)'"])
        return parseFileList(from: output)
    }

    private func parseFileList(from output: String) -> [DeviceFile] {
        // Strip ANSI escape codes
        let clean: String
        if let regex = try? NSRegularExpression(pattern: "\\x1B\\[[0-9;]*[mK]") {
            let range = NSRange(output.startIndex..., in: output)
            clean = regex.stringByReplacingMatches(in: output, range: range, withTemplate: "")
        } else {
            clean = output
        }

        return clean.components(separatedBy: .newlines).compactMap { line -> DeviceFile? in
            let t = line.trimmingCharacters(in: .whitespaces)
            // Skip empty, "total N", and "path/:" header lines (multi-dir ls output)
            guard !t.isEmpty,
                  !t.hasPrefix("total"),
                  !t.hasSuffix(":"),
                  t.count > 10 else { return nil }

            let parts = t.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard parts.count >= 7 else { return nil }

            let perms = parts[0]
            // Symlinks on Android storage usually point to directories; treat them as navigable.
            let kind: DeviceFile.Kind
            switch perms.first {
            case "d": kind = .directory
            case "l": kind = .directory   // treat symlinks as folders for navigation
            case "-": kind = .regular
            default:  return nil
            }

            // Support ls output with or without the group column:
            //   with group: perms links owner group size date time name...  (≥8 fields)
            //   no group:   perms links owner size date time name...        (≥7 fields)
            let sizeIdx: Int
            let nameStart: Int
            if parts.count >= 8, Int64(parts[4]) != nil {
                sizeIdx = 4; nameStart = 7
            } else if Int64(parts[3]) != nil {
                sizeIdx = 3; nameStart = 6
            } else {
                return nil
            }

            guard nameStart < parts.count else { return nil }
            let size = Int64(parts[sizeIdx])
            let date = parts[sizeIdx + 1] + " " + parts[sizeIdx + 2]
            var name = parts[nameStart...].joined(separator: " ")

            // Strip symlink arrow " -> /target"
            if let r = name.range(of: " -> ") { name = String(name[..<r.lowerBound]) }

            guard name != "." && name != ".." && !name.isEmpty else { return nil }
            return DeviceFile(name: name, kind: kind, sizeBytes: size, modified: date)
        }
    }

    func pull(remotePath: String, to folder: URL, deviceId: String) async throws -> URL {
        _ = try await CommandRunner.run(executable: executable,
            arguments: ["-s", deviceId, "pull", remotePath, folder.path])
        let name = URL(fileURLWithPath: remotePath).lastPathComponent
        return folder.appendingPathComponent(name)
    }

    // MARK: - Package Installer (APK / XAPK / APKM)

    /// Installs a single APK, or a split-APK bundle from an XAPK/APKM archive.
    func installPackage(url: URL, deviceId: String) async throws {
        switch url.pathExtension.lowercased() {
        case "apk":
            try await installAPK(path: url, deviceId: deviceId)
        case "xapk", "apkm":
            try await installSplitPackage(archiveURL: url, deviceId: deviceId)
        default:
            throw CommandError.executionFailed("Unsupported format: .\(url.pathExtension). Use .apk, .xapk, or .apkm")
        }
    }

    private func installAPK(path: URL, deviceId: String) async throws {
        let output = try await CommandRunner.run(executable: executable,
            arguments: ["-s", deviceId, "install", "-r", path.path])
        let lower = output.lowercased()
        if lower.contains("failure") || lower.contains("error:") {
            throw CommandError.executionFailed(output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    /// Unzips an XAPK/APKM archive, finds all contained APKs, and installs them
    /// as a split-APK set using `adb install-multiple`.
    private func installSplitPackage(archiveURL: URL, deviceId: String) async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("macdroid_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        // XAPK and APKM are standard ZIP archives — ditto handles them natively
        _ = try await CommandRunner.run(executable: "ditto",
            arguments: ["-xk", archiveURL.path, tmp.path])

        // Collect all .apk files recursively (some archives nest them in subdirs)
        let enumerator = FileManager.default.enumerator(
            at: tmp,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        var apkPaths: [String] = []
        while let fileURL = enumerator?.nextObject() as? URL {
            if fileURL.pathExtension.lowercased() == "apk" {
                apkPaths.append(fileURL.path)
            }
        }

        guard !apkPaths.isEmpty else {
            throw CommandError.executionFailed("No APK files found inside \(archiveURL.lastPathComponent)")
        }

        let output = try await CommandRunner.run(executable: executable,
            arguments: ["-s", deviceId, "install-multiple", "-r"] + apkPaths)
        let lower = output.lowercased()
        if lower.contains("failure") || lower.contains("error:") {
            throw CommandError.executionFailed(output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    // MARK: - App Manager

    func listInstalledApps(deviceId: String) async throws -> [AppInfo] {
        let output = try await CommandRunner.run(executable: executable,
            arguments: ["-s", deviceId, "shell", "pm", "list", "packages", "-3"])
        return output.components(separatedBy: .newlines)
            .compactMap { line -> AppInfo? in
                let t = line.trimmingCharacters(in: .whitespaces)
                guard t.hasPrefix("package:") else { return nil }
                let pkg = String(t.dropFirst("package:".count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !pkg.isEmpty else { return nil }
                return AppInfo(packageName: pkg)
            }
            .sorted { $0.readableName.localizedStandardCompare($1.readableName) == .orderedAscending }
    }

    func launchApp(package: String, deviceId: String) async throws {
        _ = try await CommandRunner.run(executable: executable,
            arguments: ["-s", deviceId, "shell", "monkey",
                        "-p", package, "-c", "android.intent.category.LAUNCHER", "1"])
    }

    func uninstallApp(package: String, deviceId: String) async throws {
        let output = try await CommandRunner.run(executable: executable,
            arguments: ["-s", deviceId, "shell", "pm", "uninstall", "--user", "0", package])
        if output.lowercased().contains("failure") {
            throw CommandError.executionFailed(output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    // MARK: - Parsing Helpers

    private func parseBattery(from output: String) -> (level: Int, charging: Bool) {
        var level = 0
        var charging = false
        for line in output.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("level:"),
               let val = Int(t.dropFirst(6).trimmingCharacters(in: .whitespaces)) {
                level = val
            }
            if t.hasPrefix("status:"),
               let val = Int(t.dropFirst(7).trimmingCharacters(in: .whitespaces)) {
                charging = (val == 2 || val == 5)
            }
        }
        return (level, charging)
    }

    private func parseStorage(from output: String) -> (used: Int64, total: Int64) {
        let dataLines = output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.lowercased().hasPrefix("filesystem") }
        guard let line = dataLines.first else { return (0, 0) }
        let parts = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard parts.count >= 3 else { return (0, 0) }
        // Numeric 1K-blocks (df -k style)
        if let t = Int64(parts[1]), let u = Int64(parts[2]) { return (u * 1024, t * 1024) }
        // Human-readable (e.g. "54.9G")
        if let t = parseHumanBytes(parts[1]), let u = parseHumanBytes(parts[2]) { return (u, t) }
        return (0, 0)
    }

    private func parseHumanBytes(_ s: String) -> Int64? {
        let u = s.uppercased()
        let table: [(String, Int64)] = [
            ("T", 1_099_511_627_776), ("G", 1_073_741_824), ("M", 1_048_576), ("K", 1_024)
        ]
        for (suffix, mult) in table where u.hasSuffix(suffix) {
            if let v = Double(u.dropLast()) { return Int64(v * Double(mult)) }
        }
        return nil
    }

    // MARK: - Output Parsing

    private func parseDevices(from output: String) -> [Device] {
        output
            .components(separatedBy: .newlines)
            .compactMap { line -> Device? in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                // Skip header, daemon messages, empty lines
                guard !trimmed.isEmpty,
                      !trimmed.hasPrefix("List of"),
                      !trimmed.hasPrefix("*") else { return nil }

                // Columns are tab-separated; fall back to any whitespace
                let parts: [String]
                if trimmed.contains("\t") {
                    parts = trimmed.components(separatedBy: "\t").filter { !$0.isEmpty }
                } else {
                    parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                }
                guard parts.count >= 2 else { return nil }

                let status: DeviceStatus
                switch parts[1] {
                case "device":       status = .connected
                case "unauthorized": status = .unauthorized
                case "offline":      status = .offline
                default:             status = .unknown
                }
                return Device(id: parts[0], status: status)
            }
    }
}
#endif
