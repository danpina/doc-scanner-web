import Foundation

/// Reads the text of an old Word document (.doc, Word 97 to 2003). Those files are "compound
/// files" (a small file system in one file) that hold the text in a piece table. Only the plain
/// text of the main document is read, not formatting, tables as such, pictures or other parts.
/// Password-protected files are not supported.
enum DocReader {
    static func text(from data: Data) -> String? {
        guard let file = CompoundFile(data: data),
              let wordData = file.stream(named: "WordDocument") else { return nil }

        let word = Bytes(wordData)
        guard word.u16(0) == 0xA5EC else { return nil }
        let flags = word.u16(0x0A)
        if flags & 0x0100 != 0 { return nil }   // encrypted

        guard let tableData = file.stream(named: flags & 0x0200 != 0 ? "1Table" : "0Table") else { return nil }
        let table = Bytes(tableData)

        // Walk the variable-length FIB header to the number of characters in the main text and
        // the location of the piece table (Clx).
        let shortCount = word.u16(32)
        let longCountPosition = 34 + shortCount * 2
        let longCount = word.u16(longCountPosition)
        let longs = longCountPosition + 2
        let pairCountPosition = longs + longCount * 4
        guard word.u16(pairCountPosition) > 33 else { return nil }

        let characterCount = word.u32(longs + 12)
        let clxOffset = word.u32(pairCountPosition + 2 + 33 * 8)
        let clxLength = word.u32(pairCountPosition + 2 + 33 * 8 + 4)
        guard clxLength > 0, clxOffset < table.count else { return nil }

        var units: [UInt16] = []
        var cursor = clxOffset
        let end = min(clxOffset + clxLength, table.count)
        while cursor < end {
            let kind = table.u8(cursor)
            if kind == 1 {
                cursor += 3 + table.u16(cursor + 1)    // formatting data, not needed
            } else if kind == 2 {
                units = pieces(table: table, word: word, start: cursor + 5, length: table.u32(cursor + 1))
                break
            } else {
                return nil
            }
        }
        guard !units.isEmpty else { return nil }

        if characterCount > 0, characterCount < units.count { units = Array(units.prefix(characterCount)) }
        let cleaned = String(decoding: cleanedUnits(units), as: UTF16.self)
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : cleaned
    }

    // MARK: Pieces

    /// The piece table lists where each run of text lives in the WordDocument stream, either as
    /// one byte per character (Windows-1252) or as two (UTF-16).
    private static func pieces(table: Bytes, word: Bytes, start: Int, length: Int) -> [UInt16] {
        guard length >= 16 else { return [] }
        let count = (length - 4) / 12
        let pieceTable = start + 4 * (count + 1)
        var units: [UInt16] = []

        for index in 0..<count {
            let first = table.u32(start + index * 4)
            let last = table.u32(start + (index + 1) * 4)
            guard last > first, last - first < 20_000_000 else { continue }
            let characters = last - first
            let fc = table.u32(pieceTable + index * 8 + 2)

            if fc & 0x4000_0000 != 0 {
                let offset = (fc & 0x3FFF_FFFF) / 2
                let stop = min(offset + characters, word.count)
                var position = offset
                while position < stop {
                    units.append(windows1252(word.u8(position)))
                    position += 1
                }
            } else {
                var position = fc
                let stop = min(fc + characters * 2, word.count - 1)
                while position < stop {
                    units.append(UInt16(word.u16(position)))
                    position += 2
                }
            }
        }
        return units
    }

    private static let windows1252High: [UInt16] = [
        0x20AC, 0x0081, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021,
        0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x008D, 0x017D, 0x008F,
        0x0090, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
        0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x009D, 0x017E, 0x0178
    ]

    private static func windows1252(_ byte: Int) -> UInt16 {
        (0x80...0x9F).contains(byte) ? windows1252High[byte - 0x80] : UInt16(byte)
    }

    /// Word marks paragraphs, cells, fields and pictures with control characters. Paragraph
    /// ends become line breaks, cell ends become tabs, and field instructions (such as the
    /// address behind a link) and picture markers are dropped.
    private static func cleanedUnits(_ units: [UInt16]) -> [UInt16] {
        var output: [UInt16] = []
        output.reserveCapacity(units.count)
        var fields: [Bool] = []   // true while a field is still showing its instruction part

        for unit in units {
            switch unit {
            case 0x13:
                fields.append(true)
            case 0x14:
                if !fields.isEmpty { fields[fields.count - 1] = false }
            case 0x15:
                if !fields.isEmpty { fields.removeLast() }
            default:
                guard !fields.contains(true) else { continue }
                switch unit {
                case 0x0D, 0x0B, 0x0C: output.append(0x0A)
                case 0x07: output.append(0x09)
                case 0x09, 0x0A: output.append(unit)
                case 0x1E: output.append(0x2D)
                case 0x1F: break
                case ..<0x20: break
                default: output.append(unit)
                }
            }
        }
        return output
    }
}

/// Bounds-checked little-endian reads, so a damaged file gives zeros instead of a crash.
private struct Bytes {
    let bytes: [UInt8]
    var count: Int { bytes.count }

    init(_ data: Data) { bytes = [UInt8](data) }

