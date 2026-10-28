import UIKit

/// The pen colors offered for signatures and text.
enum MarkColor: String, CaseIterable, Identifiable {
    case black
    case blue
    case red
    case green

    var id: String { rawValue }

    var uiColor: UIColor {
        switch self {
        case .black: return UIColor(white: 0.08, alpha: 1)
        case .blue: return UIColor(red: 0.05, green: 0.15, blue: 0.62, alpha: 1)
        case .red: return UIColor(red: 0.82, green: 0.1, blue: 0.12, alpha: 1)
        case .green: return UIColor(red: 0.08, green: 0.5, blue: 0.22, alpha: 1)
        }
    }

    var label: String { rawValue.capitalized }
}

/// Something placed on a page by the user: a signature or a piece of typed text. Positions and
/// sizes are relative to the page, so the same mark lands in the same spot on the small preview
/// and on the full-size page.
struct PageMark: Identifiable {
    enum Kind {
        case signature(UIImage)
        case text(String)
    }

    let id: UUID
    var kind: Kind
    /// Center of the mark, 0...1 across and down the page.
    var center: CGPoint
    /// Signature: width as a fraction of the page width. Text: font size as a fraction of the page width.
    var size: CGFloat
    var color: MarkColor
    /// Clockwise, in degrees (-180...180).
    var rotation: Double

    init(
        id: UUID = UUID(),
        kind: Kind,
        center: CGPoint = CGPoint(x: 0.5, y: 0.5),
        size: CGFloat,
        color: MarkColor = .black,
        rotation: Double = 0
    ) {
        self.id = id
        self.kind = kind
        self.center = center
        self.size = size
        self.color = color
        self.rotation = rotation
    }

    var isSignature: Bool {
        if case .signature = kind { return true }
        return false
    }

    /// How far "larger" and "smaller" can go.
    var sizeRange: ClosedRange<CGFloat> {
        isSignature ? 0.08...0.9 : 0.015...0.2
    }

    static func signature(_ image: UIImage) -> PageMark {
        PageMark(kind: .signature(image), center: CGPoint(x: 0.65, y: 0.8), size: 0.35, color: .blue)
    }

    static func text(_ string: String, size: CGFloat = 0.035) -> PageMark {
        PageMark(kind: .text(string), size: size)
    }
}
