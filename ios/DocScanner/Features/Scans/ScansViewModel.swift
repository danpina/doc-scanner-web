import Combine
import Foundation

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
