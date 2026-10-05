import UIKit

enum PDFBuilder {
    /// Each page is sized to its own image's aspect ratio (long edge = A4's), so the scan fills
    /// the page edge-to-edge with no white borders — same rule as the web app's export.
    private static let longEdge: CGFloat = 841.89

    static func makePDF(from images: [UIImage], title: String) -> Data? {
        guard let first = images.first else { return nil }

        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: title,
            kCGPDFContextCreator as String: "Doc Scanner"
        ]

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect(for: first), format: format)
        return renderer.pdfData { context in
            for image in images {
                let rect = pageRect(for: image)
                context.beginPage(withBounds: rect, pageInfo: [:])
                compressed(image).draw(in: rect)
            }
        }
    }

    private static func pageRect(for image: UIImage) -> CGRect {
        let width = image.size.width
        let height = image.size.height
        guard width > 0, height > 0 else {
            return CGRect(x: 0, y: 0, width: 595.28, height: longEdge)
        }
        if height >= width {
            return CGRect(x: 0, y: 0, width: longEdge * width / height, height: longEdge)
        }
        return CGRect(x: 0, y: 0, width: longEdge, height: longEdge * height / width)
    }

    /// Round-trips through JPEG so the PDF embeds compressed pixels instead of raw ones
    /// (a raw page would be several MB, and uploads are capped).
    private static func compressed(_ image: UIImage) -> UIImage {
        guard let data = image.jpegData(compressionQuality: 0.85), let jpeg = UIImage(data: data) else {
            return image
        }
        return jpeg
    }
}
