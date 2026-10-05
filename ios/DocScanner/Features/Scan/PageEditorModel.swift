import SwiftUI

/// Working copy of one page while the editor is open. Cancel just throws this away, so
/// (unlike the web editor) there's nothing to snapshot and restore.
@MainActor
final class PageEditorModel: ObservableObject {
    let pageID: UUID
    @Published private(set) var original: UIImage
    /// In `original` pixel coordinates.
    @Published var corners: [CGPoint]
    @Published private(set) var filter: PageFilter
    /// Small, filtered copy shown in the editor so dragging and filter changes stay snappy.
    @Published private(set) var previewShown: UIImage

    private var previewBase: UIImage
    private static let previewDimension: CGFloat = 900

    init(page: ScanPage) {
        pageID = page.id
        original = page.original
        corners = page.corners
        filter = page.filter
        let base = ImageProcessing.scaled(page.original, maxDimension: Self.previewDimension)
        previewBase = base
        previewShown = ImageFilters.apply(page.filter, to: base)
    }

    func setFilter(_ newFilter: PageFilter) {
        guard newFilter != filter else { return }
        filter = newFilter
        previewShown = ImageFilters.apply(newFilter, to: previewBase)
    }

    func rotate() {
        original = ImageProcessing.rotatedClockwise(original)
        // The old corners were measured against the pre-rotation image, so start from full frame.
        corners = ImageProcessing.fullFrame(for: original.size)
        previewBase = ImageProcessing.scaled(original, maxDimension: Self.previewDimension)
        previewShown = ImageFilters.apply(filter, to: previewBase)
    }

    func resetCrop() {
        corners = ImageProcessing.fullFrame(for: original.size)
    }

    /// Renders the full-resolution result off the main thread.
    func commit() async -> ScanPage {
        let id = pageID
        let source = original
        let quad = corners
        let chosen = filter
        return await Task.detached(priority: .userInitiated) {
            ScanPage.make(id: id, original: source, corners: quad, filter: chosen)
        }.value
    }
}
