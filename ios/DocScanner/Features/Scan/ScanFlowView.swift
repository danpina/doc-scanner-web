import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import VisionKit

/// The scan workflow — capture, reorder/edit pages, export. Shown as the "New Scan" screen.
struct ScanFlowView: View {
    @ObservedObject var inbox: ImportInbox
    let onClose: () -> Void
    let onSaved: () -> Void
    /// Set when a saved scan was reopened: saving then replaces it instead of adding a new one.
    var editing: SavedScan?
    var initialImages: [UIImage] = []

    @StateObject private var scan = ScanSession()
    @State private var loadedInitialImages = false
    @State private var showCamera = false
    @State private var showCameraUnavailable = false
    @State private var showIDCardHint = false
    @State private var showIDBackPrompt = false
    @State private var showIDLayoutChoice = false
    /// Which side of an ID card the camera is capturing right now; nil for an ordinary scan.
    @State private var idSide: IDSide?
    @State private var idFront: UIImage?
    @State private var idBack: UIImage?
    @State private var showFileImporter = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var editTarget: EditTarget?
    @State private var markupTarget: EditTarget?
    @State private var exportItem: ExportItem?
    @State private var allFilter: PageFilter = .original
    @State private var confirmLeave = false
    @State private var dropTargetID: UUID?

    private enum IDSide {
        case front
        case back
    }

    private struct EditTarget: Identifiable {
        let id: UUID
    }

