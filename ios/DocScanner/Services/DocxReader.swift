import UIKit

/// Reads the text of a Word (.docx) document: paragraphs, headings, bold / italic / underline,
/// colors, alignment, bullet points and tables as tab-separated rows. Pictures, headers, footers
/// and page layout are not carried over.
enum DocxReader {
    static func attributedText(from data: Data) -> NSAttributedString? {
        guard let xml = ZipArchive.file(named: "word/document.xml", in: data) else { return nil }

        let builder = Builder()
        let parser = XMLParser(data: xml)
        parser.shouldResolveExternalEntities = false
        parser.delegate = builder
        _ = parser.parse()
        return builder.result.length > 0 ? builder.result : nil
    }

    private final class Builder: NSObject, XMLParserDelegate {
        let result = NSMutableAttributedString()

        private var paragraph = NSMutableAttributedString()
        private var styleName = ""
        private var alignment: NSTextAlignment = .natural
        private var isListItem = false
        private var cellDepth = 0

        private var inRun = false
        private var inText = false
        private var bold = false
        private var italic = false
        private var underline = false
        private var runSize: CGFloat?
        private var runColor: UIColor?

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            let value = attributeDict["w:val"]
            switch elementName {
            case "w:p":
                paragraph = NSMutableAttributedString()
                styleName = ""
                alignment = .natural
                isListItem = false
            case "w:pStyle":
                styleName = (value ?? "").lowercased()
            case "w:jc":
                switch value ?? "" {
                case "center": alignment = .center
                case "right", "end": alignment = .right
                case "both": alignment = .justified
                default: alignment = .natural
                }
            case "w:numPr":
                isListItem = true
            case "w:r":
                inRun = true
                bold = false
                italic = false
                underline = false
                runSize = nil
                runColor = nil
            case "w:b":
                bold = Self.isOn(value)
            case "w:i":
                italic = Self.isOn(value)
            case "w:u":
                underline = (value ?? "single") != "none"
            case "w:sz":
                if let value, let halfPoints = Double(value) { runSize = CGFloat(halfPoints / 2) }
            case "w:color":
                if let value, value != "auto" { runColor = UIColor(hex: value) }
            case "w:t":
                inText = true
            case "w:tab" where inRun:
                append("\t")
            case "w:br" where inRun, "w:cr" where inRun:
                append("\n")
            case "w:tc":
                cellDepth += 1
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if inText { append(string) }
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?) {
            switch elementName {
            case "w:t":
                inText = false
            case "w:r":
                inRun = false
            case "w:p":
                finishParagraph()
            case "w:tc":
                cellDepth = max(0, cellDepth - 1)
                result.append(NSAttributedString(string: "\t", attributes: [.font: Self.font(size: Self.bodySize)]))
            case "w:tr":
                result.append(NSAttributedString(string: "\n", attributes: [.font: Self.font(size: Self.bodySize)]))
            case "w:tbl":
                result.append(NSAttributedString(string: "\n", attributes: [.font: Self.font(size: Self.bodySize)]))
            default:
                break
            }
        }

        // MARK: Building

        private static let bodySize: CGFloat = 11

        private var headingSize: CGFloat? {
            if styleName == "title" || styleName == "titel" { return 22 }
            // Word names its heading styles "Heading1"… (or "Kop1", "Überschrift1" in other languages).
            for prefix in ["heading", "kop", "überschrift"] where styleName.hasPrefix(prefix) {
                if let level = Int(styleName.dropFirst(prefix.count)) {
                    return [CGFloat(18), 15, 13][min(max(level, 1), 3) - 1]
                }
            }
            return nil
        }

        private func append(_ text: String) {
            let heading = headingSize
            let size = runSize ?? heading ?? Self.bodySize
            var attributes: [NSAttributedString.Key: Any] = [
                .font: Self.font(size: size, bold: bold || heading != nil, italic: italic),
                .foregroundColor: runColor ?? UIColor.black
            ]
            if underline { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            paragraph.append(NSAttributedString(string: text, attributes: attributes))
        }

        private func finishParagraph() {
            if isListItem {
                paragraph.insert(
                    NSAttributedString(string: "•  ", attributes: [.font: Self.font(size: Self.bodySize), .foregroundColor: UIColor.black]),
                    at: 0
                )
            }

            let style = NSMutableParagraphStyle()
            style.alignment = alignment
            style.paragraphSpacing = cellDepth > 0 ? 0 : 6
            style.paragraphSpacingBefore = headingSize == nil ? 0 : 8
            if isListItem {
                style.firstLineHeadIndent = 12
                style.headIndent = 24
            }
            paragraph.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: paragraph.length))

            // Inside a table cell paragraphs stay on one line; the cell and row ends add the breaks.
            let ending = cellDepth > 0 ? " " : "\n"
            paragraph.append(NSAttributedString(string: ending, attributes: [.font: Self.font(size: Self.bodySize)]))
            result.append(paragraph)
            paragraph = NSMutableAttributedString()
        }

        private static func isOn(_ value: String?) -> Bool {
            guard let value else { return true }
            return value != "0" && value != "false" && value != "none"
        }

        private static func font(size: CGFloat, bold: Bool = false, italic: Bool = false) -> UIFont {
            let base = UIFont.systemFont(ofSize: size)
            var traits: UIFontDescriptor.SymbolicTraits = []
            if bold { traits.insert(.traitBold) }
            if italic { traits.insert(.traitItalic) }
            guard !traits.isEmpty, let descriptor = base.fontDescriptor.withSymbolicTraits(traits) else { return base }
            return UIFont(descriptor: descriptor, size: size)
        }
    }
}

private extension UIColor {
    /// "RRGGBB" as used by Word; nil-safe fallback to black.
    convenience init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        self.init(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}
