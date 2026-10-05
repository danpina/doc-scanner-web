import PhotosUI
import SwiftUI

/// The scan in progress: an ordered list of pages plus everything you can do to them before
/// exporting. The heavy image work runs off the main thread; `isBusy` drives a spinner.
@MainActor
final class ScanSession: ObservableObject {
    @Published private(set) var pages: [ScanPage] = []
    @Published var isBusy = false
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

    func buildPDF(title: String) async -> Data? {
        guard !pages.isEmpty else { return nil }
        isBusy = true
        defer { isBusy = false }

        let images = pages.map { $0.processed }
        return await Task.detached(priority: .userInitiated) {
            PDFBuilder.makePDF(from: images, title: title)
        }.value
    }
}
