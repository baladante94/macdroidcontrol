#if os(macOS)
import AppKit
import Combine

/// Manages a live device-mirror session.
///
/// **Primary**: Streams raw H.264 from `adb exec-out screenrecord --output-format=h264`.
///   Decoded by H264StreamDecoder → AVSampleBufferDisplayLayer.  ≈ 15-30 fps.
///
/// **Fallback**: Polls `adb exec-out screencap -p` PNG frames when the device does
///   not support H.264 streaming.  ≈ 1-5 fps.
@MainActor
class MirrorSession: ObservableObject {

    // H.264 streaming path
    @Published private(set) var h264Decoder: H264StreamDecoder? = nil

    // Screencap fallback path
    @Published private(set) var currentFrame: NSImage? = nil

    @Published private(set) var isRunning:    Bool    = false
    @Published private(set) var isRecording:  Bool    = false
    @Published private(set) var measuredFPS:  Double  = 0
    @Published private(set) var lastError:    String? = nil

    /// True when using the fast H.264 path; false when on screencap fallback.
    @Published private(set) var isStreaming:      Bool    = false
    /// Physical pixel resolution of the connected device, populated on start.
    @Published private(set) var deviceResolution: CGSize = CGSize(width: 1080, height: 2400)

    private var streamProcess:   Process?
    private var captureTask:     Task<Void, Never>?
    private var recordProcess:   Process?
    private var recordRemotePath: String?
    private var recordDeviceId:   String?

    private let adb = "adb"

    // MARK: - Start / Stop

    func start(deviceId: String, fps: Int) {
        guard !isRunning else { return }
        lastError    = nil
        currentFrame = nil
        isRunning    = true

        // Fetch device resolution for accurate touch coordinate mapping.
        Task { [weak self] in
            let adb = ADBService()
            if let res = await adb.screenResolution(deviceId: deviceId) {
                await MainActor.run { self?.deviceResolution = res }
            }
        }

        if startH264Streaming(deviceId: deviceId) {
            isStreaming = true
        } else {
            isStreaming = false
            captureTask = Task { [weak self] in
                await self?.screencapLoop(deviceId: deviceId, targetFPS: max(1, min(fps, 15)))
            }
        }
    }

    func stop() {
        // H.264 streaming
        streamProcess?.terminate()
        streamProcess = nil
        h264Decoder?.reset()
        h264Decoder   = nil

        // Screencap polling
        captureTask?.cancel()
        captureTask  = nil
        currentFrame = nil
        measuredFPS  = 0

        // Recording
        if isRecording, let id = recordDeviceId { stopRecording(deviceId: id) }

        isRunning   = false
        isStreaming = false
    }

    // MARK: - H.264 Streaming

    private func startH264Streaming(deviceId: String) -> Bool {
        guard let adbPath = CommandRunner.findExecutable(adb) else { return false }

        let decoder = H264StreamDecoder()
        let p       = Process()
        p.executableURL = URL(fileURLWithPath: adbPath)
        // --time-limit 0 = unlimited on Android 13+; on older Android, max is 180 s.
        // We restart automatically when the process exits.
        p.arguments = [
            "-s", deviceId, "exec-out",
            "screenrecord",
            "--output-format=h264",
            "--time-limit=180",
            "/proc/self/fd/1"        // more reliable than /dev/stdout on older Android
        ]
        p.environment   = CommandRunner.defaultEnvironment
        p.standardError = Pipe()    // discard; avoids stderr blocking

        let pipe = Pipe()
        p.standardOutput = pipe

        // Feed raw bytes into the decoder from the background I/O thread.
        pipe.fileHandleForReading.readabilityHandler = { [weak decoder] handle in
            let data = handle.availableData
            if !data.isEmpty { decoder?.feed(data) }
        }

        // When screenrecord hits its 3-minute limit or the user stops: restart.
        p.terminationHandler = { [weak self, weak decoder] proc in
            Task { @MainActor [weak self] in
                guard let self, self.isRunning, self.isStreaming else { return }
                // Restart seamlessly
                decoder?.reset()
                self.streamProcess = nil
                _ = self.startH264Streaming(deviceId: deviceId)
            }
        }

        do {
            try p.run()
        } catch {
            return false
        }

        streamProcess = p
        h264Decoder   = decoder
        return true
    }

