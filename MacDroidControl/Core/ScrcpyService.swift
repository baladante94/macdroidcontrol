#if os(macOS)
import Foundation
import Combine
import AppKit

@MainActor
class ScrcpyService: ObservableObject {
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var isRecording: Bool = false
    @Published private(set) var lastError: String? = nil

    private var process: Process?
    private let executable = "scrcpy"
    private var onExited: (() -> Void)?

    // Auto-restart on unexpected disconnect (phone lock, USB glitch, etc.)
    private var lastLaunchArgs: (deviceId: String, extraArgs: [String], recording: Bool)?
    // True while stop() is in progress — distinguishes user stop from unexpected exit.
    private var userInitiatedStop = false
    // Retry counter for consecutive unexpected exits (resets after a good session).
    private var autoRestartAttempt = 0
    // Incremented on every user-initiated stop; auto-restart Tasks compare against this
    // to know whether they've been superseded before launching a new process.
    private var restartGeneration = 0

    var isAvailable: Bool { CommandRunner.findExecutable(executable) != nil }

    // MARK: - Public API

    /// Shows an error without starting a process — used by the session layer
    /// to surface pre-flight failures (e.g. device unreachable on Wi-Fi).
    func reportError(_ message: String) {
        lastError = message
    }

    func start(deviceId: String, config: ScrcpyConfig) {
        guard !isRunning else { return }
        lastError = nil
        autoRestartAttempt = 0
        restartGeneration += 1
        launchProcess(deviceId: deviceId, extraArgs: config.arguments, recording: false)
    }

    func startRecording(deviceId: String, config: ScrcpyConfig, to url: URL) {
        guard !isRunning else { return }
        lastError = nil
        autoRestartAttempt = 0
        launchProcess(
            deviceId: deviceId,
            extraArgs: config.arguments + ["--record", url.path],
            recording: true
        )
    }

    func stop(then completion: (() -> Void)? = nil) {
        guard let proc = process else {
            if onExited != nil {
                let prev = onExited
                onExited = { prev?(); completion?() }
            } else {
                completion?()
            }
            return
        }
        userInitiatedStop = true
        restartGeneration += 1          // invalidates any sleeping auto-restart Task
        onExited = completion
        proc.terminate()
        process     = nil
        isRunning   = false
        isRecording = false
    }

    // MARK: - Private

    private func launchProcess(deviceId: String, extraArgs: [String], recording: Bool) {
        guard let path = CommandRunner.findExecutable(executable) else {
            lastError = "scrcpy not found. Install via: brew install scrcpy"
            return
        }

        lastLaunchArgs = (deviceId: deviceId, extraArgs: extraArgs, recording: recording)
        let startTime = Date()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)

        var args: [String] = [
            "--serial=\(deviceId)",
            "--window-title=MacDroidControl · \(deviceId)",
        ]
        args += extraArgs
        p.arguments = args

        p.environment = [
            "PATH": "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
            "TMPDIR": NSTemporaryDirectory(),
        ]

        p.standardOutput = FileHandle.nullDevice
        let stderrPipe = Pipe()
        p.standardError = stderrPipe

        // Accumulate stderr so we can surface scrcpy's own error messages.
        var stderrBuffer = Data()
        let stderrQueue  = DispatchQueue(label: "macdroid.stderr.\(deviceId)")
        stderrPipe.fileHandleForReading.readabilityHandler = { fh in
            let chunk = fh.availableData
            if !chunk.isEmpty { stderrQueue.async { stderrBuffer.append(chunk) } }
        }

        p.terminationHandler = { [weak self] proc in
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            let exitCode   = proc.terminationStatus
            let elapsed    = Date().timeIntervalSince(startTime)
            // Drain any remaining stderr before leaving the background thread.
            let stderrText = stderrQueue.sync {
                String(data: stderrBuffer, encoding: .utf8) ?? ""
            }
            let isWireless = deviceId.contains(":")

            Task { @MainActor [weak self] in
                guard let self else { return }

                // process != nil means we were NOT stopped by the user — unexpected exit.
                let unexpected = (self.process != nil)
                let wasUser    = self.userInitiatedStop
                self.userInitiatedStop = false
                self.isRunning   = false
                self.isRecording = false
                self.process     = nil

                if unexpected && !wasUser && exitCode != 0 {
                    // Unexpected exit — phone locked, USB glitch, ROM killed scrcpy, etc.
                    // exitCode == 0 means the user closed the scrcpy window intentionally; don't restart.
                    self.lastError = nil
                    guard let args = self.lastLaunchArgs, !args.recording else {
                        // Don't auto-restart recordings — let user decide.
                        return
                    }

                    // Fast exit on a wireless device = network unreachable; don't retry blindly.
                    if isWireless && elapsed < 4 {
                        self.autoRestartAttempt = 0
                        self.lastError = "Cannot reach \(deviceId). Make sure your phone is on the same Wi-Fi network and Wireless Debugging is still active."
                        return
                    }

                    // A session that ran > 10 s is healthy; reset the retry counter.
                    if elapsed > 10 { self.autoRestartAttempt = 0 }

                    // Retry up to 5 times with Fibonacci back-off (2 → 3 → 5 → 8 → 13 s).
                    let delays: [UInt64] = [2, 3, 5, 8, 13]
                    guard self.autoRestartAttempt < delays.count else {
                        self.autoRestartAttempt = 0
                        self.lastError = "Mirror disconnected after multiple retries. Tap ▶ to reconnect."
                        return
                    }
                    let delaySec = delays[self.autoRestartAttempt]
                    self.autoRestartAttempt += 1

                    // Snapshot the generation before sleeping. If the user presses Stop
                    // during the delay, restartGeneration is incremented and we bail out.
                    let generation = self.restartGeneration
                    try? await Task.sleep(nanoseconds: delaySec * 1_000_000_000)
                    guard self.restartGeneration == generation else { return }
                    self.launchProcess(
                        deviceId: args.deviceId,
                        extraArgs: args.extraArgs,
                        recording: false
                    )
                } else {
                    self.autoRestartAttempt = 0
                    if exitCode != 0 && !wasUser {
                        // Try to pull a useful line from scrcpy's own stderr output.
                        let hint = stderrText
                            .components(separatedBy: .newlines)
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .first { $0.lowercased().hasPrefix("error") || $0.lowercased().hasPrefix("adb") }
                        if elapsed < 5 {
                            if isWireless {
                                self.lastError = "Cannot reach \(deviceId). Check that your phone is on the same Wi-Fi network and Wireless Debugging is enabled."
                            } else {
                                let base = "scrcpy failed to start. Unlock the device and ensure USB debugging is authorized."
                                self.lastError = hint.map { "\(base)\n\($0)" } ?? base
                            }
                        } else {
                            self.lastError = hint ?? "scrcpy stopped unexpectedly (exit \(exitCode))."
                        }
                    }
                    let cb = self.onExited
                    self.onExited = nil
                    cb?()
                }
            }
        }

        do {
            try p.run()
            process     = p
            isRunning   = true
            isRecording = recording
        } catch {
            lastError = "Failed to launch scrcpy: \(error.localizedDescription)"
            isRunning = false
        }
    }
}
#endif
