import SwiftUI

/// What the web app's export panel does: name the PDF, then share/save-to-Files it or
/// (for signed-in users) save it to "My Scans".
struct ExportSheet: View {
    let pdfData: Data
    let pageCount: Int
    let allowsSaving: Bool
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ExportSheet.defaultTitle()
    @State private var shareItem: IdentifiableURL?
    @State private var isSaving = false
    @State private var errorMessage: String?

    // The server accepts 25 MB of JSON and base64 inflates the PDF by a third.
    private static let maxSaveBytes = 17_000_000

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Title", text: $title)
                }

                Section {
                    Button {
                        share()
                    } label: {
                        Label("Share / Save to Files", systemImage: "square.and.arrow.up")
                    }

                    if allowsSaving {
                        Button {
                            Task { await save() }
                        } label: {
                            Label("Save to My Scans", systemImage: "icloud.and.arrow.up")
                        }
                        .disabled(isSaving)
                    }
                } footer: {
                    if allowsSaving {
                        Text("\(ByteCountFormatter.string(fromByteCount: Int64(pdfData.count), countStyle: .file)) · \(pageCount) page\(pageCount == 1 ? "" : "s")")
                    } else {
                        Text("Guest mode — log in to save scans to an account.")
                    }
                }

                if isSaving {
                    HStack {
                        ProgressView()
                        Text("Saving…")
                    }
                    WakeHint()
                }

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
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

    private func save() async {
        errorMessage = nil
        guard pdfData.count <= Self.maxSaveBytes else {
            errorMessage = "This scan is too large to save. Try fewer pages, or share it instead."
            return
        }

        isSaving = true
        defer { isSaving = false }
        do {
            struct SaveBody: Encodable {
                let title: String
                let pageCount: Int
                let pdfBase64: String
            }
            let _: SavedScan = try await APIClient.shared.send(
                "/api/scans", method: .post,
                body: SaveBody(title: cleanTitle, pageCount: pageCount, pdfBase64: pdfData.base64EncodedString())
            )
            onSaved()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
