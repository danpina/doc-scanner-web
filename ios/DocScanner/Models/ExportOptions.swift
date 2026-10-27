import UIKit

/// How much the page images are shrunk and compressed inside the PDF.
enum OutputQuality: String, CaseIterable, Identifiable {
    case small
    case medium
    case best

    var id: String { rawValue }

    var label: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .best: return "Best"
        }
    }

    var hint: String {
        switch self {
        case .small: return "Smallest file, good for email. Text stays readable."
        case .medium: return "A balance of size and sharpness."
        case .best: return "Sharpest pages, largest file."
        }
    }

    /// Longest side of a page image in pixels.
    var maxPixels: CGFloat {
        switch self {
        case .small: return 1100
        case .medium: return 1500
        case .best: return IDCardComposer.longEdgePixels // never shrinks a normal scan (those stop at 2000 px)
        }
    }

    var jpegQuality: CGFloat {
        switch self {
        case .small: return 0.5
        case .medium: return 0.7
        case .best: return 0.85
        }
    }
}

/// The size of every page in the PDF.
enum PageLayout: String, CaseIterable, Identifiable {
    case original
    case a4
    case letter

    var id: String { rawValue }

    var label: String {
        switch self {
        case .original: return "As scanned"
        case .a4: return "A4"
        case .letter: return "Letter"
        }
    }

    var hint: String {
        switch self {
        case .original: return "Each page has the shape of its scan, edge to edge."
        case .a4: return "Every page is A4, with the scan centered on it."
        case .letter: return "Every page is US Letter, with the scan centered on it."
        }
    }

    /// Portrait size in points; nil keeps each scan's own shape.
    var portraitSize: CGSize? {
        switch self {
        case .original: return nil
        case .a4: return CGSize(width: 595.28, height: 841.89)
        case .letter: return CGSize(width: 612, height: 792)
        }
    }
}

struct ExportOptions: Equatable {
    static let qualityKey = "exportQuality"
    static let layoutKey = "exportLayout"

    var quality: OutputQuality = .best
    var layout: PageLayout = .original

    /// The choices the user made last time (the export screen keeps them in UserDefaults).
    static var stored: ExportOptions {
        let defaults = UserDefaults.standard
        return ExportOptions(
            quality: OutputQuality(rawValue: defaults.string(forKey: qualityKey) ?? "") ?? .best,
            layout: PageLayout(rawValue: defaults.string(forKey: layoutKey) ?? "") ?? .original
        )
    }
}
