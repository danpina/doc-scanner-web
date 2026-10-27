import UIKit
import Vision

/// One line of text found on a page.
struct RecognizedLine {
    let text: String
    /// Normalized to the page (0...1), origin at the bottom-left — Vision's convention.
    let box: CGRect
}

/// Everything recognized on one page, in reading order.
struct PageText {
    var lines: [RecognizedLine]

    static let empty = PageText(lines: [])

    var plain: String { lines.map(\.text).joined(separator: "\n") }
}

/// Reads the text on a page image with Apple's Vision framework. It runs entirely on the
/// iPhone; nothing is sent anywhere.
enum TextRecognizer {
    /// Off by default only if the user turned it off in Settings.
    static let settingKey = "recognizeText"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: settingKey) as? Bool ?? true
    }

    /// Never throws: a page that can't be read simply has no text.
    static func recognize(_ image: UIImage) -> PageText {
        guard let cgImage = image.cgImage else { return .empty }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
        do {
            try handler.perform([request])
        } catch {
            return .empty
        }

        let lines = (request.results ?? []).compactMap { observation -> RecognizedLine? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return RecognizedLine(text: text, box: observation.boundingBox)
        }
        return PageText(lines: lines)
    }
}
