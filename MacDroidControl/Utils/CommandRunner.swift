#if os(macOS)
import Foundation

enum CommandError: LocalizedError {
    case executableNotFound(String)
    case executionFailed(String)

    var errorDescription: String? {
        switch self {
        case .executableNotFound(let name):
            return "\(name) not found. Install via Homebrew: brew install \(name)"
        case .executionFailed(let message):
            return message
        }
    }
}

struct CommandRunner {

    // MARK: - Default Environment

    static let defaultEnvironment: [String: String] = [
        "PATH":   "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
        "HOME":   FileManager.default.homeDirectoryForCurrentUser.path,
        "TMPDIR": NSTemporaryDirectory(),
    ]

    // MARK: - Executable Discovery

    nonisolated static func findExecutable(_ name: String) -> String? {
        // Check known install locations first — instant filesystem stat, no subprocess.
        // This avoids blocking the main thread with a `which` subprocess call.
        let candidates = [
            "/opt/homebrew/bin/\(name)",   // Apple Silicon Homebrew
            "/usr/local/bin/\(name)",      // Intel Homebrew
            "/usr/bin/\(name)",
            "/usr/local/sbin/\(name)",
            "/opt/homebrew/sbin/\(name)",
        ]
        if let fast = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return fast
        }
        // Fall back to `which` only if not in known paths (rare).
        return whichExecutable(name)
    }

    nonisolated private static func whichExecutable(_ name: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        p.arguments = [name]
        p.environment = ["PATH": "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        guard (try? p.run()) != nil else { return nil }
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        let path = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return path.flatMap { $0.isEmpty ? nil : $0 }
    }

    // MARK: - Text Output Runner

    nonisolated static func run(executable: String, arguments: [String]) async throws -> String {
        guard let path = findExecutable(executable) else {
            throw CommandError.executableNotFound(executable)
        }
        return try await run(path: path, arguments: arguments)
    }

    nonisolated static func run(path: String, arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = arguments
                process.environment = defaultEnvironment

                let stdout = Pipe()
                let stderr = Pipe()
                process.standardOutput = stdout
                process.standardError  = stderr

                do {
                    try process.run()

                    // Read both pipes concurrently to prevent pipe-buffer deadlock.
                    // A single large write (or both pipes having output) will
                    // deadlock if we call waitUntilExit() before draining them.
                    var outData = Data()
                    var errData = Data()
                    let group = DispatchGroup()

                    group.enter()
                    DispatchQueue.global().async {
                        outData = stdout.fileHandleForReading.readDataToEndOfFile()
                        group.leave()
                    }
                    group.enter()
                    DispatchQueue.global().async {
                        errData = stderr.fileHandleForReading.readDataToEndOfFile()
                        group.leave()
                    }
                    group.wait()
                    process.waitUntilExit()

                    if process.terminationStatus != 0 {
                        let msg = String(data: errData, encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            ?? "Command failed (exit \(process.terminationStatus))"
                        continuation.resume(throwing: CommandError.executionFailed(msg))
                    } else {
                        continuation.resume(returning: String(data: outData, encoding: .utf8) ?? "")
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Binary Output Runner

    /// Returns raw binary stdout. Reads both stdout and stderr concurrently
    /// so that large outputs (e.g. full-HD screencap PNGs ≫ 64 KB) never
    /// deadlock the pipe buffer while we wait for the process to exit.
    nonisolated static func runBinary(path: String, arguments: [String]) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = arguments
                process.environment = defaultEnvironment

                let stdout = Pipe()
                let stderr = Pipe()
                process.standardOutput = stdout
                process.standardError  = stderr

                do {
                    try process.run()

                    var outData = Data()
                    var errData = Data()
                    let group = DispatchGroup()

                    group.enter()
                    DispatchQueue.global().async {
                        outData = stdout.fileHandleForReading.readDataToEndOfFile()
                        group.leave()
                    }
                    group.enter()
                    DispatchQueue.global().async {
                        errData = stderr.fileHandleForReading.readDataToEndOfFile()
                        group.leave()
                    }
                    group.wait()
                    process.waitUntilExit()

                    if process.terminationStatus != 0 {
                        let msg = String(data: errData, encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            ?? "Command failed (exit \(process.terminationStatus))"
                        continuation.resume(throwing: CommandError.executionFailed(msg))
                    } else {
                        continuation.resume(returning: outData)
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
#endif
