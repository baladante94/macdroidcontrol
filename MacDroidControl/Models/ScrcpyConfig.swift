import Foundation

struct ScrcpyConfig: Equatable, Codable {
    var bitrate: String = "8M"
    var maxSize: Int = 0       // 0 = no limit
    var fps: Int = 60
    var stayAwake: Bool = true
    var turnScreenOff: Bool = false
    var enableAudio: Bool = false
    var alwaysOnTop: Bool = false

    var arguments: [String] {
        var args: [String] = []
        args += ["--video-bit-rate", bitrate]
        if maxSize > 0 { args += ["--max-size", String(maxSize)] }
        args += ["--max-fps", String(fps)]
        if stayAwake      { args.append("--stay-awake") }
        if turnScreenOff  { args.append("--turn-screen-off") }
        if !enableAudio   { args.append("--no-audio") }
        if alwaysOnTop    { args.append("--always-on-top") }
        return args
    }
}

// MARK: - AppStorage / UserDefaults support
//
// NOTE: Uses JSONSerialization (not JSONEncoder/JSONDecoder) to avoid infinite
// recursion. When a Codable type also conforms to RawRepresentable<String>,
// Foundation's JSONEncoder resolves it via rawValue → encode(self) → rawValue → …

extension ScrcpyConfig: RawRepresentable {
    var rawValue: String {
        let dict: [String: Any] = [
            "bitrate":       bitrate,
            "maxSize":       maxSize,
            "fps":           fps,
            "stayAwake":     stayAwake,
            "turnScreenOff": turnScreenOff,
            "enableAudio":   enableAudio,
            "alwaysOnTop":   alwaysOnTop,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str  = String(data: data, encoding: .utf8) else { return "{}" }
        return str
    }

    init?(rawValue: String) {
        guard let data = rawValue.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        self.init()
        if let v = dict["bitrate"]       as? String { bitrate       = v }
        if let v = dict["maxSize"]       as? Int    { maxSize        = v }
        if let v = dict["fps"]           as? Int    { fps            = v }
        if let v = dict["stayAwake"]     as? Bool   { stayAwake      = v }
        if let v = dict["turnScreenOff"] as? Bool   { turnScreenOff  = v }
        if let v = dict["enableAudio"]   as? Bool   { enableAudio    = v }
        if let v = dict["alwaysOnTop"]   as? Bool   { alwaysOnTop    = v }
    }
}

enum ScrcpyProfile: String, CaseIterable {
    case lowLatency  = "Low Latency"
    case balanced    = "Balanced"
    case highQuality = "High Quality"

    var config: ScrcpyConfig {
        switch self {
        case .lowLatency:  return ScrcpyConfig(bitrate: "2M",  maxSize: 720, fps: 60)
        case .balanced:    return ScrcpyConfig(bitrate: "8M",  maxSize: 0,   fps: 60)
        case .highQuality: return ScrcpyConfig(bitrate: "16M", maxSize: 0,   fps: 60)
        }
    }
}