    private struct ExportItem: Identifiable {
        let id = UUID()
        let pdf: ScanSession.BuiltPDF
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
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
            .navigationTitle(editing == nil ? "New Scan" : "Edit Scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { leave() }
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
                    if let side = idSide {
                        idSide = nil
                        handleIDCapture(images, side: side)
                        return
                    }
                    Task {
                        await scan.addScanned(images)
                        Haptics.success()
                    }
                },
                onCancel: {
                    showCamera = false
                    idSide = nil
                    idFront = nil
                    idBack = nil
                }
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
        .fullScreenCover(item: $markupTarget) { target in
            if let page = scan.page(withID: target.id) {
                MarkupEditorView(
                    page: page,
                    onCancel: { markupTarget = nil },
                    onDone: { updated in
                        scan.replace(updated)
                        markupTarget = nil
                    }
                )
            }
        }
        .sheet(item: $exportItem) { item in
            ExportSheet(
                source: item.pdf,
                pageCount: scan.pages.count,
                replacing: editing,
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
        .onAppear {
            takeFilesFromInbox()
            loadInitialImagesOnce()
        }
        .onChange(of: inbox.pendingURLs) { _ in takeFilesFromInbox() }
        .alert("Scan an ID card", isPresented: $showIDCardHint) {
            Button("Scan the front") {
                idSide = .front
                startCamera()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Start with the front of the card. You'll be asked for the back next.")
        }
        .alert("Now the back", isPresented: $showIDBackPrompt) {
            Button("Scan the back") {
                idSide = .back
                startCamera()
            }
            Button("Front only") {
                idBack = nil
                finishIDCard(onOnePage: true)
            }
            Button("Cancel", role: .cancel) {
                idFront = nil
            }
        } message: {
            Text("Turn the card over and scan the back.")
        }
        .confirmationDialog("How should the card go in your PDF?", isPresented: $showIDLayoutChoice, titleVisibility: .visible) {
            Button("Both sides on one page") {
                finishIDCard(onOnePage: true)
            }
            Button("Front and back on separate pages") {
                finishIDCard(onOnePage: false)
            }
            Button("Cancel", role: .cancel) {
                idFront = nil
                idBack = nil
            }
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

            Button {
                Haptics.tap()
                showIDCardHint = true
            } label: {
                secondaryTile(icon: "person.text.rectangle", title: "ID card", subtitle: "Front and back on one page")
            }
            .buttonStyle(.pressable)

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
        VStack(spacing: 12) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 12)], spacing: 12) {
                ForEach(Array(scan.pages.enumerated()), id: \.element.id) { index, page in
                    PageThumb(
                        page: page,
                        index: index,
                        count: scan.pages.count,
                        onEdit: { editTarget = EditTarget(id: page.id) },
                        onMarkup: { markupTarget = EditTarget(id: page.id) },
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
                    // Touch and hold lifts the page (a tap or a scroll never does); it only moves
                    // when it is dropped on another page.
                    .draggable(DraggedPage(id: page.id))
                    .dropDestination(for: DraggedPage.self) { items, _ in
                        dropTargetID = nil
                        guard let dragged = items.first,
                              dragged.id != page.id,
                              scan.page(withID: dragged.id) != nil else { return false }
                        Haptics.success()
                        scan.move(dragged.id, onto: page.id)
                        return true
                    } isTargeted: { isOver in
                        if isOver {
                            dropTargetID = page.id
                        } else if dropTargetID == page.id {
                            dropTargetID = nil
                        }
                    }
                    .overlay {
                        if dropTargetID == page.id {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Theme.brandGradient, lineWidth: 3)
                        }
                    }
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: scan.pages.map { $0.id })

            Label("Tap Sign on a page to add your signature, text or today's date.", systemImage: "signature")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if scan.pages.count > 1 {
                Text("To change the order, touch and hold a page, then drag it onto another one.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
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
                ProgressView(scan.busyMessage)
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
            idSide = nil
            showCameraUnavailable = true
            return
        }
        showCamera = true
    }

    /// After the front: ask for the back. After the back (or if both came in one go): ask how to lay them out.
    private func handleIDCapture(_ images: [UIImage], side: IDSide) {
        switch side {
        case .front:
            guard let front = images.first else { return }
            idFront = front
            idBack = images.count > 1 ? images[1] : nil
            presentAfterCamera {
                if idBack == nil {
                    showIDBackPrompt = true
                } else {
                    showIDLayoutChoice = true
                }
            }
        case .back:
            idBack = images.first
            presentAfterCamera { showIDLayoutChoice = true }
        }
    }

    /// Lets the camera finish closing before the next dialog opens (iOS drops a dialog shown too early).
    private func presentAfterCamera(_ show: @escaping () -> Void) {
        Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            show()
        }
    }

    private func finishIDCard(onOnePage: Bool) {
        guard let front = idFront else { return }
        let back = idBack
        idFront = nil
        idBack = nil
        Task {
            if onOnePage {
                await scan.addIDCard([front] + (back.map { [$0] } ?? []))
            } else {
                await scan.addScanned([front] + (back.map { [$0] } ?? []))
            }
            Haptics.success()
        }
    }

    private func loadInitialImagesOnce() {
        guard !loadedInitialImages, !initialImages.isEmpty else { return }
        loadedInitialImages = true
        let images = initialImages
        Task { await scan.addScanned(images) }
    }

    private func takeFilesFromInbox() {
        let urls = inbox.take()
        guard !urls.isEmpty else { return }
        Task { await scan.addFiles(urls) }
    }

    private func leave() {
        if scan.pages.isEmpty {
            onClose()
        } else {
            confirmLeave = true
        }
    }

    private func startExport() async {
        guard let pdf = await scan.buildPDF() else { return }
        Haptics.success()
        exportItem = ExportItem(pdf: pdf)
    }
}

/// What a page carries while it is being dragged to a new position. Only this app can read it,
/// so dropping a page onto another app doesn't paste anything.
private struct DraggedPage: Codable, Transferable {
    let id: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
            .visibility(.ownProcess)
    }
}

/// One page in the grid: the page itself on a little sheet of paper, its number, and the
/// same ⬅ ✏️ 🗑 ➡ controls as the web app.
private struct PageThumb: View {
    let page: ScanPage
    let index: Int
    let count: Int
    let onEdit: () -> Void
    let onMarkup: () -> Void
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
                .overlay(alignment: .topTrailing) {
                    Button(action: onMarkup) {
                        Label("Sign", systemImage: "signature")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(page.marks.isEmpty ? Theme.blueDeep : Color.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                page.marks.isEmpty ? AnyShapeStyle(Theme.amber) : AnyShapeStyle(Theme.brandGradient),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Sign and fill in")
                    .padding(6)
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
