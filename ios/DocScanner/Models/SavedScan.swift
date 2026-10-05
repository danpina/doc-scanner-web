import Foundation

/// One entry from GET /api/scans (also the response of POST /api/scans).
struct SavedScan: Decodable, Identifiable, Equatable {
    let id: String
    let title: String
    let pageCount: Int
    let pdfSize: Int
    let createdAt: String

    var createdDate: Date? { Self.parseDate(createdAt) }

    var subtitle: String {
        var parts: [String] = []
        if let date = createdDate {
            parts.append(date.formatted(date: .abbreviated, time: .omitted))
        }
        parts.append(pageCount == 1 ? "1 page" : "\(pageCount) pages")
        parts.append(ByteCountFormatter.string(fromByteCount: Int64(pdfSize), countStyle: .file))
        return parts.joined(separator: " · ")
    }

    // The server sends JS `toISOString()` output ("2026-07-23T10:13:33.041Z"), which has
    // fractional seconds that a default ISO8601DateFormatter refuses to parse.
    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plainFormatter = ISO8601DateFormatter()

    private static func parseDate(_ string: String) -> Date? {
        fractionalFormatter.date(from: string) ?? plainFormatter.date(from: string)
    }
}
