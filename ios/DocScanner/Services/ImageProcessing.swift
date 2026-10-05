import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// Geometry + rendering helpers. Everything here works in *pixels* (images are always
/// redrawn at scale 1), and none of it touches UI state, so it's safe off the main thread.
enum ImageProcessing {
    /// Same cap the web app uses when it downsizes camera photos.
    static let maxSourceDimension: CGFloat = 2000

    private static let ciContext = CIContext()

    // MARK: Geometry

    /// Top-left, top-right, bottom-right, bottom-left.
    static func fullFrame(for size: CGSize) -> [CGPoint] {
        [
            CGPoint(x: 0, y: 0),
            CGPoint(x: size.width, y: 0),
            CGPoint(x: size.width, y: size.height),
            CGPoint(x: 0, y: size.height)
        ]
    }

    static func isFullFrame(_ corners: [CGPoint], size: CGSize) -> Bool {
        guard corners.count == 4 else { return true }
        let full = fullFrame(for: size)
        for (corner, expected) in zip(corners, full) {
            if abs(corner.x - expected.x) > 1 || abs(corner.y - expected.y) > 1 { return false }
        }
        return true
    }

    // MARK: Resizing / rotating

    /// Redraws the image at scale 1 with its orientation baked in, shrunk so the long edge is
    /// at most `maxDimension`. Also flattens any transparency onto white.
    static func scaled(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        let longest = max(pixelWidth, pixelHeight)
        guard longest > 0 else { return image }

        let factor = min(1, maxDimension / longest)
        let target = CGSize(
            width: max(1, (pixelWidth * factor).rounded()),
            height: max(1, (pixelHeight * factor).rounded())
        )
        let rect = CGRect(origin: .zero, size: target)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { context in
            context.cgContext.setFillColor(UIColor.white.cgColor)
            context.cgContext.fill(rect)
            image.draw(in: rect)
        }
    }

    /// 90° clockwise. Expects a scale-1, orientation-up image (everything in `ScanPage` is).
    static func rotatedClockwise(_ image: UIImage) -> UIImage {
        let newSize = CGSize(width: image.size.height, height: image.size.width)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: newSize, format: format).image { context in
            let cg = context.cgContext
            cg.translateBy(x: newSize.width, y: 0)
            cg.rotate(by: .pi / 2)
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    // MARK: Perspective crop

    /// Flattens the quad described by `corners` into a rectangle — the same job as the web
    /// app's hand-rolled homography, done here by Core Image.
    static func warp(_ image: UIImage, corners: [CGPoint]) -> UIImage? {
        guard corners.count == 4, let cgImage = image.cgImage else { return nil }
        let height = CGFloat(cgImage.height)

        // Core Image's origin is bottom-left, UIKit's is top-left.
        func flipped(_ point: CGPoint) -> CGPoint {
            CGPoint(x: point.x, y: height - point.y)
        }

        let filter = CIFilter.perspectiveCorrection()
        filter.inputImage = CIImage(cgImage: cgImage)
        filter.topLeft = flipped(corners[0])
        filter.topRight = flipped(corners[1])
        filter.bottomRight = flipped(corners[2])
        filter.bottomLeft = flipped(corners[3])

        guard let output = filter.outputImage else { return nil }
        let extent = output.extent
        guard !extent.isInfinite, extent.width > 1, extent.height > 1,
              let result = ciContext.createCGImage(output, from: extent) else { return nil }
        return UIImage(cgImage: result)
    }

    // MARK: Full page render

    /// Crop (if the corners were moved) and then filter.
    static func render(original: UIImage, corners: [CGPoint], filter: PageFilter) -> UIImage {
        var base = original
        if !isFullFrame(corners, size: original.size),
           let warped = warp(original, corners: corners) {
            base = warped
        }
        return ImageFilters.apply(filter, to: base)
    }
}
