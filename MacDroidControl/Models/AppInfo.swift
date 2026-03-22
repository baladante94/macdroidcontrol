import Foundation

struct AppInfo: Identifiable {
    let packageName: String
    var id: String { packageName }

    var readableName: String {
        let segments = packageName.split(separator: ".").map(String.init)
        let name = segments.last ?? packageName
        return name.prefix(1).uppercased() + name.dropFirst()
    }
}