    // MARK: - Screencap Fallback Loop

    private func screencapLoop(deviceId: String, targetFPS: Int) async {
        guard let adbPath = CommandRunner.findExecutable(adb) else {
            lastError = "adb not found. Install via: brew install android-platform-tools"
            isRunning = false
            return
        }

        let nsPerFrame       = UInt64(1_000_000_000) / UInt64(targetFPS)
        var frameCount       = 0
        var windowStart      = Date()
        var consecutiveFails = 0

        while !Task.isCancelled {
            let tick = Date()

            do {
                let data = try await CommandRunner.runBinary(
                    path: adbPath,
                    arguments: ["-s", deviceId, "exec-out", "screencap", "-p"]
                )

                if !data.isEmpty {
                    let img = NSImage(data: data)
                        ?? NSImage(data: Data(data.filter { $0 != 0x0D }))
                    if let img {
                        currentFrame      = img
                        frameCount       += 1
                        consecutiveFails  = 0
                    }
                }
            } catch {
                consecutiveFails += 1
                if consecutiveFails >= 3 {
                    lastError = "Lost connection: \(error.localizedDescription)"
                    break
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
                continue
            }

            let now = Date()
            if now.timeIntervalSince(windowStart) >= 1.0 {
                measuredFPS = Double(frameCount) / now.timeIntervalSince(windowStart)
                frameCount  = 0
                windowStart = now
            }

            let elapsed   = UInt64(Date().timeIntervalSince(tick) * 1_000_000_000)
            let remaining = nsPerFrame > elapsed ? nsPerFrame - elapsed : 0
            if remaining > 0 { try? await Task.sleep(nanoseconds: remaining) }
        }

        isRunning   = false
        measuredFPS = 0
    }

    // MARK: - Recording

    func startRecording(deviceId: String) {
        guard !isRecording else { return }
        guard let adbPath = CommandRunner.findExecutable(adb) else {
            lastError = "adb not found"
            return
        }

        let ts     = Int(Date().timeIntervalSince1970)
        let remote = "/sdcard/MacDroidControl_\(ts).mp4"
        recordRemotePath = remote
        recordDeviceId   = deviceId

        let p = Process()
        p.executableURL = URL(fileURLWithPath: adbPath)
        p.arguments     = ["-s", deviceId, "shell", "screenrecord", "--time-limit", "180", remote]
        p.environment   = CommandRunner.defaultEnvironment
        p.standardOutput = FileHandle.nullDevice
        p.standardError  = FileHandle.nullDevice

        p.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isRecording = false
                if let path = self.recordRemotePath {
                    await self.pullRecording(deviceId: deviceId, remotePath: path)
                }
                self.recordRemotePath = nil
                self.recordDeviceId   = nil
            }
        }

        do {
            try p.run()
            recordProcess = p
            isRecording   = true
        } catch {
            lastError = "Failed to start recording: \(error.localizedDescription)"
        }
    }

    func stopRecording(deviceId: String) {
        recordProcess?.interrupt()
        recordProcess = nil
    }

    // MARK: - Recording Pull

    private func pullRecording(deviceId: String, remotePath: String) async {
        guard let adbPath = CommandRunner.findExecutable(adb) else { return }
        let filename = URL(fileURLWithPath: remotePath).lastPathComponent
        let dest = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(filename)
        _ = try? await CommandRunner.run(path: adbPath, arguments: ["-s", deviceId, "pull", remotePath, dest.path])
        _ = try? await CommandRunner.run(path: adbPath, arguments: ["-s", deviceId, "shell", "rm", remotePath])
        NSWorkspace.shared.activateFileViewerSelecting([dest])
    }
}
#endif
