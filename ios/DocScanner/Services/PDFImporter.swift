import PDFKit
import UIKit

/// Turns an existing PDF into page images, so its pages can be reordered, filtered and
/// re-cropped alongside scanned photos (the web app's "Add PDF").
enum PDFImporter {
    static func pageImages(from url: URL) -> [UIImage] {
        guard let document = PDFDocument(url: url) else { return [] }

        var images: [UIImage] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }

            var box = page.bounds(for: .mediaBox)
            if page.rotation % 180 != 0 {
                box = CGRect(x: 0, y: 0, width: box.height, height: box.width)
            }
            guard box.width > 0, box.height > 0 else { continue }

            // Render so the long edge lands near the same cap photos are shrunk to.
            let longest = max(box.width, box.height)
            let renderScale = min(3, max(1, ImageProcessing.maxSourceDimension / longest))
            let size = CGSize(
                width: (box.width * renderScale).rounded(),
                height: (box.height * renderScale).rounded()
            )

            let rendered = page.thumbnail(of: size, for: .mediaBox)
            images.append(ImageProcessing.scaled(rendered, maxDimension: ImageProcessing.maxSourceDimension))
        }
        return images
    }
}
