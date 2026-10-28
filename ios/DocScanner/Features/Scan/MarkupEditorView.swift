import SwiftUI

/// Working copy of one page's marks while the editor is open. Cancel throws it away.
@MainActor
final class MarkupModel: ObservableObject {
    let page: ScanPage
    /// The page without any marks, small enough to keep dragging smooth. Nil while it renders.
    @Published private(set) var base: UIImage?
    @Published var marks: [PageMark]
    @Published var selectedID: UUID?

    private var dragOrigin: CGPoint?
    private static let previewDimension: CGFloat = 1400

    init(page: ScanPage) {
        self.page = page
        marks = page.marks
    }

    /// The page as it is without marks, rebuilt from the original so existing marks aren't
    /// painted twice.
    func loadBase() async {
        let source = page
        base = await Task.detached(priority: .userInitiated) {
            let clean = ImageProcessing.render(original: source.original, corners: source.corners, filter: source.filter)
            return ImageProcessing.scaled(clean, maxDimension: MarkupModel.previewDimension)
        }.value
    }

    var selected: PageMark? {
        marks.first { $0.id == selectedID }
    }

    func add(_ mark: PageMark) {
        marks.append(mark)
        selectedID = mark.id
    }

    func remove(_ id: UUID) {
        marks.removeAll { $0.id == id }
        if selectedID == id { selectedID = nil }
    }

    func resize(_ id: UUID, factor: CGFloat) {
        guard let index = marks.firstIndex(where: { $0.id == id }) else { return }
        let range = marks[index].sizeRange
        marks[index].size = min(max(marks[index].size * factor, range.lowerBound), range.upperBound)
    }

    func setColor(_ id: UUID, _ color: MarkColor) {
        guard let index = marks.firstIndex(where: { $0.id == id }) else { return }
        marks[index].color = color
    }

    /// Snaps to upright when the slider is close to it, so 0° is easy to hit.
    func setRotation(_ id: UUID, degrees: Double) {
        guard let index = marks.firstIndex(where: { $0.id == id }) else { return }
        marks[index].rotation = abs(degrees) < 3 ? 0 : degrees
    }

    func rotateQuarterTurn(_ id: UUID) {
        guard let index = marks.firstIndex(where: { $0.id == id }) else { return }
        var turned = marks[index].rotation + 90
        if turned > 180 { turned -= 360 }
        marks[index].rotation = turned
    }

    func replaceSignature(_ id: UUID, with image: UIImage) {
        guard let index = marks.firstIndex(where: { $0.id == id }) else { return }
        marks[index].kind = .signature(image)
    }

    func drag(_ id: UUID, by translation: CGSize, in pageSize: CGSize) {
        guard let index = marks.firstIndex(where: { $0.id == id }),
              pageSize.width > 0, pageSize.height > 0 else { return }
        if dragOrigin == nil {
            dragOrigin = marks[index].center
            selectedID = id
        }
        guard let origin = dragOrigin else { return }
        marks[index].center = CGPoint(
            x: min(max(origin.x + translation.width / pageSize.width, 0), 1),
            y: min(max(origin.y + translation.height / pageSize.height, 0), 1)
        )
    }

    func endDrag() {
        dragOrigin = nil
    }

    /// Renders the full-resolution page with the marks on it, off the main thread.
    func commit() async -> ScanPage {
        let source = page
        let chosen = marks
        return await Task.detached(priority: .userInitiated) {
            ScanPage.make(id: source.id, original: source.original, corners: source.corners, filter: source.filter, marks: chosen)
        }.value
    }
}

/// Sign and fill in one page: place your signature, type text, add today's date or a tick,
/// drag everything where it belongs.
struct MarkupEditorView: View {
    @StateObject private var model: MarkupModel
    @State private var isSaving = false
    @State private var showPad = false
    @State private var padReplacesID: UUID?
    @State private var showTextAlert = false
    @State private var draftText = ""

    let onCancel: () -> Void
    let onDone: (ScanPage) -> Void

