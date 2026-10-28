import UIKit

/// The colors offered for signatures, text, covers, pens and highlighters.
enum MarkColor: String, CaseIterable, Identifiable {
    case black
    case blue
    case red
    case green
    case white
    case yellow
    case pink
    case cyan
    case lime

    var id: String { rawValue }

    var uiColor: UIColor {
        switch self {
        case .black: return UIColor(white: 0.08, alpha: 1)
        case .blue: return UIColor(red: 0.05, green: 0.15, blue: 0.62, alpha: 1)
        case .red: return UIColor(red: 0.82, green: 0.1, blue: 0.12, alpha: 1)
        case .green: return UIColor(red: 0.08, green: 0.5, blue: 0.22, alpha: 1)
        case .white: return .white
        case .yellow: return UIColor(red: 1.0, green: 0.88, blue: 0.0, alpha: 1)
        case .pink: return UIColor(red: 1.0, green: 0.4, blue: 0.7, alpha: 1)
        case .cyan: return UIColor(red: 0.1, green: 0.8, blue: 1.0, alpha: 1)
        case .lime: return UIColor(red: 0.45, green: 0.9, blue: 0.2, alpha: 1)
        }
    }

    var label: String { rawValue.capitalized }

    /// What the color dots offer for each kind of mark.
    static let forInk: [MarkColor] = [.black, .blue, .red, .green, .white]
    static let forCover: [MarkColor] = [.black, .white]
    static let forHighlighter: [MarkColor] = [.yellow, .lime, .pink, .cyan]
}

/// Something placed on a page by the user: a signature, typed text, a cover box, or a pen or
/// highlighter stroke. Positions and sizes are relative to the page, so the same mark lands in
/// the same spot on the small preview and on the full-size page.
struct PageMark: Identifiable {
    enum Kind {
        case signature(UIImage)
        case text(String)
        /// A solid box to hide something; `aspect` is its height divided by its width.
        case cover(aspect: CGFloat)
        /// A drawn line through points given as 0...1 across and down the page.
        case stroke(points: [CGPoint], highlighter: Bool)
    }

    let id: UUID
    var kind: Kind
    /// Center of the mark, 0...1 across and down the page. Unused by strokes.
    var center: CGPoint
    /// Signature and cover: width as a fraction of the page width. Text: font size as a fraction
    /// of the page width. Stroke: line width as a fraction of the page width.
    var size: CGFloat
    var color: MarkColor
    /// Clockwise, in degrees (-180...180). Unused by strokes.
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

    var isCover: Bool {
        if case .cover = kind { return true }
        return false
    }

    var isStroke: Bool {
        if case .stroke = kind { return true }
        return false
    }

    /// How far "larger" and "smaller" can go.
    var sizeRange: ClosedRange<CGFloat> {
        switch kind {
        case .signature: return 0.08...0.9
        case .cover: return 0.04...1.0
        case .text: return 0.015...0.2
        case .stroke: return size...size
        }
    }

    /// Colors the color dots offer for this mark.
    var palette: [MarkColor] {
        isCover ? MarkColor.forCover : MarkColor.forInk
    }

    static func signature(_ image: UIImage) -> PageMark {
        PageMark(kind: .signature(image), center: CGPoint(x: 0.65, y: 0.8), size: 0.35, color: .blue)
    }

    static func text(_ string: String, size: CGFloat = 0.035) -> PageMark {
        PageMark(kind: .text(string), size: size)
    }

    static func cover() -> PageMark {
        PageMark(kind: .cover(aspect: 0.12), size: 0.4, color: .black)
    }

    static func stroke(points: [CGPoint], highlighter: Bool, color: MarkColor) -> PageMark {
        PageMark(kind: .stroke(points: points, highlighter: highlighter), size: highlighter ? 0.035 : 0.006, color: color)
    }
}
