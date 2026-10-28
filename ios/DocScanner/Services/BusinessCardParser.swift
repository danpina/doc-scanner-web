import Contacts
import Foundation

/// Turns the text read from a business card into a contact, ready for the user to check and
/// save. Business cards have no fixed layout, so this is a best guess: names, companies and job
/// titles are picked by shape and size, while phone numbers, e-mails, web addresses and
/// addresses come from Apple's data detectors.
enum BusinessCardParser {
    private static let emailRegex = try? NSRegularExpression(pattern: "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}")
    private static let companyRegex = try? NSRegularExpression(
        pattern: "\\b(GmbH|AG|Ltd|LLC|Inc|Corp|Co|SA|SL|Srl|BV|KG|UG|SpA|Limited|Sàrl|Sarl)\\b",
        options: [.caseInsensitive]
    )
    private static let prefixes: Set<String> = ["dr", "dr.", "prof", "prof.", "mr", "mr.", "ms", "ms.", "mrs", "mrs.", "herr", "frau", "mag.", "dipl.-ing."]

    static func contact(from page: PageText) -> CNMutableContact {
        let contact = CNMutableContact()
        let text = page.plain
        let nsText = text as NSString
        let whole = NSRange(location: 0, length: nsText.length)

        // E-mail addresses.
        var emails: [String] = []
        for match in emailRegex?.matches(in: text, range: whole) ?? [] {
            let email = nsText.substring(with: match.range)
            if !emails.contains(where: { $0.caseInsensitiveCompare(email) == .orderedSame }) {
                emails.append(email)
            }
        }

        // Phone numbers, web addresses and the postal address.
        var phones: [(number: String, label: String)] = []
        var websites: [String] = []
        var address: CNMutablePostalAddress?
        let types = NSTextCheckingResult.CheckingType.phoneNumber.rawValue
            | NSTextCheckingResult.CheckingType.link.rawValue
            | NSTextCheckingResult.CheckingType.address.rawValue
        if let detector = try? NSDataDetector(types: types) {
            for match in detector.matches(in: text, options: [], range: whole) {
                switch match.resultType {
                case .phoneNumber:
                    guard let number = match.phoneNumber else { continue }
                    let start = max(0, match.range.location - 14)
                    let before = nsText.substring(with: NSRange(location: start, length: match.range.location - start)).lowercased()
                    if before.contains("fax") { continue }
                    let isMobile = ["mob", "cell", "handy"].contains { before.contains($0) }
                    if !phones.contains(where: { $0.number == number }) {
                        phones.append((number, isMobile ? CNLabelPhoneNumberMobile : CNLabelWork))
                    }
                case .link:
                    let shown = nsText.substring(with: match.range)
                    if !shown.contains("@"), !websites.contains(shown) {
                        websites.append(shown)
                    }
                case .address:
                    if address == nil, let parts = match.addressComponents {
                        let postal = CNMutablePostalAddress()
                        postal.street = parts[.street] ?? ""
                        postal.city = parts[.city] ?? ""
                        postal.state = parts[.state] ?? ""
                        postal.postalCode = parts[.zip] ?? ""
                        postal.country = parts[.country] ?? ""
                        address = postal
                    }
                default:
                    break
                }
            }
        }

        // Name, job title and company come from the lines of text.
        let lines = page.lines
        let nameIndex = bestNameLine(in: lines)
        if let nameIndex {
            apply(name: lines[nameIndex].text, to: contact)

            let next = nameIndex + 1
            if next < lines.count, isPlainText(lines[next].text), lines[next].text.count <= 50, !isCompany(lines[next].text) {
                contact.jobTitle = lines[next].text
            }
        }
        let titleLine = contact.jobTitle
        let used = Set([nameIndex.map { lines[$0].text }, titleLine].compactMap { $0 })
        let companyLines = lines.filter { isPlainText($0.text) && !used.contains($0.text) && $0.text.count >= 3 }
        if let legal = companyLines.first(where: { isCompany($0.text) }) {
            contact.organizationName = legal.text
        } else if let tallest = companyLines.max(by: { $0.box.height < $1.box.height }) {
            contact.organizationName = tallest.text
        }

        contact.phoneNumbers = phones.map {
            CNLabeledValue(label: $0.label, value: CNPhoneNumber(stringValue: $0.number))
        }
        contact.emailAddresses = emails.map { CNLabeledValue(label: CNLabelWork, value: $0 as NSString) }
        contact.urlAddresses = websites.map { CNLabeledValue(label: CNLabelWork, value: $0 as NSString) }
        if let address {
            contact.postalAddresses = [CNLabeledValue<CNPostalAddress>(label: CNLabelWork, value: address)]
        }
        return contact
    }

    // MARK: Lines

    /// The tallest line (biggest print) made of two to four words with no digits, links or
    /// legal-form words: usually the person's name.
    private static func bestNameLine(in lines: [RecognizedLine]) -> Int? {
        var best: Int?
        for (index, line) in lines.enumerated() {
            let text = line.text
            let words = text.split(separator: " ")
            guard (2...4).contains(words.count), text.count <= 40,
                  isPlainText(text), !isCompany(text),
                  words.allSatisfy({ $0.first?.isLetter == true }) else { continue }
            if let current = best, lines[current].box.height >= line.box.height { continue }
            best = index
        }
        return best
    }

    /// Words only: no digits, e-mail or web addresses, which belong to the contact details.
    private static func isPlainText(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return text.rangeOfCharacter(from: .decimalDigits) == nil
            && !lowered.contains("@") && !lowered.contains("www") && !lowered.contains(".com")
    }

    private static func isCompany(_ text: String) -> Bool {
        let range = NSRange(location: 0, length: (text as NSString).length)
        return companyRegex?.firstMatch(in: text, range: range) != nil
    }

    private static func apply(name: String, to contact: CNMutableContact) {
        var tokens = name.split(separator: " ").map(String.init)
        if name == name.uppercased() {
            tokens = tokens.map { $0.capitalized }
        }
        if let first = tokens.first, prefixes.contains(first.lowercased()), tokens.count > 2 {
            contact.namePrefix = first
            tokens.removeFirst()
        }
        guard let given = tokens.first else { return }
        contact.givenName = given
        if tokens.count > 1 {
            contact.familyName = tokens[tokens.count - 1]
        }
        if tokens.count > 2 {
            contact.middleName = tokens[1..<(tokens.count - 1)].joined(separator: " ")
        }
    }
}
