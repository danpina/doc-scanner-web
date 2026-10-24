import Foundation

/// One scan saved on this iPhone (see `LocalScanStore`).
struct SavedScan: Codable, Identifiable, Equatable {
    let id: String
    var title: String
    let pageCount: Int
    let pdfSize: Int
    let createdAt: Date

    var createdDate: Date? { createdAt }

    var subtitle: String {
        var parts: [String] = []
        parts.append(createdAt.formatted(date: .abbreviated, time: .omitted))
        parts.append(pageCount == 1 ? "1 page" : "\(pageCount) pages")
        parts.append(ByteCountFormatter.string(fromByteCount: Int64(pdfSize), countStyle: .file))
        return parts.joined(separator: " · ")
    }
}
