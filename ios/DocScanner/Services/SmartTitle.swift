import Foundation

/// Suggests a title for a scan from its recognized text: the most prominent line near the top
/// of the first page (usually the sender or the kind of document), plus the date printed on it.
enum SmartTitle {
    private static let maxLength = 60

    static func suggest(from pages: [PageText]) -> String? {
        guard let first = pages.first(where: { !$0.lines.isEmpty }) else { return nil }

        let title = heading(in: first)
        let printed = printedDate(in: first.plain)

        switch (title, printed) {
        case let (title?, printed?): return clip("\(title) \(printed)")
        case let (title?, nil): return clip(title)
        case let (nil, printed?): return "Scan \(printed)"
        case (nil, nil): return nil
        }
    }

    // MARK: Heading

    /// The tallest line (a good stand-in for the biggest type) in the top part of the page
    /// that looks like words rather than numbers, addresses or links.
    private static func heading(in page: PageText) -> String? {
        let candidates = page.lines.filter { $0.box.midY > 0.55 && looksLikeHeading($0.text) }
        guard var best = candidates.first else { return nil }
        for line in candidates where line.box.height > best.box.height * 1.05 {
            best = line
        }
        return tidy(best.text)
    }

    private static func looksLikeHeading(_ text: String) -> Bool {
        guard text.count >= 4, text.count <= 45 else { return false }
        let letters = text.filter { $0.isLetter }.count
        guard Double(letters) / Double(text.count) >= 0.6 else { return false }
        let lowered = text.lowercased()
        return !lowered.contains("@") && !lowered.contains("http") && !lowered.contains("www.")
    }

    /// "RECHNUNG" reads better as "Rechnung"; characters a file name can't hold are dropped.
    private static func tidy(_ text: String) -> String {
        var result = text
        if result == result.uppercased() {
            result = result.capitalized
        }
        let reserved = CharacterSet(charactersIn: "/\\:?*\"<>|")
        result = result.components(separatedBy: reserved).joined(separator: " ")
        result = result.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return result.trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespaces))
    }

    // MARK: Date

    /// The first date on the page that states a year ("12.10.2026", "October 12, 2026"), as
    /// yyyy-MM-dd. Dates without a year ("Monday", "12 Oct") are ignored.
    private static func printedDate(in text: String) -> String? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        let latest = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()

        for match in detector.matches(in: text, options: [], range: range) {
            guard let date = match.date, let matchRange = Range(match.range, in: text) else { continue }
            let matched = String(text[matchRange])
            guard matched.range(of: "(19|20)\\d{2}", options: .regularExpression) != nil,
                  date <= latest else { continue }

            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: date)
        }
        return nil
    }

    private static func clip(_ title: String) -> String {
        title.count <= maxLength ? title : String(title.prefix(maxLength)).trimmingCharacters(in: .whitespaces)
    }
}
