import Foundation

/// Files other apps hand to Doc Scanner ("Open in…" / "Copy to Doc Scanner" on a PDF or image)
/// wait here until the scan screen picks them up.
@MainActor
final class ImportInbox: ObservableObject {
    @Published var pendingURLs: [URL] = []

    func receive(_ url: URL) {
        pendingURLs.append(url)
    }

    func take() -> [URL] {
        let urls = pendingURLs
        pendingURLs = []
        return urls
    }
}
