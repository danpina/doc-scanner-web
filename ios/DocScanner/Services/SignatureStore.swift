import UIKit

/// The user's drawn signature, kept as a transparent PNG in the app's private storage so it can
/// be placed on any page with one tap. Like scans, it never leaves the iPhone.
enum SignatureStore {
    private static var url: URL? {
        guard let support = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ) else { return nil }
        return support.appendingPathComponent("signature.png")
    }

    static func load() -> UIImage? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    static func save(_ image: UIImage) {
        guard let url, let data = image.pngData() else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func delete() {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
