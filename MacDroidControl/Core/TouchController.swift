#if os(macOS)
import Foundation

/// Sends touch and hardware-key input to an Android device via `adb shell input`.
/// All methods are fire-and-forget async — they do not throw.
struct TouchController {

    enum Key: Int {
        case back       = 4
        case home       = 3
        case recents    = 187
        case volumeUp   = 24
        case volumeDown = 25
        case power      = 26
        case enter      = 66
        case delete     = 67
        case screenshot = 120   // KEYCODE_SYSRQ
    }

    // MARK: - Tap

    func tap(deviceId: String, x: Int, y: Int) async {
        await adb(deviceId, "input", "tap", "\(x)", "\(y)")
    }

    // MARK: - Swipe

    func swipe(deviceId: String, from: CGPoint, to: CGPoint, durationMs: Int = 300) async {
        await adb(deviceId,
                  "input", "swipe",
                  "\(Int(from.x))", "\(Int(from.y))",
                  "\(Int(to.x))",   "\(Int(to.y))",
                  "\(durationMs)")
    }

    // MARK: - Hardware Keys

    func press(_ key: Key, deviceId: String) async {
        await adb(deviceId, "input", "keyevent", "\(key.rawValue)")
    }

    // MARK: - Text

    func type(text: String, deviceId: String) async {
        let escaped = text.replacingOccurrences(of: " ", with: "%s")
        await adb(deviceId, "input", "text", escaped)
    }

    // MARK: - Private

    private func adb(_ deviceId: String, _ args: String...) async {
        guard let path = CommandRunner.findExecutable("adb") else { return }
        _ = try? await CommandRunner.run(path: path, arguments: ["-s", deviceId, "shell"] + args)
    }
}
#endif
