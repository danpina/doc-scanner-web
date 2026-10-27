import Foundation

/// Scans saved on this iPhone: one PDF per scan in Documents/Scans plus a small index file with
/// titles and dates. Nothing here is ever sent anywhere (an iCloud device backup, if the user
/// has one turned on, includes it like any other app data).
final class LocalScanStore {
    static let shared = LocalScanStore()

    private let fileManager = FileManager.default
    private let directory: URL

    private var indexURL: URL { directory.appendingPathComponent("index.json") }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private init() {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        directory = documents.appendingPathComponent("Scans", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func pdfURL(for scan: SavedScan) -> URL {
        directory.appendingPathComponent("\(scan.id).pdf")
    }

    /// Newest first. Entries whose PDF has gone missing are skipped.
    func loadAll() -> [SavedScan] {
        guard let data = try? Data(contentsOf: indexURL),
              let scans = try? decoder.decode([SavedScan].self, from: data) else {
            return []
        }
        return scans
            .filter { fileManager.fileExists(atPath: pdfURL(for: $0).path) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    @discardableResult
    func save(pdf: Data, title: String, pageCount: Int, searchText: String? = nil) throws -> SavedScan {
        let scan = SavedScan(
            id: UUID().uuidString,
            title: title,
            pageCount: pageCount,
            pdfSize: pdf.count,
            createdAt: Date(),
            searchText: searchText
        )
        // PDF first, index second: a crash in between leaves an unlisted file, never a listed
        // scan with nothing behind it.
        try pdf.write(to: pdfURL(for: scan), options: .atomic)
        do {
            try writeIndex([scan] + loadAll())
        } catch {
            try? fileManager.removeItem(at: pdfURL(for: scan))
            throw error
        }
        return scan
    }

    func delete(_ scan: SavedScan) throws {
        try writeIndex(loadAll().filter { $0.id != scan.id })
        try? fileManager.removeItem(at: pdfURL(for: scan))
    }

    private func writeIndex(_ scans: [SavedScan]) throws {
        try encoder.encode(scans).write(to: indexURL, options: .atomic)
    }
}
