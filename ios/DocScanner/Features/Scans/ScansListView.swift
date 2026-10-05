import SwiftUI

/// Home screen for signed-in users: the saved scans (the web dashboard), plus a "+" for a new one.
struct ScansListView: View {
    @EnvironmentObject var session: SessionStore
    @StateObject private var model = ScansViewModel()

    @State private var showNewScan = false
    @State private var viewing: IdentifiableURL?
    @State private var sharing: IdentifiableURL?
    @State private var pendingDelete: SavedScan?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("My Scans")
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Menu {
                            Button(session.user?.email ?? "") {}
                                .disabled(true)
                            Button("Log out", role: .destructive) {
                                Task { await session.logout() }
                            }
                        } label: {
                            Image(systemName: "person.circle")
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            showNewScan = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
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

    @ViewBuilder
    private var content: some View {
        if model.isLoading && model.scans.isEmpty {
            VStack(spacing: 12) {
                ProgressView()
                WakeHint().padding(.horizontal)
            }
        } else if model.scans.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "doc.text.viewfinder")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
                Text("No scans yet")
                    .font(.headline)
                Text("Tap + to scan your first document.")
                    .foregroundStyle(.secondary)
            }
        } else {
            list
        }
    }

    private var list: some View {
        List {
            ForEach(model.scans) { scan in
                Button {
                    Task { await open(scan) }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(scan.title).font(.headline)
                        Text(scan.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(.primary)
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
        }
        .refreshable { await model.load() }
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
