import PhotosUI
import SwiftUI

/// The scan in progress: an ordered list of pages plus everything you can do to them before
/// exporting. The heavy image work runs off the main thread; `isBusy` drives a spinner.
@MainActor
final class ScanSession: ObservableObject {
    @Published private(set) var pages: [ScanPage] = []
    @Published var isBusy = false
    @Published private(set) var busyMessage = "Processing…"
    @Published var errorMessage: String?

    func page(withID id: UUID) -> ScanPage? {
        pages.first { $0.id == id }
    }

    // MARK: Adding pages

    /// Pages from the document camera (already flattened by VisionKit).
    func addScanned(_ images: [UIImage]) async {
        guard !images.isEmpty else { return }
        isBusy = true
        defer { isBusy = false }
        pages.append(contentsOf: await makePages(from: images))
    }

    /// Photos picked from the library.
    func addPhotos(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        isBusy = true
        defer { isBusy = false }

        var images: [UIImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                images.append(image)
            }
        }
        guard !images.isEmpty else {
            errorMessage = "Couldn't load the selected photos."
            return
        }
        pages.append(contentsOf: await makePages(from: images))
    }

    /// Every page of one or more existing PDFs.
    func addPDFs(_ urls: [URL]) async {
        guard !urls.isEmpty else { return }
        isBusy = true
        defer { isBusy = false }

        var images: [UIImage] = []
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            images.append(contentsOf: PDFImporter.pageImages(from: url))
            if scoped { url.stopAccessingSecurityScopedResource() }
        }
        guard !images.isEmpty else {
            errorMessage = "No pages could be read from that PDF."
            return
        }
        pages.append(contentsOf: await makePages(from: images))
    }

    private func makePages(from images: [UIImage]) async -> [ScanPage] {
        await Task.detached(priority: .userInitiated) {
            images.map { raw in
                ScanPage.make(original: ImageProcessing.scaled(raw, maxDimension: ImageProcessing.maxSourceDimension))
            }
        }.value
    }

    // MARK: Editing

    func replace(_ page: ScanPage) {
        guard let index = pages.firstIndex(where: { $0.id == page.id }) else { return }
        pages[index] = page
    }

    func remove(_ id: UUID) {
        pages.removeAll { $0.id == id }
    }

    func move(_ id: UUID, by offset: Int) {
        guard let index = pages.firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard pages.indices.contains(target) else { return }
        pages.swapAt(index, target)
    }

    /// Drag-and-drop reorder: the dragged page takes the dropped-on page's position and the
    /// pages in between shift over by one.
    func move(_ id: UUID, onto targetID: UUID) {
        guard id != targetID,
              let from = pages.firstIndex(where: { $0.id == id }),
              let to = pages.firstIndex(where: { $0.id == targetID }) else { return }
        let page = pages.remove(at: from)
        pages.insert(page, at: to)
    }

    func applyFilterToAll(_ filter: PageFilter) async {
        guard !pages.isEmpty else { return }
        isBusy = true
        defer { isBusy = false }

        let current = pages
        pages = await Task.detached(priority: .userInitiated) {
            current.map { page in
                ScanPage.make(id: page.id, original: page.original, corners: page.corners, filter: filter)
            }
        }.value
    }

    // MARK: Export

    /// The finished PDF plus what was read from it: the words for searching and a suggested title.
    struct BuiltPDF {
        let data: Data
        let suggestedTitle: String?
        let searchText: String?
    }

    /// Text recognition is skipped when the user turned it off in Settings.
    func buildPDF() async -> BuiltPDF? {
        guard !pages.isEmpty else { return nil }
        isBusy = true
        defer {
            isBusy = false
            busyMessage = "Processing…"
        }

        let images = pages.map { $0.processed }

        var recognized: [PageText] = []
        if TextRecognizer.isEnabled {
            for (index, image) in images.enumerated() {
                busyMessage = images.count == 1 ? "Reading text…" : "Reading text… \(index + 1) of \(images.count)"
                recognized.append(await Task.detached(priority: .userInitiated) {
                    TextRecognizer.recognize(image)
                }.value)
            }
            busyMessage = "Building PDF…"
        }

        let texts = recognized
        let suggested = SmartTitle.suggest(from: texts)
        let data = await Task.detached(priority: .userInitiated) {
            PDFBuilder.makePDF(from: images, text: texts, title: suggested ?? "Scan")
        }.value
        guard let data else { return nil }

        let joined = texts.map(\.plain).joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return BuiltPDF(
            data: data,
            suggestedTitle: suggested,
            searchText: joined.isEmpty ? nil : String(joined.prefix(Self.maxSearchTextLength))
        )
    }

    /// Keeps the saved index small even for a long scanned book.
    private static let maxSearchTextLength = 30_000
}
