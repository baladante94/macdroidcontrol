#if os(macOS)
import Foundation
import Combine

struct SavedDevice: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String   // user-editable label (defaults to IP)
    var ip: String     // "192.168.x.x:5555"
}

@MainActor
class SavedDevicesStore: ObservableObject {
    @Published var devices: [SavedDevice] = []
    private static let key = "savedWirelessDevices"

    init() { load() }

    /// Adds a device if the IP isn't already saved.
    func add(ip: String, name: String? = nil) {
        let normalised = normalise(ip)
        guard !devices.contains(where: { $0.ip == normalised }) else { return }
        devices.append(SavedDevice(name: name ?? normalised, ip: normalised))
        save()
    }

    func remove(_ device: SavedDevice) {
        devices.removeAll { $0.id == device.id }
        save()
    }

    func update(_ device: SavedDevice, name: String, ip: String) {
        guard let idx = devices.firstIndex(where: { $0.id == device.id }) else { return }
        devices[idx].name = name.isEmpty ? ip : name
        devices[idx].ip   = normalise(ip)
        save()
    }

    /// Ensures the address always has a port suffix.
    private func normalise(_ ip: String) -> String {
        let trimmed = ip.trimmingCharacters(in: .whitespaces)
        return trimmed.contains(":") ? trimmed : "\(trimmed):5555"
    }

    private func load() {
        guard let data    = UserDefaults.standard.data(forKey: Self.key),
              let decoded = try? JSONDecoder().decode([SavedDevice].self, from: data)
        else { return }
        devices = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(devices) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}
#endif