    init(page: ScanPage, onCancel: @escaping () -> Void, onDone: @escaping (ScanPage) -> Void) {
        _model = StateObject(wrappedValue: MarkupModel(page: page))
        self.onCancel = onCancel
        self.onDone = onDone
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            pageArea
            toolbar
        }
        .background(
            LinearGradient(
                colors: [Color.black, Theme.blueDeep.opacity(0.55)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .task { await model.loadBase() }
        .sheet(isPresented: $showPad) {
            SignaturePadView { image in
                SignatureStore.save(image)
                if let id = padReplacesID {
                    model.replaceSignature(id, with: image)
                } else {
                    model.add(.signature(image))
                }
                padReplacesID = nil
            }
        }
        .alert("Add text", isPresented: $showTextAlert) {
            TextField("Text", text: $draftText)
            Button("Add") {
                let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    model.add(.text(trimmed))
                }
                draftText = ""
            }
            Button("Cancel", role: .cancel) { draftText = "" }
        } message: {
            Text("Type what you want to write on the page, then drag it into place.")
        }
    }

    // MARK: Pieces

    private var topBar: some View {
        HStack {
            Button("Cancel") { onCancel() }
                .foregroundStyle(Color.white.opacity(0.85))
            Spacer()
            Text("Sign & fill in")
                .font(.headline)
            Spacer()
            Button {
                guard !isSaving, model.base != nil else { return }
                Haptics.tap()
                isSaving = true
                Task {
                    let page = await model.commit()
                    onDone(page)
                }
            } label: {
                if isSaving {
                    ProgressView().tint(.white)
                } else {
                    Text("Done").bold()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var pageArea: some View {
        GeometryReader { proxy in
            if let base = model.base {
                let size = fitted(base.size, in: proxy.size)
                ZStack {
                    Image(uiImage: base)
                        .resizable()
                        .frame(width: size.width, height: size.height)
                        .onTapGesture { model.selectedID = nil }

                    ForEach(model.marks) { mark in
                        markView(mark, pageSize: size)
                    }
                }
                .frame(width: size.width, height: size.height)
                .coordinateSpace(name: "page")
                .clipped()
                .shadow(color: .black.opacity(0.4), radius: 10)
                .frame(width: proxy.size.width, height: proxy.size.height)
            } else {
                ProgressView()
                    .tint(.white)
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func markView(_ mark: PageMark, pageSize: CGSize) -> some View {
        let selected = mark.id == model.selectedID
        Group {
            switch mark.kind {
            case .signature(let image):
                Image(uiImage: image)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(Color(mark.color.uiColor))
                    .frame(width: mark.size * pageSize.width)
            case .text(let string):
                Text(string)
                    .font(.system(size: mark.size * pageSize.width))
                    .foregroundColor(Color(mark.color.uiColor))
                    .fixedSize()
            }
        }
        .padding(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Theme.blueLight, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                .opacity(selected ? 1 : 0)
        )
        .contentShape(Rectangle())
        .rotationEffect(.degrees(mark.rotation))
        .position(x: mark.center.x * pageSize.width, y: mark.center.y * pageSize.height)
        .gesture(
            // Measured in the page's space, so a turned mark still follows the finger.
            DragGesture(coordinateSpace: .named("page"))
                .onChanged { value in
                    model.drag(mark.id, by: value.translation, in: pageSize)
                }
                .onEnded { _ in model.endDrag() }
        )
        .onTapGesture { model.selectedID = mark.id }
    }

    private var toolbar: some View {
        VStack(spacing: 10) {
            if let selected = model.selected {
                colorAndAngle(for: selected)
                HStack(spacing: 10) {
                    toolButton("Smaller", icon: "minus.magnifyingglass") {
                        model.resize(selected.id, factor: 1 / 1.15)
                    }
                    toolButton("Larger", icon: "plus.magnifyingglass") {
                        model.resize(selected.id, factor: 1.15)
                    }
                    toolButton("Turn 90°", icon: "rotate.right") {
                        model.rotateQuarterTurn(selected.id)
                    }
                    if selected.isSignature {
                        toolButton("Redraw", icon: "pencil.tip") {
                            padReplacesID = selected.id
                            showPad = true
                        }
                    }
                    toolButton("Delete", icon: "trash", tint: .red) {
                        Haptics.warning()
                        model.remove(selected.id)
                    }
                }
            }

            HStack(spacing: 10) {
                toolButton("Signature", icon: "signature") {
                    if let saved = SignatureStore.load() {
                        model.add(.signature(saved))
                    } else {
                        padReplacesID = nil
                        showPad = true
                    }
                }
                toolButton("Text", icon: "textformat") {
                    showTextAlert = true
                }
                toolButton("Date", icon: "calendar") {
                    model.add(.text(Date().formatted(date: .numeric, time: .omitted)))
                }
                toolButton("Tick", icon: "checkmark") {
                    model.add(.text("✓", size: 0.05))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 14)
    }

    /// Pen color dots and a slider to turn the selected item to any angle.
    private func colorAndAngle(for mark: PageMark) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 14) {
                ForEach(MarkColor.allCases) { color in
                    Button {
                        Haptics.select()
                        model.setColor(mark.id, color)
                    } label: {
                        Circle()
                            .fill(Color(color.uiColor))
                            .frame(width: 30, height: 30)
                            .overlay(Circle().strokeBorder(Color.white, lineWidth: mark.color == color ? 3 : 1).opacity(mark.color == color ? 1 : 0.4))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(color.label)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                Image(systemName: "rotate.right")
                    .font(.footnote)
                Slider(
                    value: Binding(
                        get: { mark.rotation },
                        set: { model.setRotation(mark.id, degrees: $0) }
                    ),
                    in: -180...180,
                    step: 1
                )
                Text("\(Int(mark.rotation))°")
                    .font(.footnote.monospacedDigit())
                    .frame(width: 44, alignment: .trailing)
            }
        }
    }

    private func toolButton(_ title: String, icon: String, tint: Color = .white, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                Text(title)
                    .font(.caption2)
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// The largest size with the image's shape that fits in `available`.
    private func fitted(_ image: CGSize, in available: CGSize) -> CGSize {
        guard image.width > 0, image.height > 0, available.width > 0, available.height > 0 else { return .zero }
        let scale = min(available.width / image.width, available.height / image.height)
        return CGSize(width: image.width * scale, height: image.height * scale)
    }
}
