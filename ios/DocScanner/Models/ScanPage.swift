import UIKit

/// Same five filters as the web app (public/filters.js).
enum PageFilter: String, CaseIterable, Identifiable {
    case original
    case grayscale
    case bw
    case enhance
    case bright

    var id: String { rawValue }

    var label: String {
        switch self {
        case .original: return "Original"
        case .grayscale: return "Grayscale"
        case .bw: return "Black & White"
        case .enhance: return "Enhance"
        case .bright: return "Brighten"
        }
    }
}

/// One page of the scan in progress. Mirrors the web app's page object:
/// the source image, four crop corners over it, a filter, and the cached result.
struct ScanPage: Identifiable {
    let id: UUID
    /// Orientation-baked, scale-1, long edge <= `ImageProcessing.maxSourceDimension`.
    var original: UIImage
    /// Crop corners (top-left, top-right, bottom-right, bottom-left) in `original` pixel coordinates.
    var corners: [CGPoint]
    var filter: PageFilter
    /// Perspective-corrected + filtered — this is what ends up in the PDF.
    var processed: UIImage
    var thumbnail: UIImage

    /// Builds a page and renders its result. Pure image work, so it's safe to call off the main thread.
    static func make(
        id: UUID = UUID(),
        original: UIImage,
        corners: [CGPoint]? = nil,
        filter: PageFilter = .original
    ) -> ScanPage {
        let corners = corners ?? ImageProcessing.fullFrame(for: original.size)
        let processed = ImageProcessing.render(original: original, corners: corners, filter: filter)
        return ScanPage(
            id: id,
            original: original,
            corners: corners,
            filter: filter,
            processed: processed,
            thumbnail: ImageProcessing.scaled(processed, maxDimension: 360)
        )
    }
}
