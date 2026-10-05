import Combine
import Foundation

@MainActor
final class ScansViewModel: ObservableObject {
    @Published var scans: [SavedScan] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            scans = try await APIClient.shared.send("/api/scans", method: .get)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ scan: SavedScan) async {
        do {
            try await APIClient.shared.sendNoContent("/api/scans/\(scan.id)", method: .delete)
            scans.removeAll { $0.id == scan.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Downloads the stored PDF to a temp file (for viewing or sharing).
    func downloadPDF(_ scan: SavedScan) async -> URL? {
        do {
            let data = try await APIClient.shared.fetchData("/api/scans/\(scan.id)/pdf")
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(FileNames.safe(scan.title)).pdf")
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }
}
