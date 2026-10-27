import UIKit

/// Puts the front and back of an ID card on one A4 page, one above the other, as large as the
/// page allows and centered. Pure image work, so it is safe off the main thread.
enum IDCardComposer {
    private static let pageMM = CGSize(width: 210, height: 297)
    /// The widest a card may be: the page minus a 20 mm margin on each side.
    private static let maxCardWidthMM: CGFloat = 170
    /// Two cards plus the gap must fit between 25 mm margins, even for a tall card.
    private static let maxCardHeightMM: CGFloat = 120
    private static let gapMM: CGFloat = 12

    /// A bit above `ImageProcessing.maxSourceDimension` so the small print on a card stays sharp.
    static let longEdgePixels: CGFloat = 3000

    static func compose(front: UIImage, back: UIImage?) -> UIImage {
        let pxPerMM = longEdgePixels / pageMM.height
        let size = CGSize(width: (pageMM.width * pxPerMM).rounded(), height: longEdgePixels)

        var cards = [landscape(front)]
        if let back { cards.append(landscape(back)) }

        // Work out every card's rectangle first so the whole block can be centered on the page.
        let gap = gapMM * pxPerMM
        let sizes: [CGSize] = cards.map { card in
            var width = maxCardWidthMM * pxPerMM
            var height = width * card.size.height / card.size.width
            let tallest = maxCardHeightMM * pxPerMM
            if height > tallest {
                height = tallest
                width = height * card.size.width / card.size.height
            }
            return CGSize(width: width, height: height)
        }
        let blockHeight = sizes.reduce(0) { $0 + $1.height } + gap * CGFloat(sizes.count - 1)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            var y = (size.height - blockHeight) / 2
            for (card, cardSize) in zip(cards, sizes) {
                let rect = CGRect(
                    x: (size.width - cardSize.width) / 2,
                    y: y,
                    width: cardSize.width,
                    height: cardSize.height
                )
                card.draw(in: rect)

                let border = UIBezierPath(rect: rect)
                border.lineWidth = max(1, 0.3 * pxPerMM)
                UIColor(white: 0.6, alpha: 1).setStroke()
                border.stroke()

                y += cardSize.height + gap
            }
        }
    }

    /// Cards are scanned lengthwise; a portrait capture is turned to match.
    private static func landscape(_ image: UIImage) -> UIImage {
        image.size.height > image.size.width ? ImageProcessing.rotatedClockwise(image) : image
    }
}
