#if os(macOS)
import Foundation
import Combine

@MainActor
class NicknameStore: ObservableObject {
    @Published private var nicknames: [String: String] = [:]
    private static let key = "deviceNicknames"

    init() {
        if let dict = UserDefaults.standard.dictionary(forKey: Self.key) as? [String: String] {
            nicknames = dict
        }
    }

    func displayName(for device: Device) -> String {
        nicknames[device.id] ?? device.displayName
    }

    func set(nickname: String, for deviceId: String) {
        let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            nicknames.removeValue(forKey: deviceId)
        } else {
            nicknames[deviceId] = trimmed
        }
        UserDefaults.standard.set(nicknames, forKey: Self.key)
    }
}
#endif
