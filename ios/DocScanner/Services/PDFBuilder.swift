import CoreText
import UIKit

enum PDFBuilder {
    /// Each page is sized to its own image's aspect ratio (long edge = A4's), so the scan fills
    /// the page edge-to-edge with no white borders — same rule as the web app's export.
    private static let longEdge: CGFloat = 841.89

    /// `text`, when given, holds the recognized text of each page (same order as `images`). It is
    /// written into the PDF invisibly, on top of each page's image, so the PDF can be searched
    /// and its text selected while the scan itself looks exactly as before.
    static func makePDF(from images: [UIImage], text: [PageText] = [], title: String) -> Data? {
        guard let first = images.first else { return nil }

        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: title,
            kCGPDFContextCreator as String: "Doc Scanner"
        ]

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect(for: first), format: format)
        return renderer.pdfData { context in
            for (index, image) in images.enumerated() {
                let rect = pageRect(for: image)
                context.beginPage(withBounds: rect, pageInfo: [:])
                compressed(image).draw(in: rect)
                if index < text.count {
                    drawInvisibleText(text[index], in: rect, context: context.cgContext)
                }
            }
        }
    }

    /// Each line is laid out over the spot where it was found, stretched to the width Vision
    /// measured, so selecting text highlights the right part of the page.
    private static func drawInvisibleText(_ page: PageText, in rect: CGRect, context: CGContext) {
        guard !page.lines.isEmpty else { return }

        context.saveGState()
        context.setTextDrawingMode(.invisible)
        for line in page.lines {
            let width = line.box.width * rect.width
            let height = line.box.height * rect.height
            guard width > 1, height > 1 else { continue }

            let font = UIFont(name: "Helvetica", size: height * 0.85) ?? UIFont.systemFont(ofSize: height * 0.85)
            let attributed = NSAttributedString(string: line.text, attributes: [.font: font])
            let ctLine = CTLineCreateWithAttributedString(attributed)
            let naturalWidth = CGFloat(CTLineGetTypographicBounds(ctLine, nil, nil, nil))
            guard naturalWidth > 0 else { continue }

            // The PDF context is flipped (origin top-left), so the text matrix flips the glyphs
            // back upright. Vision's boxes are bottom-left based; the baseline sits a little
            // above the bottom of the box.
            let x = rect.minX + line.box.minX * rect.width
            let baseline = rect.minY + (1 - line.box.minY) * rect.height - height * 0.2
            context.textMatrix = CGAffineTransform(a: width / naturalWidth, b: 0, c: 0, d: -1, tx: 0, ty: 0)
            context.textPosition = CGPoint(x: x, y: baseline)
            CTLineDraw(ctLine, context)
        }
        context.restoreGState()
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
