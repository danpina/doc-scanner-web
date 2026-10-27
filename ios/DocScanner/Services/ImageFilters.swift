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

        case .clean:
            clean(pixels, width: width, height: height)

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

    /// Removes shadows and uneven light, like a flatbed scanner would: estimates how bright the
    /// blank paper is at every spot (a high brightness percentile per small block, smoothed and
    /// interpolated), then divides each pixel by it. Paper comes out white, text stays dark, and a
    /// shadow across the page disappears. Result is grayscale.
    private static func clean(_ pixels: UnsafeMutablePointer<UInt8>, width: Int, height: Int) {
        let block = max(16, min(width, height) / 32)
        let gridWidth = (width + block - 1) / block
        let gridHeight = (height + block - 1) / block

        // 1. Paper brightness per block: the 85th percentile, so printing doesn't pull it down.
        var grid = [Float](repeating: 255, count: gridWidth * gridHeight)
        var histogram = [Int](repeating: 0, count: 256)
        for blockY in 0..<gridHeight {
            for blockX in 0..<gridWidth {
                for level in 0..<256 { histogram[level] = 0 }
                let startX = blockX * block
                let endX = min(width, startX + block)
                let startY = blockY * block
                let endY = min(height, startY + block)

                var total = 0
                for y in startY..<endY {
                    for x in startX..<endX {
                        let offset = (y * width + x) * 4
                        histogram[luminance(pixels[offset], pixels[offset + 1], pixels[offset + 2])] += 1
                        total += 1
                    }
                }

                let target = Int(Double(total) * 0.85)
                var accumulated = 0
                var paper = 255
                for level in 0..<256 {
                    accumulated += histogram[level]
                    if accumulated >= target {
                        paper = level
                        break
                    }
                }
                grid[blockY * gridWidth + blockX] = Float(max(paper, 60))
            }
        }

        // 2. Smooth the estimate so block edges don't show.
        for _ in 0..<2 {
            var smoothed = grid
            for blockY in 0..<gridHeight {
                for blockX in 0..<gridWidth {
                    var sum: Float = 0
                    var n: Float = 0
                    for dy in -1...1 {
                        for dx in -1...1 {
                            let nx = blockX + dx
                            let ny = blockY + dy
                            if nx >= 0, nx < gridWidth, ny >= 0, ny < gridHeight {
                                sum += grid[ny * gridWidth + nx]
                                n += 1
                            }
                        }
                    }
                    smoothed[blockY * gridWidth + blockX] = sum / n
                }
            }
            grid = smoothed
        }

        // 3. Divide every pixel by the paper brightness at its spot (bilinear between block centers).
        func cell(_ position: Int, size: Int, limit: Int) -> (Int, Int, Float) {
            let f = (Float(position) + 0.5) / Float(size) - 0.5
            let low = max(0, min(limit - 1, Int(f.rounded(.down))))
            let high = min(limit - 1, low + 1)
            return (low, high, max(0, min(1, f - Float(low))))
        }
        let columns = (0..<width).map { cell($0, size: block, limit: gridWidth) }

        for y in 0..<height {
            let (row0, row1, ty) = cell(y, size: block, limit: gridHeight)
            for x in 0..<width {
                let (col0, col1, tx) = columns[x]
                let top = grid[row0 * gridWidth + col0] * (1 - tx) + grid[row0 * gridWidth + col1] * tx
                let bottom = grid[row1 * gridWidth + col0] * (1 - tx) + grid[row1 * gridWidth + col1] * tx
                let paper = top * (1 - ty) + bottom * ty

                let offset = (y * width + x) * 4
                let gray = Float(luminance(pixels[offset], pixels[offset + 1], pixels[offset + 2]))
                // Paper (ratio near 1) goes to white; ink below about a third of the paper
                // brightness goes to black.
                let ratio = gray / paper
                let value = UInt8(max(0, min(255, (ratio - 0.35) / 0.55 * 255)))
                pixels[offset] = value
                pixels[offset + 1] = value
                pixels[offset + 2] = value
            }
        }
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
