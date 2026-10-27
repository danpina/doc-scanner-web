import UIKit

/// Burns signatures and typed text into a page image. Pure image work, safe off the main thread.
enum MarkRenderer {
    /// Ink colors: typed text is near-black, a signature is blue-black like a pen.
    static let textColor = UIColor(white: 0.08, alpha: 1)
    static let inkColor = UIColor(red: 0.05, green: 0.1, blue: 0.4, alpha: 1)

    /// Expects a scale-1 image (everything in `ScanPage` is).
    static func draw(_ marks: [PageMark], on image: UIImage) -> UIImage {
        guard !marks.isEmpty else { return image }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let size = image.size

        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(at: .zero)
            for mark in marks {
                draw(mark, pageSize: size)
            }
        }
    }

    private static func draw(_ mark: PageMark, pageSize: CGSize) {
        let centerX = mark.center.x * pageSize.width
        let centerY = mark.center.y * pageSize.height

        switch mark.kind {
        case .signature(let image):
            guard image.size.width > 0 else { return }
            let width = mark.size * pageSize.width
            let height = width * image.size.height / image.size.width
            image.draw(in: CGRect(x: centerX - width / 2, y: centerY - height / 2, width: width, height: height))

        case .text(let string):
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: mark.size * pageSize.width),
                .foregroundColor: textColor
            ]
            let textSize = (string as NSString).size(withAttributes: attributes)
            (string as NSString).draw(
                at: CGPoint(x: centerX - textSize.width / 2, y: centerY - textSize.height / 2),
                withAttributes: attributes
            )
        }
    }
}
