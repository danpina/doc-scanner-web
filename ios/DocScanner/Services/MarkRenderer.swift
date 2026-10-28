import UIKit

/// Burns signatures and typed text into a page image. Pure image work, safe off the main thread.
enum MarkRenderer {
    /// Expects a scale-1 image (everything in `ScanPage` is).
    static func draw(_ marks: [PageMark], on image: UIImage) -> UIImage {
        guard !marks.isEmpty else { return image }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let size = image.size

        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            image.draw(at: .zero)
            for mark in marks {
                draw(mark, pageSize: size, in: context.cgContext)
            }
        }
    }

    /// Each mark is drawn around its own center, so rotating it turns it in place.
    private static func draw(_ mark: PageMark, pageSize: CGSize, in context: CGContext) {
        context.saveGState()
        context.translateBy(x: mark.center.x * pageSize.width, y: mark.center.y * pageSize.height)
        context.rotate(by: CGFloat(mark.rotation) * .pi / 180)

        switch mark.kind {
        case .signature(let image):
            if image.size.width > 0 {
                let width = mark.size * pageSize.width
                let height = width * image.size.height / image.size.width
                // The signature is stored as a shape; the pen color is applied here.
                let tinted = image
                    .withRenderingMode(.alwaysTemplate)
                    .withTintColor(mark.color.uiColor, renderingMode: .alwaysOriginal)
                tinted.draw(in: CGRect(x: -width / 2, y: -height / 2, width: width, height: height))
            }

        case .text(let string):
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: mark.size * pageSize.width),
                .foregroundColor: mark.color.uiColor
            ]
            let textSize = (string as NSString).size(withAttributes: attributes)
            (string as NSString).draw(
                at: CGPoint(x: -textSize.width / 2, y: -textSize.height / 2),
                withAttributes: attributes
            )
        }
        context.restoreGState()
    }
}
