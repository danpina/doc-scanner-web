import Compression
import Foundation

/// Just enough of the ZIP format to pull one file out of a Word (.docx) document, which is a
/// ZIP archive. Handles stored and deflated entries; not ZIP64 or encrypted archives.
enum ZipArchive {
    private static let maxFileSize = 64 * 1024 * 1024

    static func file(named name: String, in data: Data) -> Data? {
        let bytes = [UInt8](data)
        guard bytes.count >= 22 else { return nil }

        func u16(_ index: Int) -> Int {
            Int(bytes[index]) | Int(bytes[index + 1]) << 8
        }
        func u32(_ index: Int) -> Int {
            u16(index) | u16(index + 2) << 16
        }

        // The end-of-central-directory record sits at the very end, before an optional comment.
        var end = -1
        var index = bytes.count - 22
        let lowest = max(0, bytes.count - 22 - 65_535)
        while index >= lowest {
            if u32(index) == 0x0605_4b50 {
                end = index
                break
            }
            index -= 1
        }
        guard end >= 0 else { return nil }

        let entryCount = u16(end + 10)
        var cursor = u32(end + 16)

        for _ in 0..<entryCount {
            guard cursor + 46 <= bytes.count, u32(cursor) == 0x0201_4b50 else { return nil }
            let method = u16(cursor + 10)
            let compressedSize = u32(cursor + 20)
            let size = u32(cursor + 24)
            let nameLength = u16(cursor + 28)
            let extraLength = u16(cursor + 30)
            let commentLength = u16(cursor + 32)
            let localOffset = u32(cursor + 42)

            let nameEnd = cursor + 46 + nameLength
            guard nameEnd <= bytes.count else { return nil }
            let entryName = String(decoding: bytes[(cursor + 46)..<nameEnd], as: UTF8.self)
            cursor = nameEnd + extraLength + commentLength
            guard entryName == name else { continue }

            guard localOffset + 30 <= bytes.count, u32(localOffset) == 0x0403_4b50 else { return nil }
            let start = localOffset + 30 + u16(localOffset + 26) + u16(localOffset + 28)
            guard start + compressedSize <= bytes.count, size <= maxFileSize else { return nil }
            let payload = Array(bytes[start..<(start + compressedSize)])

            switch method {
            case 0:
                return Data(payload)
            case 8:
                guard size > 0, !payload.isEmpty else { return nil }
                var output = [UInt8](repeating: 0, count: size)
                let written = compression_decode_buffer(&output, size, payload, payload.count, nil, COMPRESSION_ZLIB)
                return written == size ? Data(output) : nil
            default:
                return nil
            }
        }
        return nil
    }
}
