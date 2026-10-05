import SwiftUI

/// Home screen for signed-in users: the saved scans (the web dashboard), plus a big
/// "New Scan" button.
struct ScansListView: View {
    @EnvironmentObject var session: SessionStore
    @StateObject private var model = ScansViewModel()

    @State private var showNewScan = false
    @State private var showSettings = false
    @State private var viewing: IdentifiableURL?
    @State private var sharing: IdentifiableURL?
    @State private var pendingDelete: SavedScan?
    @State private var query = ""

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
                            AvatarView(email: session.user?.email ?? "?")
                        }
                        .accessibilityLabel("Settings")
                    }
                }
                .safeAreaInset(edge: .bottom) { newScanButton }
        }
        .task { await model.load() }
        .fullScreenCover(isPresented: $showNewScan) {
            ScanFlowView(
                allowsSaving: true,
                closeTitle: "Cancel",
                onClose: { showNewScan = false },
                onSaved: {
                    showNewScan = false
                    Task { await model.load() }
                }
            )
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
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
                Task { await model.delete(scan) }
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
        if model.isLoading && model.scans.isEmpty {
            VStack(spacing: 12) {
                ProgressView()
                WakeHint().padding(.horizontal)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.scans.isEmpty {
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
            Text("Scan a document, or add photos or a PDF, and save it here to find it on any device.")
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
        .searchable(text: $query, prompt: "Search scans")
        .refreshable { await model.load() }
    }

    private func row(_ scan: SavedScan) -> some View {
        Button {
            Haptics.tap()
            Task { await open(scan) }
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
                Task { await share(scan) }
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
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
                Task { await share(scan) }
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .tint(.blue)
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
        return model.scans.filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
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

    private func open(_ scan: SavedScan) async {
        if let url = await model.downloadPDF(scan) {
            viewing = IdentifiableURL(url: url)
        }
    }

    private func share(_ scan: SavedScan) async {
        if let url = await model.downloadPDF(scan) {
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
