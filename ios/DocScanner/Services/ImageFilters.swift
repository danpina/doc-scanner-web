import UIKit

/// Per-pixel filters, a straight port of public/filters.js so a page looks the same in the
/// app as it does on the website.
enum ImageFilters {
    static func apply(_ filter: PageFilter, to image: UIImage) -> UIImage {
        guard filter != .original, let cgImage = image.cgImage else { return image }

        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return image }
        let bytesPerRow = width * 4

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let raw = context.data else { return image }

        // White underneath, so any transparent pixels end up white rather than black.
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        context.setFillColor(UIColor.white.cgColor)
        context.fill(rect)
        context.draw(cgImage, in: rect)

        let pixels = raw.bindMemory(to: UInt8.self, capacity: bytesPerRow * height)
        let count = width * height

        switch filter {
        case .original:
            break

        case .grayscale:
            for i in 0..<count {
                let offset = i * 4
                let gray = UInt8(luminance(pixels[offset], pixels[offset + 1], pixels[offset + 2]))
                pixels[offset] = gray
                pixels[offset + 1] = gray
                pixels[offset + 2] = gray
            }

        case .bw:
            let threshold = 150
            for i in 0..<count {
                let offset = i * 4
                let gray = luminance(pixels[offset], pixels[offset + 1], pixels[offset + 2])
                let value: UInt8 = gray > threshold ? 255 : 0
                pixels[offset] = value
                pixels[offset + 1] = value
                pixels[offset + 2] = value
            }

        case .enhance:
            enhance(pixels, count: count)

        case .bright:
            let amount = 45
            for i in 0..<count {
                let offset = i * 4
                for channel in 0..<3 {
                    pixels[offset + channel] = UInt8(min(255, Int(pixels[offset + channel]) + amount))
                }
            }
        }

        guard let output = context.makeImage() else { return image }
        return UIImage(cgImage: output)
    }

    private static func luminance(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> Int {
        (299 * Int(r) + 587 * Int(g) + 114 * Int(b)) / 1000
    }

    /// "Magic scan" look: grayscale, then stretch the contrast so the page background goes white
    /// and the text goes dark, without B&W's harsh cutoff. The darkest/lightest 2% of pixels are
    /// clipped before stretching so a stray shadow or glare spot doesn't squash the rest.
    private static func enhance(_ pixels: UnsafeMutablePointer<UInt8>, count: Int) {
        var gray = [UInt8](repeating: 0, count: count)
        var histogram = [Int](repeating: 0, count: 256)
        for i in 0..<count {
            let offset = i * 4
            let value = UInt8(luminance(pixels[offset], pixels[offset + 1], pixels[offset + 2]))
            gray[i] = value
            histogram[Int(value)] += 1
        }

        let clip = Int(Double(count) * 0.02)

        var low = 0
        var accumulated = 0
        while low < 255 {
            accumulated += histogram[low]
            if accumulated >= clip { break }
            low += 1
        }

        var high = 255
        accumulated = 0
        while high > 0 {
            accumulated += histogram[high]
            if accumulated >= clip { break }
            high -= 1
        }

        if high <= low {
            low = 0
            high = 255
        }

        let scale = 255.0 / Double(high - low)
        for i in 0..<count {
            let stretched = (Double(gray[i]) - Double(low)) * scale
            let value = UInt8(max(0, min(255, stretched)))
            let offset = i * 4
            pixels[offset] = value
            pixels[offset + 1] = value
            pixels[offset + 2] = value
        }
    }
}
