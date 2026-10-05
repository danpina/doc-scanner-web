import SwiftUI

/// The image with a draggable four-corner quad on top. Corners are stored in *image pixel*
/// coordinates and converted to/from view coordinates here, so the same corners work no
/// matter how large the on-screen preview is.
struct CropCanvas: View {
    let image: UIImage
    let imageSize: CGSize
    @Binding var corners: [CGPoint]

    @State private var dragStart: [CGPoint]?

    private let spaceName = "cropCanvas"

    var body: some View {
        GeometryReader { proxy in
            let rect = displayRect(in: proxy.size)
            ZStack(alignment: .topLeading) {
                Image(uiImage: image)
                    .resizable()
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)

                // Everything outside the selection is dimmed, like a scanner's crop guide.
                dimPath(in: rect)
                    .fill(Color.black.opacity(0.5), style: FillStyle(eoFill: true))
                    .allowsHitTesting(false)

                quadPath(in: rect)
                    .stroke(Theme.amber, style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
                    .allowsHitTesting(false)

                ForEach(0..<4, id: \.self) { index in
                    handle(index, in: rect)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .coordinateSpace(name: spaceName)
        }
    }

    // MARK: Handles

    private func handle(_ index: Int, in rect: CGRect) -> some View {
        let center = corners.indices.contains(index) ? viewPoint(corners[index], in: rect) : CGPoint.zero
        return Circle()
            .fill(Color.white)
            .frame(width: 24, height: 24)
            .overlay(Circle().stroke(Theme.amber, lineWidth: 4))
            .shadow(color: Color.black.opacity(0.45), radius: 3, x: 0, y: 1)
            // A full 44pt touch target around the 24pt dot.
            .frame(width: 44, height: 44)
            .contentShape(Circle())
            .position(center)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(spaceName))
                    .onChanged { value in
                        if dragStart == nil {
                            dragStart = corners
                            Haptics.select()
                        }
                        guard let start = dragStart,
                              start.indices.contains(index),
                              corners.indices.contains(index) else { return }
                        // Move by the finger's travel from where the drag began, so grabbing a
                        // handle off-center doesn't make the corner jump under the finger.
                        let origin = viewPoint(start[index], in: rect)
                        let moved = CGPoint(
                            x: origin.x + value.translation.width,
                            y: origin.y + value.translation.height
                        )
                        corners[index] = imagePoint(moved, in: rect)
                    }
                    .onEnded { _ in dragStart = nil }
            )
    }

    private func quadPath(in rect: CGRect) -> Path {
        var path = Path()
        guard corners.count == 4 else { return path }
        path.move(to: viewPoint(corners[0], in: rect))
        path.addLine(to: viewPoint(corners[1], in: rect))
        path.addLine(to: viewPoint(corners[2], in: rect))
        path.addLine(to: viewPoint(corners[3], in: rect))
        path.closeSubpath()
        return path
    }

    /// The whole image rectangle plus the quad; filled with the even-odd rule this leaves the
    /// quad itself clear and covers everything around it.
    private func dimPath(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        path.addPath(quadPath(in: rect))
        return path
    }

    // MARK: Coordinates

    /// Where the aspect-fit image sits inside the container.
    private func displayRect(in container: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, container.width > 0, container.height > 0 else {
            return .zero
        }
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (container.width - size.width) / 2,
            y: (container.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    private func viewPoint(_ point: CGPoint, in rect: CGRect) -> CGPoint {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        return CGPoint(
            x: rect.minX + point.x / imageSize.width * rect.width,
            y: rect.minY + point.y / imageSize.height * rect.height
        )
    }

    private func imagePoint(_ point: CGPoint, in rect: CGRect) -> CGPoint {
        guard rect.width > 0, rect.height > 0 else { return .zero }
        let nx = min(max((point.x - rect.minX) / rect.width, 0), 1)
        let ny = min(max((point.y - rect.minY) / rect.height, 0), 1)
        return CGPoint(x: nx * imageSize.width, y: ny * imageSize.height)
    }
}
