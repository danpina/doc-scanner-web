import Foundation

/// One scan saved on this iPhone (see `LocalScanStore`).
struct SavedScan: Codable, Identifiable, Equatable {
    let id: String
    var title: String
    let pageCount: Int
    let pdfSize: Int
    let createdAt: Date
    /// The words found on the pages, for searching. Nil for scans saved before text recognition
    /// existed or with it turned off.
    var searchText: String?

    var createdDate: Date? { createdAt }

    /// A short excerpt of the scan's text around the first match of `query`, or nil when the
    /// query isn't in the text.
    func snippet(for query: String) -> String? {
        guard let text = searchText,
              let range = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return nil
        }
        let start = text.index(range.lowerBound, offsetBy: -30, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(range.upperBound, offsetBy: 60, limitedBy: text.endIndex) ?? text.endIndex
        let excerpt = text[start..<end]
            .split(whereSeparator: { $0.isNewline })
            .joined(separator: " ")
        return (start > text.startIndex ? "…" : "") + excerpt + (end < text.endIndex ? "…" : "")
    }

    func matches(_ query: String) -> Bool {
        title.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            || searchText?.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    var subtitle: String {
        var parts: [String] = []
        parts.append(createdAt.formatted(date: .abbreviated, time: .omitted))
        parts.append(pageCount == 1 ? "1 page" : "\(pageCount) pages")
        parts.append(ByteCountFormatter.string(fromByteCount: Int64(pdfSize), countStyle: .file))
        return parts.joined(separator: " · ")
    }
}