    func u8(_ index: Int) -> Int {
        index >= 0 && index < bytes.count ? Int(bytes[index]) : 0
    }
    func u16(_ index: Int) -> Int {
        u8(index) | u8(index + 1) << 8
    }
    func u32(_ index: Int) -> Int {
        u16(index) | u16(index + 2) << 16
    }
    func slice(_ start: Int, _ length: Int) -> [UInt8] {
        guard start >= 0, length > 0, start < bytes.count else { return [] }
        return Array(bytes[start..<min(start + length, bytes.count)])
    }
}

/// The "compound file" container (also called OLE or structured storage): numbered sectors
/// chained through an allocation table, a directory of named streams, and small streams packed
/// together in a mini stream.
private final class CompoundFile {
    private struct Entry {
        let name: String
        let type: Int
        let start: Int
        let size: Int
    }

    private let file: Bytes
    private var sectorSize = 512
    private var miniSectorSize = 64
    private var miniCutoff = 4096
    private var fat: [Int] = []
    private var miniFat: [Int] = []
    private var miniStream: [UInt8] = []
    private var entries: [Entry] = []

    private static let endOfChain = 0xFFFF_FFFA

    init?(data: Data) {
        file = Bytes(data)
        let signature: [UInt8] = [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]
        guard file.count > 512, Array(file.bytes.prefix(8)) == signature else { return nil }

        let sectorShift = file.u16(0x1E)
        let miniShift = file.u16(0x20)
        guard sectorShift == 9 || sectorShift == 12, miniShift >= 6, miniShift <= 9 else { return nil }
        sectorSize = 1 << sectorShift
        miniSectorSize = 1 << miniShift
        miniCutoff = file.u32(0x38)

        // Which sectors hold the allocation table: 109 are listed in the header, the rest in
        // a chain of extra sectors.
        var fatSectors: [Int] = (0..<109).map { file.u32(0x4C + $0 * 4) }
        var next = file.u32(0x44)
        var extra = file.u32(0x48)
        while extra > 0, next < Self.endOfChain, fatSectors.count < 1_000_000 {
            let base = sectorOffset(next)
            let perSector = sectorSize / 4 - 1
            fatSectors.append(contentsOf: (0..<perSector).map { file.u32(base + $0 * 4) })
            next = file.u32(base + perSector * 4)
            extra -= 1
        }

        for sector in fatSectors where sector < Self.endOfChain {
            let base = sectorOffset(sector)
            fat.append(contentsOf: (0..<(sectorSize / 4)).map { file.u32(base + $0 * 4) })
        }
        guard !fat.isEmpty else { return nil }

        let directory = chain(from: file.u32(0x30))
        for index in 0..<(directory.count / 128) {
            let base = index * 128
            let nameBytes = min(max(Self.u16(directory, base + 0x40) - 2, 0), 62)
            let name = String(
                decoding: stride(from: 0, to: nameBytes, by: 2).map { UInt16(Self.u16(directory, base + $0)) },
                as: UTF16.self
            )
            entries.append(Entry(
                name: name,
                type: Int(directory[base + 0x42]),
                start: Self.u32(directory, base + 0x74),
                size: Self.u32(directory, base + 0x78)
            ))
        }
        guard let root = entries.first else { return nil }

        miniStream = Array(chain(from: root.start).prefix(root.size))
        let miniFatBytes = chain(from: file.u32(0x3C))
        miniFat = (0..<(miniFatBytes.count / 4)).map { Self.u32(miniFatBytes, $0 * 4) }
    }

    func stream(named name: String) -> Data? {
        guard let entry = entries.first(where: { $0.type == 2 && $0.name == name }) else { return nil }
        if entry.size < miniCutoff {
            return Data(miniChain(from: entry.start).prefix(entry.size))
        }
        return Data(chain(from: entry.start).prefix(entry.size))
    }

    // MARK: Reading chains

    private func sectorOffset(_ sector: Int) -> Int {
        (sector + 1) * sectorSize
    }

    private func chain(from start: Int) -> [UInt8] {
        var output: [UInt8] = []
        var sector = start
        var steps = 0
        while sector < Self.endOfChain, sector < fat.count, steps <= fat.count {
            output.append(contentsOf: file.slice(sectorOffset(sector), sectorSize))
            sector = fat[sector]
            steps += 1
        }
        return output
    }

    private func miniChain(from start: Int) -> [UInt8] {
        var output: [UInt8] = []
        var sector = start
        var steps = 0
        while sector < Self.endOfChain, sector < miniFat.count, steps <= miniFat.count {
            let base = sector * miniSectorSize
            guard base < miniStream.count else { break }
            output.append(contentsOf: miniStream[base..<min(base + miniSectorSize, miniStream.count)])
            sector = miniFat[sector]
            steps += 1
        }
        return output
    }

    private static func u16(_ bytes: [UInt8], _ index: Int) -> Int {
        guard index >= 0, index + 1 < bytes.count else { return 0 }
        return Int(bytes[index]) | Int(bytes[index + 1]) << 8
    }

    private static func u32(_ bytes: [UInt8], _ index: Int) -> Int {
        u16(bytes, index) | u16(bytes, index + 2) << 16
    }
}
