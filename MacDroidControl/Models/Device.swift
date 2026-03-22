import Foundation

struct Device: Identifiable, Equatable, Hashable {
    let id: String
    let status: DeviceStatus

    var displayName: String { id }
}

enum DeviceStatus: String, Equatable {
    case connected = "device"
    case unauthorized = "unauthorized"
    case offline = "offline"
    case unknown

    var label: String {
        switch self {
        case .connected:    return "Connected"
        case .unauthorized: return "Unauthorized"
        case .offline:      return "Offline"
        case .unknown:      return "Unknown"
        }
    }
}
