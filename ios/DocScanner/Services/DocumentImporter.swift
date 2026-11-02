import UIKit
import UniformTypeIdentifiers

/// Turns files other than PDFs and pictures into page images, so a text file, a Word document,
/// an RTF or a web page can be handled like any other scan (filters, signing, OCR, sharing).
/// Text and basic formatting are kept; pictures, headers and exact page layout are not.
enum DocumentImporter {
    enum Kind {
        case pdf
        case image
        case plainText(monospaced: Bool)
        case rtf
        case html
        case docx
        case unsupported
    }

    /// What the Files picker offers besides PDFs and images.
    static var pickerTypes: [UTType] {
        var types: [UTType] = [.pdf, .image, .text]
        if let docx = UTType("org.openxmlformats.wordprocessingml.document") { types.append(docx) }
        return types
    }

    static func kind(of url: URL) -> Kind {
        switch url.pathExtension.lowercased() {
        case "pdf":
            return .pdf
        case "txt", "text", "md", "markdown":
            return .plainText(monospaced: false)
        case "csv", "tsv", "log", "json", "xml":
            return .plainText(monospaced: true)
        case "rtf":
            return .rtf
        case "html", "htm", "xhtml":
            return .html
        case "docx":
            return .docx
        default:
            if let type = UTType(filenameExtension: url.pathExtension) {
                if type.conforms(to: .image) { return .image }
                if type.conforms(to: .pdf) { return .pdf }
                if type.conforms(to: .plainText) { return .plainText(monospaced: false) }
            }
            return .unsupported
        }
    }

    /// Reads the file into styled text. Runs on the main actor because the web page reader of
    /// iOS requires it.
    @MainActor
    static func attributedText(from url: URL, kind: Kind) -> NSAttributedString? {
        switch kind {
        case .plainText(let monospaced):
            guard let string = decodedString(from: url) else { return nil }
            let font = monospaced
                ? UIFont.monospacedSystemFont(ofSize: 9.5, weight: .regular)
                : UIFont.systemFont(ofSize: 11.5)
            let style = NSMutableParagraphStyle()
            style.lineSpacing = 2
            return NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: UIColor.black, .paragraphStyle: style])
        case .rtf:
            guard let data = try? Data(contentsOf: url) else { return nil }
            let text = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
            return text.map(withDefaultColor)
        case .html:
            guard let string = decodedString(from: url) else { return nil }
            let text = try? NSAttributedString(
                data: Data(withoutOutsideResources(string).utf8),
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
            )
            return text.map(withDefaultColor)
        case .docx:
            guard let data = try? Data(contentsOf: url) else { return nil }
            return DocxReader.attributedText(from: data)
        case .pdf, .image, .unsupported:
            return nil
        }
    }

    // MARK: Pages

    private static let pageSize = CGSize(width: 595, height: 842)   // A4 in points
    private static let margin: CGFloat = 54
    private static let maxPages = 200

    /// Lays the text out on A4 pages and draws each one to an image.
    static func pageImages(from text: NSAttributedString) -> [UIImage] {
        guard !text.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }

        let textSize = CGSize(width: pageSize.width - margin * 2, height: pageSize.height - margin * 2)
        let storage = NSTextStorage(attributedString: text)
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)

        var containers: [NSTextContainer] = []
        while containers.count < maxPages {
            let container = NSTextContainer(size: textSize)
            container.lineFragmentPadding = 0
            layout.addTextContainer(container)
            containers.append(container)
            layout.ensureLayout(for: container)
            let glyphs = layout.glyphRange(for: container)
            if glyphs.length == 0 || NSMaxRange(glyphs) >= layout.numberOfGlyphs { break }
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 2.4
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: pageSize, format: format)

        return containers.compactMap { container in
            let glyphs = layout.glyphRange(for: container)
            guard glyphs.length > 0 else { return nil }
            return renderer.image { context in
                UIColor.white.setFill()
                context.fill(CGRect(origin: .zero, size: pageSize))
                let origin = CGPoint(x: margin, y: margin)
                layout.drawBackground(forGlyphRange: glyphs, at: origin)
                layout.drawGlyphs(forGlyphRange: glyphs, at: origin)
            }
        }
    }

    // MARK: Helpers

    /// Text files come in many encodings; try the file's own marker first, then common fallbacks.
    private static func decodedString(from url: URL) -> String? {
        var encoding = String.Encoding.utf8
        if let string = try? String(contentsOf: url, usedEncoding: &encoding) { return string }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return String(data: data, encoding: .windowsCP1252) ?? String(data: data, encoding: .isoLatin1)
    }

    /// The web page reader may fetch pictures and styles a page points to on the internet. Doc
    /// Scanner never contacts the network for a document, so those parts are removed first.
    private static func withoutOutsideResources(_ html: String) -> String {
        let patterns = [
            "<script[\\s\\S]*?</script>",
            "<iframe[\\s\\S]*?</iframe>",
            "<(img|link|embed|object|source|video|audio)\\b[^>]*>"
        ]
        var cleaned = html
        for pattern in patterns {
            cleaned = cleaned.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }
        return cleaned
    }

    /// Text without a color is drawn black on the white page.
    private static func withDefaultColor(_ text: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: text)
        let whole = NSRange(location: 0, length: result.length)
        result.enumerateAttribute(.foregroundColor, in: whole) { value, range, _ in
            if value == nil { result.addAttribute(.foregroundColor, value: UIColor.black, range: range) }
        }
        return result
    }
}
