import UIKit

/// Burns signatures, text, covers and drawn strokes into a page image. Pure image work, safe off
/// the main thread.
enum MarkRenderer {
    /// Highlighter strokes are drawn at this strength, multiplied onto the page so the text
    /// underneath stays readable.
    static let highlighterAlpha: CGFloat = 0.5

    /// Expects a scale-1 image (everything in `ScanPage` is).
    static func draw(_ marks: [PageMark], on image: UIImage) -> UIImage {
        guard !marks.isEmpty else { return image }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let size = image.size

        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            image.draw(at: .zero)
            // Strokes go on first, so a cover or a signature always sits on top of them.
            for mark in marks where mark.isStroke {
                drawStroke(mark, pageSize: size, in: context.cgContext)
            }
            for mark in marks where !mark.isStroke {
                draw(mark, pageSize: size, in: context.cgContext)
            }
        }
    }

    /// A smooth line through the points, scaled to a page of `size`. Shared with the editor's
    /// live drawing so what you see is what gets saved.
    static func strokePath(_ points: [CGPoint], in size: CGSize) -> CGPath {
        let path = CGMutablePath()
        let scaled = points.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
        guard let first = scaled.first else { return path }

        path.move(to: first)
        guard scaled.count > 1 else {
            path.addLine(to: CGPoint(x: first.x + 0.1, y: first.y))
            return path
        }
        for index in 1..<scaled.count {
            let previous = scaled[index - 1]
            let point = scaled[index]
            let mid = CGPoint(x: (previous.x + point.x) / 2, y: (previous.y + point.y) / 2)
            path.addQuadCurve(to: mid, control: previous)
        }
        if let last = scaled.last {
            path.addLine(to: last)
        }
        return path
    }

    private static func drawStroke(_ mark: PageMark, pageSize: CGSize, in context: CGContext) {
        guard case .stroke(let points, let highlighter) = mark.kind else { return }

        context.saveGState()
        context.setLineWidth(mark.size * pageSize.width)
        context.setLineJoin(.round)
        if highlighter {
            context.setLineCap(.butt)
            context.setBlendMode(.multiply)
            context.setStrokeColor(mark.color.uiColor.withAlphaComponent(highlighterAlpha).cgColor)
        } else {
            context.setLineCap(.round)
            context.setStrokeColor(mark.color.uiColor.cgColor)
        }
        context.addPath(strokePath(points, in: pageSize))
        context.strokePath()
        context.restoreGState()
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

        case .cover(let aspect):
            let width = mark.size * pageSize.width
            context.setFillColor(mark.color.uiColor.cgColor)
            context.fill(CGRect(x: -width / 2, y: -width * aspect / 2, width: width, height: width * aspect))

        case .stroke:
            break
        }
        context.restoreGState()
    }
}
