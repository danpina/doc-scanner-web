import SwiftUI

/// Home screen: the scans saved on this iPhone, plus a big "New Scan" button.
struct ScansListView: View {
    @ObservedObject var inbox: ImportInbox
    @StateObject private var model = ScansViewModel()

    @State private var showNewScan = false
    @State private var showSettings = false
    @State private var viewing: IdentifiableURL?
    @State private var sharing: IdentifiableURL?
    @State private var pendingDelete: SavedScan?
    @State private var renaming: SavedScan?
    @State private var renameText = ""
    @State private var editing: EditSession?
    @State private var isLoadingEdit = false
    @State private var query = ""

    /// A saved scan reopened in the editor, with its pages already read from the PDF.
    private struct EditSession: Identifiable {
        let id = UUID()
        let scan: SavedScan
        let images: [UIImage]
    }

    private struct MonthSection: Identifiable {
        let id: String
        let title: String
        let scans: [SavedScan]
    }

    var body: some View {
        NavigationStack {
            content
                .background(Color(.systemGroupedBackground).ignoresSafeArea())
                .navigationTitle("My Scans")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            Haptics.tap()
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(Theme.brandGradient)
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Settings")
                    }
                }
                .safeAreaInset(edge: .bottom) { newScanButton }
        }
        .onAppear {
            model.load()
            openScanScreenIfFilesArrived()
        }
        .onChange(of: inbox.pendingURLs) { _ in
            openScanScreenIfFilesArrived()
        }
        .fullScreenCover(isPresented: $showNewScan) {
            ScanFlowView(
                inbox: inbox,
                onClose: { showNewScan = false },
                onSaved: {
                    showNewScan = false
                    model.load()
                }
            )
        }
        .fullScreenCover(item: $editing) { session in
            ScanFlowView(
                inbox: inbox,
                onClose: { editing = nil },
                onSaved: {
                    editing = nil
                    model.load()
                },
                editing: session.scan,
                initialImages: session.images
            )
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .alert("Rename scan", isPresented: Binding(
            get: { renaming != nil },
            set: { shown in
                if !shown { renaming = nil }
            }
        )) {
            TextField("Title", text: $renameText)
            Button("Save") {
                if let scan = renaming {
                    model.rename(scan, to: renameText)
                }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .overlay {
            if isLoadingEdit {
                ZStack {
                    Color.black.opacity(0.25).ignoresSafeArea()
                    ProgressView("Opening…")
                        .padding(22)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
        .sheet(item: $viewing) { item in
            PDFPreviewSheet(url: item.url)
        }
        .sheet(item: $sharing) { item in
            ShareSheet(items: [item.url])
        }
        .confirmationDialog(
            "Delete this scan?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { shown in
                    if !shown { pendingDelete = nil }
                }
            ),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { scan in
            Button("Delete \"\(scan.title)\"", role: .destructive) {
                model.delete(scan)
            }
        }
        .alert("Something went wrong", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if model.scans.isEmpty {
            emptyState
        } else {
            list
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Theme.brandGradient)
                    .frame(width: 110, height: 110)
                    .shadow(color: Theme.blueDeep.opacity(0.35), radius: 16, x: 0, y: 8)
                Image(systemName: "doc.text.viewfinder")
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundStyle(.white)
            }
            Text("No scans yet")
                .font(.title2.bold())
            Text("Scan a document, or add photos or a PDF, and save it here. Your scans stay on this iPhone.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 80)
    }

    private var list: some View {
        List {
            ForEach(sections) { section in
                Section {
                    ForEach(section.scans) { scan in
                        row(scan)
                    }
                } header: {
                    Text(section.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                }
            }

            if sections.isEmpty {
                Text("No scans match \"\(query)\".")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            // Room so the last card isn't hidden behind the floating button.
            Color.clear
                .frame(height: 60)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .searchable(text: $query, prompt: "Search titles and text")
    }

    private func row(_ scan: SavedScan) -> some View {
        Button {
            Haptics.tap()
            open(scan)
        } label: {
            HStack(spacing: 14) {
                documentTile(pages: scan.pageCount)

                VStack(alignment: .leading, spacing: 4) {
                    Text(scan.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(scan.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let snippet = searchSnippet(for: scan) {
                        Text(snippet)
                            .font(.caption)
                            .foregroundStyle(Theme.blueDeep)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .cardStyle(padding: 12)
        }
        .buttonStyle(.plain)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        .contextMenu {
            Button {
                share(scan)
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            Button {
                startRename(scan)
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button {
                edit(scan)
            } label: {
                Label("Edit pages", systemImage: "slider.horizontal.3")
            }
            Button(role: .destructive) {
                pendingDelete = scan
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                pendingDelete = scan
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                share(scan)
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .tint(.blue)
            Button {
                startRename(scan)
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            .tint(.orange)
        }
    }

    /// A little gradient "page" with the page count tucked into the corner.
    private func documentTile(pages: Int) -> some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.brandGradient)
                .frame(width: 46, height: 58)
                .overlay(
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.9))
                )

            if pages > 1 {
                Text("\(pages)")
                    .font(.caption2.bold())
                    .foregroundStyle(.black)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.amber, in: Capsule())
                    .offset(x: 6, y: 6)
            }
        }
        .padding(.trailing, 4)
    }

    private var newScanButton: some View {
        Button {
            Haptics.tap()
            showNewScan = true
        } label: {
            Label("New Scan", systemImage: "camera.viewfinder")
        }
        .buttonStyle(PrimaryButtonStyle(cornerRadius: 30))
        .padding(.horizontal, 48)
        .padding(.bottom, 8)
    }

    // MARK: Data

    private var filteredScans: [SavedScan] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return model.scans }
        return model.scans.filter { $0.matches(trimmed) }
    }

    /// Where the search words appear inside the scan, shown when the title alone doesn't explain
    /// why the scan is in the results.
    private func searchSnippet(for scan: SavedScan) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              scan.title.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == nil else {
            return nil
        }
        return scan.snippet(for: trimmed)
    }

    /// Scans grouped by month, newest first (the server already returns them newest first).
    private var sections: [MonthSection] {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL yyyy"

        var result: [MonthSection] = []
        for scan in filteredScans {
            let title = scan.createdDate.map { formatter.string(from: $0) } ?? "Earlier"
            if let last = result.last, last.title == title {
                result[result.count - 1] = MonthSection(id: last.id, title: last.title, scans: last.scans + [scan])
            } else {
                result.append(MonthSection(id: "\(result.count)-\(title)", title: title, scans: [scan]))
            }
        }
        return result
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { shown in
                if !shown { model.errorMessage = nil }
            }
        )
    }

    /// A PDF or image sent from another app opens straight into a new scan.
    private func openScanScreenIfFilesArrived() {
        if !inbox.pendingURLs.isEmpty {
            showSettings = false
            showNewScan = true
        }
    }

    private func open(_ scan: SavedScan) {
        if let url = model.exportCopy(scan) {
            viewing = IdentifiableURL(url: url)
        }
    }

    private func startRename(_ scan: SavedScan) {
        renameText = scan.title
        renaming = scan
    }

    private func edit(_ scan: SavedScan) {
        isLoadingEdit = true
        Task {
            let images = await model.pageImages(for: scan)
            isLoadingEdit = false
            if images.isEmpty {
                model.errorMessage = "Couldn't read the pages of this scan."
            } else {
                editing = EditSession(scan: scan, images: images)
            }
        }
    }

    private func share(_ scan: SavedScan) {
        if let url = model.exportCopy(scan) {
            sharing = IdentifiableURL(url: url)
        }
    }
}

private struct PDFPreviewSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PDFKitView(url: url)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(url.deletingPathExtension().lastPathComponent)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: url)
                    }
                }
        }
    }
}
