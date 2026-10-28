import Combine
import Foundation
import UIKit

@MainActor
final class ScansViewModel: ObservableObject {
    @Published var scans: [SavedScan] = []
    @Published var errorMessage: String?

    func load() {
        scans = LocalScanStore.shared.loadAll()
    }

    func delete(_ scan: SavedScan) {
        do {
            try LocalScanStore.shared.delete(scan)
            scans.removeAll { $0.id == scan.id }
        } catch {
            errorMessage = "Couldn't delete the scan: \(error.localizedDescription)"
        }
    }

    func rename(_ scan: SavedScan, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != scan.title else { return }
        do {
            try LocalScanStore.shared.rename(scan, to: trimmed)
            load()
        } catch {
            errorMessage = "Couldn't rename the scan: \(error.localizedDescription)"
        }
    }

    /// The pages of a saved scan as images, so it can be opened in the editor again.
    func pageImages(for scan: SavedScan) async -> [UIImage] {
        let url = LocalScanStore.shared.pdfURL(for: scan)
        return await Task.detached(priority: .userInitiated) {
            PDFImporter.pageImages(from: url)
        }.value
    }

    /// A copy named after the scan's title, for viewing or sharing (the stored file is named
    /// by id, so sharing it directly would hand out a meaningless filename).
    func exportCopy(_ scan: SavedScan) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(FileNames.safe(scan.title)).pdf")
        do {
            try? FileManager.default.removeItem(at: url)
            try FileManager.default.copyItem(at: LocalScanStore.shared.pdfURL(for: scan), to: url)
            return url
        } catch {
            errorMessage = "Couldn't open the scan: \(error.localizedDescription)"
            return nil
        }
    }
}
