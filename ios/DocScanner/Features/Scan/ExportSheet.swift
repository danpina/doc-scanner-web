import SwiftUI

/// What the web app's export panel does: name the PDF, then share/save-to-Files it or
/// keep it in "My Scans" on this iPhone.
struct ExportSheet: View {
    let pdfData: Data
    let pageCount: Int
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ExportSheet.defaultTitle()
    @State private var shareItem: IdentifiableURL?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    summaryCard
                    titleCard
                    actions
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(item: $shareItem) { item in
                ShareSheet(items: [item.url])
            }
            .keyboardDismissible()
        }
    }

    // MARK: Pieces

    private var summaryCard: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.brandGradient)
                .frame(width: 46, height: 58)
                .overlay(
                    Image(systemName: "checkmark")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Theme.amber)
                )
            VStack(alignment: .leading, spacing: 3) {
                Text("Your PDF is ready")
                    .font(.headline)
                Text("\(pageCount) page\(pageCount == 1 ? "" : "s") · \(ByteCountFormatter.string(fromByteCount: Int64(pdfData.count), countStyle: .file))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var titleCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Title")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField("Title", text: $title)
                .font(.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button {
                Haptics.tap()
                share()
            } label: {
                Label("Share / Save to Files", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.primary)

            Button {
                save()
            } label: {
                Label("Save to My Scans", systemImage: "tray.and.arrow.down")
            }
            .buttonStyle(.secondary)

            Text("Saved scans stay on this iPhone.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: Actions

    private var cleanTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? ExportSheet.defaultTitle() : trimmed
    }

    private static func defaultTitle() -> String {
        "Scan \(Date().formatted(date: .abbreviated, time: .omitted))"
    }

    private func share() {
        errorMessage = nil
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(FileNames.safe(cleanTitle)).pdf")
        do {
            try pdfData.write(to: url, options: .atomic)
            shareItem = IdentifiableURL(url: url)
        } catch {
            errorMessage = "Couldn't prepare the file: \(error.localizedDescription)"
        }
    }

    private func save() {
        errorMessage = nil
        do {
            try LocalScanStore.shared.save(pdf: pdfData, title: cleanTitle, pageCount: pageCount)
            Haptics.success()
            onSaved()
        } catch {
            Haptics.warning()
            errorMessage = "Couldn't save the scan: \(error.localizedDescription)"
        }
    }
}
