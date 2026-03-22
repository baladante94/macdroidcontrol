import Foundation

struct DeviceFile: Identifiable {
    enum Kind { case directory, regular, symlink }

    let id = UUID()
    let name: String
    let kind: Kind
    let sizeBytes: Int64?
    let modified: String

    var isDirectory: Bool { kind == .directory }

    var systemImage: String {
        switch kind {
        case .directory: return "folder.fill"
        case .symlink:   return "arrow.right.square"
        case .regular:
            switch (name as NSString).pathExtension.lowercased() {
            case "jpg", "jpeg", "png", "gif", "heic", "webp", "bmp": return "photo"
            case "mp4", "mov", "avi", "mkv", "3gp":                   return "film"
            case "mp3", "aac", "flac", "wav", "m4a", "ogg":           return "music.note"
            case "pdf":                                                return "doc.richtext"
            case "zip", "rar", "7z", "tar", "gz":                     return "archivebox"
            case "apk":                                                return "app.badge"
            case "txt", "log", "md":                                   return "doc.text"
            default:                                                   return "doc"
            }
        }
    }

    var sizeFormatted: String {
        guard let bytes = sizeBytes else { return "" }
        return DeviceInfo.fmtBytes(bytes)
    }
}
