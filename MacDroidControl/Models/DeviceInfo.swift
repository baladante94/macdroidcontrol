import Foundation

struct DeviceInfo {
    let model: String
    let androidVersion: String
    let batteryLevel: Int
    let isCharging: Bool
    let storageUsedBytes: Int64
    let storageTotalBytes: Int64

    var batteryIcon: String {
        if isCharging { return "battery.100.bolt" }
        switch batteryLevel {
        case 76...: return "battery.100"
        case 51...: return "battery.75"
        case 26...: return "battery.50"
        case 11...: return "battery.25"
        default:    return "battery.0"
        }
    }

    var storageUsedFormatted: String { Self.fmtBytes(storageUsedBytes) }
    var storageTotalFormatted: String { Self.fmtBytes(storageTotalBytes) }

    static func fmtBytes(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 1 { return String(format: "%.0f GB", gb) }
        return String(format: "%.0f MB", Double(bytes) / 1_048_576)
    }
}
