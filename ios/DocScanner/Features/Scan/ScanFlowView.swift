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
                VStack(spacing: 18) {
                    if !allowsSaving {
                        guestBanner
                    }
                    if scan.pages.isEmpty {
                        captureHero
                    } else {
                        addBar
                        filterBar
                        pageGrid
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("New Scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(closeTitle) { leave() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !scan.pages.isEmpty {
                    exportBar
                }
            }
            .overlay { busyOverlay }
        }
        .fullScreenCover(isPresented: $showCamera) {
            DocumentCameraView(
                onFinish: { images in
                    showCamera = false
                    Task {
                        await scan.addScanned(images)
                        Haptics.success()
                    }
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

    // MARK: Capture

    /// Shown while the scan is empty: one big invitation to scan, two smaller ways in.
    private var captureHero: some View {
        VStack(spacing: 14) {
            Button {
                startCamera()
            } label: {
                HStack(spacing: 16) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 36, weight: .semibold))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Scan a document")
                            .font(.title3.bold())
                        Text("Edges are found automatically")
                            .font(.subheadline)
                            .opacity(0.85)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.headline)
                        .opacity(0.8)
                }
                .foregroundStyle(.white)
                .padding(22)
                .frame(maxWidth: .infinity)
                .background(Theme.brandGradient, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(Theme.amber.opacity(0.35))
                        .frame(width: 90, height: 90)
                        .blur(radius: 24)
                        .offset(x: 20, y: -24)
                        .allowsHitTesting(false)
                }
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: Theme.blueDeep.opacity(0.35), radius: 14, x: 0, y: 8)
            }
            .buttonStyle(.pressable)

            HStack(spacing: 14) {
                PhotosPicker(selection: $photoItems, matching: .images) {
                    secondaryTile(icon: "photo.on.rectangle.angled", title: "Photos", subtitle: "From your library")
                }
                .buttonStyle(.pressable)

                Button {
                    Haptics.tap()
                    showFileImporter = true
                } label: {
                    secondaryTile(icon: "doc.richtext", title: "PDF", subtitle: "Import its pages")
                }
                .buttonStyle(.pressable)
            }

            Text("Everything is processed on your device.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 6)
        }
        .padding(.top, 8)
    }

    private func secondaryTile(icon: String, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.blueDeep)
                .frame(width: 42, height: 42)
                .background(Theme.amber.opacity(0.9), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: 16)
    }

    /// The compact version, once there are pages.
    private var addBar: some View {
        HStack(spacing: 10) {
            Button {
                startCamera()
            } label: {
                Label("Scan", systemImage: "camera.viewfinder")
            }
            .buttonStyle(.secondary)

            PhotosPicker(selection: $photoItems, matching: .images) {
                Label("Photos", systemImage: "photo.on.rectangle")
            }
            .buttonStyle(.secondary)

            Button {
                Haptics.tap()
                showFileImporter = true
            } label: {
                Label("PDF", systemImage: "doc.richtext")
            }
            .buttonStyle(.secondary)
        }
    }

    private var guestBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "person.crop.circle.badge.questionmark")
            Text("Guest mode — log in to save scans to an account.")
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(Color.black.opacity(0.8))
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(Theme.amber.opacity(0.9), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: Pages

    private var filterBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "wand.and.stars")
                .foregroundStyle(Color.accentColor)
            Picker("Filter", selection: $allFilter) {
                ForEach(PageFilter.allCases) { filter in
                    Text(filter.label).tag(filter)
                }
            }
            .pickerStyle(.menu)

            Spacer(minLength: 0)

            Button("Apply to all") {
                Haptics.tap()
                Task { await scan.applyFilterToAll(allFilter) }
            }
            .buttonStyle(SecondaryButtonStyle(cornerRadius: 12, fillsWidth: false))
        }
        .cardStyle(padding: 10)
    }

    private var pageGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 12)], spacing: 12) {
            ForEach(Array(scan.pages.enumerated()), id: \.element.id) { index, page in
                PageThumb(
                    page: page,
                    index: index,
                    count: scan.pages.count,
                    onEdit: { editTarget = EditTarget(id: page.id) },
                    onMoveEarlier: {
                        Haptics.select()
                        scan.move(page.id, by: -1)
                    },
                    onMoveLater: {
                        Haptics.select()
                        scan.move(page.id, by: 1)
                    },
                    onDelete: {
                        Haptics.warning()
                        scan.remove(page.id)
                    }
                )
                .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: scan.pages.map { $0.id })
    }

    // MARK: Export

    private var exportBar: some View {
        Button {
            Haptics.tap()
            Task { await startExport() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.doc.fill")
                Text("Export PDF")
                Text("· \(scan.pages.count) page\(scan.pages.count == 1 ? "" : "s")")
                    .opacity(0.8)
            }
        }
        .buttonStyle(PrimaryButtonStyle(cornerRadius: 30))
        .disabled(scan.isBusy)
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(.bar)
    }

    @ViewBuilder
    private var busyOverlay: some View {
        if scan.isBusy {
            ZStack {
                Color.black.opacity(0.25).ignoresSafeArea()
                ProgressView("Processing…")
                    .padding(22)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
        Haptics.tap()
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
        Haptics.success()
        exportItem = ExportItem(data: data)
    }
}

/// One page in the grid: the page itself on a little sheet of paper, its number, and the
/// same ⬅ ✏️ 🗑 ➡ controls as the web app.
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
            Color.white
                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                .overlay(
                    Image(uiImage: page.thumbnail)
                        .resizable()
                        .scaledToFit()
                        .padding(6)
                )
                .overlay(alignment: .topLeading) {
                    Text("\(index + 1)")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(Theme.brandGradient, in: Circle())
                        .padding(8)
                }
                .contentShape(Rectangle())
                .onTapGesture(perform: onEdit)

            HStack {
                Button(action: onMoveEarlier) { Image(systemName: "chevron.left") }
                    .disabled(index == 0)
                Spacer()
                Button(action: onEdit) { Image(systemName: "slider.horizontal.3") }
                Spacer()
                Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
                Spacer()
                Button(action: onMoveLater) { Image(systemName: "chevron.right") }
                    .disabled(index == count - 1)
            }
            .font(.system(size: 15, weight: .semibold))
            .buttonStyle(.borderless)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color(.secondarySystemGroupedBackground))
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(0.10), radius: 8, x: 0, y: 4)
    }
}
