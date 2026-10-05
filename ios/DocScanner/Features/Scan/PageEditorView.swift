import SwiftUI

/// Crop (drag the four corners), rotate and filter one page — the app's version of the
/// web app's "Adjust page" overlay.
struct PageEditorView: View {
    @StateObject private var model: PageEditorModel
    @State private var isSaving = false

    let onCancel: () -> Void
    let onDone: (ScanPage) -> Void

    init(page: ScanPage, onCancel: @escaping () -> Void, onDone: @escaping (ScanPage) -> Void) {
        _model = StateObject(wrappedValue: PageEditorModel(page: page))
        self.onCancel = onCancel
        self.onDone = onDone
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            CropCanvas(image: model.previewShown, imageSize: model.original.size, corners: $model.corners)
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
            controls
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
    }

    // MARK: Pieces

    private var topBar: some View {
        HStack {
            Button("Cancel") { onCancel() }
                .foregroundStyle(Color.white.opacity(0.85))
            Spacer()
            Text("Adjust page")
                .font(.headline)
            Spacer()
            Button {
                guard !isSaving else { return }
                Haptics.tap()
                isSaving = true
                Task {
                    let page = await model.commit()
                    onDone(page)
                }
            } label: {
                Group {
                    if isSaving {
                        ProgressView().tint(.white)
                    } else {
                        Text("Done").fontWeight(.bold)
                    }
                }
                .foregroundStyle(.white)
                .frame(minWidth: 52)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Theme.brandGradient, in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.35), lineWidth: 1))
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }

    private var controls: some View {
        VStack(spacing: 16) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(PageFilter.allCases) { filter in
                        filterChip(filter)
                    }
                }
                .padding(.horizontal, 16)
            }

            HStack(spacing: 12) {
                Button {
                    Haptics.tap()
                    model.rotate()
                } label: {
                    Label("Rotate", systemImage: "rotate.right")
                }
                .buttonStyle(.secondary)

                Button {
                    Haptics.tap()
                    model.resetCrop()
                } label: {
                    Label("Reset crop", systemImage: "crop")
                }
                .buttonStyle(.secondary)
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    /// A tiny preview of the page with this filter applied, so you can see the effect
    /// before choosing it.
    private func filterChip(_ filter: PageFilter) -> some View {
        let selected = model.filter == filter
        return Button {
            Haptics.select()
            model.setFilter(filter)
        } label: {
            VStack(spacing: 6) {
                Group {
                    if let preview = model.filterPreviews[filter] {
                        Image(uiImage: preview)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Color.gray
                    }
                }
                .frame(width: 64, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(selected ? Theme.amber : Color.white.opacity(0.25), lineWidth: selected ? 3 : 1)
                )

                Text(filter.label)
                    .font(.caption2.weight(selected ? .bold : .regular))
                    .foregroundStyle(selected ? Theme.amber : Color.white.opacity(0.8))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: 72)
            }
        }
        .buttonStyle(.plain)
    }
}
