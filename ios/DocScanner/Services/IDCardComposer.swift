import UIKit

/// Puts the front and back of an ID card on one A4 page at real size (85.6 mm wide), the way a
/// photocopy would. Pure image work, so it is safe off the main thread.
enum IDCardComposer {
    private static let pageMM = CGSize(width: 210, height: 297)
    private static let cardWidthMM: CGFloat = 85.6
    private static let maxCardHeightMM: CGFloat = 60
    private static let topMarginMM: CGFloat = 30
    private static let gapMM: CGFloat = 14

    /// A bit above `ImageProcessing.maxSourceDimension` so the small print on a card stays sharp.
    static let longEdgePixels: CGFloat = 3000

    static func compose(front: UIImage, back: UIImage?) -> UIImage {
        let pxPerMM = longEdgePixels / pageMM.height
        let size = CGSize(width: (pageMM.width * pxPerMM).rounded(), height: longEdgePixels)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            var y = topMarginMM * pxPerMM
            var cards = [front]
            if let back { cards.append(back) }

            for card in cards {
                let upright = landscape(card)
                var width = cardWidthMM * pxPerMM
                var height = width * upright.size.height / upright.size.width
                let tallest = maxCardHeightMM * pxPerMM
                if height > tallest {
                    height = tallest
                    width = height * upright.size.width / upright.size.height
                }

                let rect = CGRect(x: (size.width - width) / 2, y: y, width: width, height: height)
                upright.draw(in: rect)

                let border = UIBezierPath(rect: rect)
                border.lineWidth = max(1, 0.3 * pxPerMM)
                UIColor(white: 0.6, alpha: 1).setStroke()
                border.stroke()

                y += height + gapMM * pxPerMM
            }
        }
    }

    /// Cards are scanned lengthwise; a portrait capture is turned to match.
    private static func landscape(_ image: UIImage) -> UIImage {
        image.size.height > image.size.width ? ImageProcessing.rotatedClockwise(image) : image
    }
}
