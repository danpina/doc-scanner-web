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
                .padding(22)
            controls
        }
        .background(Color.black.ignoresSafeArea())
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
    }

    private var topBar: some View {
        HStack {
            Button("Cancel") { onCancel() }
            Spacer()
            Text("Adjust page").font(.headline)
            Spacer()
            Button {
                guard !isSaving else { return }
                isSaving = true
                Task {
                    let page = await model.commit()
                    onDone(page)
                }
            } label: {
                if isSaving {
                    ProgressView()
                } else {
                    Text("Done").fontWeight(.bold)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }

    private var controls: some View {
        VStack(spacing: 14) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(PageFilter.allCases) { filter in
                        Button {
                            model.setFilter(filter)
                        } label: {
                            Text(filter.label)
                                .font(.subheadline)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    model.filter == filter ? Color.accentColor : Color.white.opacity(0.15),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }

            HStack(spacing: 12) {
                Button {
                    model.rotate()
                } label: {
                    Label("Rotate", systemImage: "rotate.right")
                }
                .buttonStyle(.bordered)

                Button {
                    model.resetCrop()
                } label: {
                    Label("Reset crop", systemImage: "crop")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.bottom, 12)
    }
}
