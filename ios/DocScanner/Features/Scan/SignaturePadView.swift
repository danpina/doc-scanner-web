import SwiftUI

/// A white pad to draw a signature with a finger. "Use signature" returns it as a tightly
/// cropped image with a transparent background.
struct SignaturePadView: View {
    let onUse: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var strokes: [[CGPoint]] = []
    @State private var current: [CGPoint] = []

    private static let lineWidth: CGFloat = 4
    private static let ink = Color(red: 0.05, green: 0.1, blue: 0.4)

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Sign inside the box with your finger.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Canvas { context, _ in
                    for stroke in strokes + [current] {
                        context.stroke(
                            Self.path(through: stroke),
                            with: .color(Self.ink),
                            style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round, lineJoin: .round)
                        )
                    }
                }
                .frame(height: 220)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(alignment: .bottom) {
                    // The line you sign on.
                    Rectangle()
                        .fill(Color.gray.opacity(0.35))
                        .frame(height: 1)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 44)
                        .allowsHitTesting(false)
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            current.append(value.location)
                        }
                        .onEnded { _ in
                            if current.count > 1 {
                                strokes.append(current)
                            }
                            current = []
                        }
                )

                HStack(spacing: 12) {
                    Button("Clear") {
                        strokes = []
                        current = []
                    }
                    .buttonStyle(.secondary)
                    .disabled(strokes.isEmpty)

                    Button("Use signature") {
                        if let image = renderedImage() {
                            Haptics.success()
                            onUse(image)
                            dismiss()
                        }
                    }
                    .buttonStyle(.primary)
                    .disabled(strokes.isEmpty)
                }

                Text("Your signature is kept only on this iPhone.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)
            }
            .padding(16)
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Your signature")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: Drawing

    /// A smooth line through the points (each segment curves through the midpoints).
    private static func path(through points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count > 1 else { return path }

        for index in 1..<points.count {
            let previous = points[index - 1]
            let point = points[index]
            let mid = CGPoint(x: (previous.x + point.x) / 2, y: (previous.y + point.y) / 2)
            path.addQuadCurve(to: mid, control: previous)
        }
        if let last = points.last {
            path.addLine(to: last)
        }
        return path
    }

    /// The strokes on a transparent background, cropped to their bounds.
    private func renderedImage() -> UIImage? {
        let points = strokes.flatMap { $0 }
        guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(), let maxY = points.map(\.y).max() else { return nil }

        let padding = Self.lineWidth * 2
        let bounds = CGRect(x: minX - padding, y: minY - padding,
                            width: maxX - minX + padding * 2, height: maxY - minY + padding * 2)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 3
        format.opaque = false

        return UIGraphicsImageRenderer(size: bounds.size, format: format).image { context in
            let cg = context.cgContext
            cg.translateBy(x: -bounds.minX, y: -bounds.minY)
            cg.setStrokeColor(UIColor(red: 0.05, green: 0.1, blue: 0.4, alpha: 1).cgColor)
            cg.setLineWidth(Self.lineWidth)
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            for stroke in strokes {
                cg.addPath(Self.path(through: stroke).cgPath)
                cg.strokePath()
            }
        }
    }
}
