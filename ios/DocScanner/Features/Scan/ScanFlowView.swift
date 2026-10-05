import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import VisionKit

/// The scan workflow — capture, reorder/edit pages, export. Used both as the "New Scan"
/// screen for signed-in users and as the whole app in guest mode.
struct ScanFlowView: View {
    /// False in guest mode: export still works, but "Save to My Scans" isn't offered.
    let allowsSaving: Bool
    /// Label of the top-left button ("Cancel" in the account flow, "Log in" for guests).
    let closeTitle: String
    let onClose: () -> Void
    let onSaved: () -> Void

    @StateObject private var scan = ScanSession()
    @State private var showCamera = false
    @State private var showCameraUnavailable = false
    @State private var showFileImporter = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var editTarget: EditTarget?
    @State private var exportItem: ExportItem?
    @State private var allFilter: PageFilter = .original
    @State private var confirmLeave = false

    private struct EditTarget: Identifiable {
        let id: UUID
    }

    private struct ExportItem: Identifiable {
        let id = UUID()
        let data: Data
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    captureBar
                    if scan.pages.isEmpty {
                        emptyHint
                    } else {
                        filterBar
                        pageGrid
                    }
                }
                .padding()
            }
            .navigationTitle("New Scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(closeTitle) { leave() }
                }
            }
            .safeAreaInset(edge: .bottom) { exportBar }
            .overlay { busyOverlay }
        }
        .fullScreenCover(isPresented: $showCamera) {
            DocumentCameraView(
                onFinish: { images in
                    showCamera = false
                    Task { await scan.addScanned(images) }
                },
                onCancel: { showCamera = false }
            )
            .ignoresSafeArea()
        }
        .fullScreenCover(item: $editTarget) { target in
            if let page = scan.page(withID: target.id) {
                PageEditorView(
                    page: page,
                    onCancel: { editTarget = nil },
                    onDone: { updated in
                        scan.replace(updated)
                        editTarget = nil
                    }
                )
            }
        }
        .sheet(item: $exportItem) { item in
            ExportSheet(
                pdfData: item.data,
                pageCount: scan.pages.count,
                allowsSaving: allowsSaving,
                onSaved: {
                    exportItem = nil
                    onSaved()
                }
            )
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.pdf], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                Task { await scan.addPDFs(urls) }
            }
        }
        .onChange(of: photoItems) { items in
            guard !items.isEmpty else { return }
            photoItems = []
            Task { await scan.addPhotos(items) }
        }
        .alert("Camera not available", isPresented: $showCameraUnavailable) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Document scanning needs a physical iPhone — the camera isn't available in the Simulator. You can still add photos or a PDF.")
        }
        .alert("Something went wrong", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(scan.errorMessage ?? "")
        }
        .confirmationDialog("Leave and discard this scan?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Discard", role: .destructive) { onClose() }
            Button("Keep editing", role: .cancel) {}
        }
    }

    // MARK: Pieces

    private var captureBar: some View {
        HStack(spacing: 10) {
            Button {
                startCamera()
            } label: {
                Label("Scan", systemImage: "camera.viewfinder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            PhotosPicker(selection: $photoItems, matching: .images) {
                Label("Photos", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                showFileImporter = true
            } label: {
                Label("PDF", systemImage: "doc.richtext")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .controlSize(.large)
    }

    private var emptyHint: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Scan, or add photos or a PDF, to start.")
                .foregroundStyle(.secondary)
            if !allowsSaving {
                Text("Guest mode — log in to save scans to an account.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
        .padding(.top, 40)
    }

    private var filterBar: some View {
        HStack(spacing: 10) {
            Picker("Filter", selection: $allFilter) {
                ForEach(PageFilter.allCases) { filter in
                    Text(filter.label).tag(filter)
                }
            }
            .pickerStyle(.menu)

            Spacer()

            Button("Apply to all pages") {
                Task { await scan.applyFilterToAll(allFilter) }
            }
            .buttonStyle(.bordered)
        }
    }

    private var pageGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10)], spacing: 10) {
            ForEach(Array(scan.pages.enumerated()), id: \.element.id) { index, page in
                PageThumb(
                    page: page,
                    index: index,
                    count: scan.pages.count,
                    onEdit: { editTarget = EditTarget(id: page.id) },
                    onMoveEarlier: { scan.move(page.id, by: -1) },
                    onMoveLater: { scan.move(page.id, by: 1) },
                    onDelete: { scan.remove(page.id) }
                )
            }
        }
    }

    private var exportBar: some View {
        Button {
            Task { await startExport() }
        } label: {
            Text("Export PDF")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(scan.pages.isEmpty || scan.isBusy)
        .padding()
        .background(.bar)
    }

    @ViewBuilder
    private var busyOverlay: some View {
        if scan.isBusy {
            ZStack {
                Color.black.opacity(0.25).ignoresSafeArea()
                ProgressView("Processing…")
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { scan.errorMessage != nil },
            set: { shown in
                if !shown { scan.errorMessage = nil }
            }
        )
    }

    // MARK: Actions

    private func startCamera() {
        guard VNDocumentCameraViewController.isSupported else {
            showCameraUnavailable = true
            return
        }
        showCamera = true
    }

    private func leave() {
        if scan.pages.isEmpty {
            onClose()
        } else {
            confirmLeave = true
        }
    }

    private func startExport() async {
        guard let data = await scan.buildPDF(title: "Scan") else { return }
        exportItem = ExportItem(data: data)
    }
}

/// One page in the grid: thumbnail, its number, and the same ⬅ ✏️ 🗑 ➡ controls as the web app.
private struct PageThumb: View {
    let page: ScanPage
    let index: Int
    let count: Int
    let onEdit: () -> Void
    let onMoveEarlier: () -> Void
    let onMoveLater: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Color(.secondarySystemBackground)
                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                .overlay(
                    Image(uiImage: page.thumbnail)
                        .resizable()
                        .scaledToFit()
                        .padding(4)
                )
                .overlay(alignment: .topLeading) {
                    Text("\(index + 1)")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.6), in: Capsule())
                        .padding(6)
                }
                .contentShape(Rectangle())
                .onTapGesture(perform: onEdit)

            HStack {
                Button(action: onMoveEarlier) { Image(systemName: "chevron.left") }
                    .disabled(index == 0)
                Spacer()
                Button(action: onEdit) { Image(systemName: "pencil") }
                Spacer()
                Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
                Spacer()
                Button(action: onMoveLater) { Image(systemName: "chevron.right") }
                    .disabled(index == count - 1)
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(.tertiarySystemBackground))
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.25)))
    }
}
