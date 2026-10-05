import Foundation

enum FileNames {
    /// A title made safe to use as a file name (no path separators or other reserved characters).
    static func safe(_ title: String) -> String {
        let reserved = CharacterSet(charactersIn: "/\\:?*\"<>|")
        let cleaned = title
            .components(separatedBy: reserved)
            .joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Scan" : cleaned
    }
}
