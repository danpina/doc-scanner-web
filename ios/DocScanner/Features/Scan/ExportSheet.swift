import PDFKit
import SwiftUI

/// What the web app's export panel does: name the PDF, pick its size and page format, then
/// share/save-to-Files it (as a PDF, or as pictures) or keep it in "My Scans" on this iPhone.
struct ExportSheet: View {
    private enum ShareFormat: String, CaseIterable, Identifiable {
        case pdf = "PDF"
        case jpg = "JPG"
        case png = "PNG"

        var id: String { rawValue }
        var fileExtension: String { rawValue.lowercased() }
    }

    private struct ShareItems: Identifiable {
        let id = UUID()
        let urls: [URL]
    }

    private enum ShareError: LocalizedError {
        case lockFailed
        case encodeFailed

        var errorDescription: String? {
            switch self {
            case .lockFailed: return "Couldn't lock the PDF with a password."
            case .encodeFailed: return "Couldn't create the pictures."
            }
        }
    }

    let source: ScanSession.BuiltPDF
    let pageCount: Int
    /// The saved scan being edited, if this export comes from reopening one.
    let replacing: SavedScan?
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage(ExportOptions.qualityKey) private var qualityRaw = OutputQuality.best.rawValue
    @AppStorage(ExportOptions.layoutKey) private var layoutRaw = PageLayout.original.rawValue
    @State private var pdfData: Data
    @State private var isRebuilding = false
    @State private var rebuildTask: Task<Void, Never>?
    @State private var title: String
    @State private var usePassword = false
    @State private var password = ""
    @State private var shareItem: ShareItems?
    @State private var errorMessage: String?
    @State private var format: ShareFormat = .pdf
    @State private var isPreparingShare = false
    @AppStorage("watermarkText") private var watermarkText = ""
    @State private var useWatermark = false

    init(source: ScanSession.BuiltPDF, pageCount: Int, replacing: SavedScan? = nil, onSaved: @escaping () -> Void) {
        self.source = source
        self.pageCount = pageCount
        self.replacing = replacing
        self.onSaved = onSaved
        _pdfData = State(initialValue: source.data)
        _title = State(initialValue: replacing?.title ?? source.suggestedTitle ?? ExportSheet.defaultTitle())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    summaryCard
                    titleCard
                    optionsCard
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
                ShareSheet(items: item.urls)
            }
            .onChange(of: qualityRaw) { _ in rebuild() }
            .onChange(of: layoutRaw) { _ in rebuild() }
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
                Text("\(pageCount) page\(pageCount == 1 ? "" : "s") · \(ByteCountFormatter.string(fromByteCount: Int64(pdfData.count), countStyle: .file))\(source.searchText == nil ? "" : " · searchable")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if isRebuilding {
                ProgressView()
            }
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
            if source.suggestedTitle != nil, replacing == nil {
                Text("Suggested from the text on the first page. Change it if you like.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var optionsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Options")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text("Share as")
                    .font(.subheadline.weight(.medium))
                Picker("Share as", selection: $format) {
                    ForEach(ShareFormat.allCases) { format in
                        Text(format.rawValue).tag(format)
                    }
                }
                .pickerStyle(.segmented)
                if format != .pdf {
                    Text("One picture per page. \"Save to My Scans\" always keeps a PDF.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("File size")
                    .font(.subheadline.weight(.medium))
                Picker("File size", selection: $qualityRaw) {
                    ForEach(OutputQuality.allCases) { quality in
                        Text(quality.label).tag(quality.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                Text(options.quality.hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if format == .pdf {
            VStack(alignment: .leading, spacing: 6) {
                Text("Page format")
                    .font(.subheadline.weight(.medium))
                Picker("Page format", selection: $layoutRaw) {
                    ForEach(PageLayout.allCases) { layout in
                        Text(layout.label).tag(layout.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                Text(options.layout.hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Toggle("Password for the shared file", isOn: $usePassword)
                    .font(.subheadline.weight(.medium))
                if usePassword {
                    SecureField("Password", text: $password)
                        .textContentType(.newPassword)
                        .textFieldStyle(.roundedBorder)
                }
                Text(usePassword
                     ? "Whoever opens the shared file needs this password. It can't be recovered, so keep it safe. The copy in My Scans stays unlocked on your iPhone."
                     : "Lock the PDF you share with a password.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Toggle("Watermark on the shared file", isOn: $useWatermark)
                    .font(.subheadline.weight(.medium))
                if useWatermark {
                    TextField("e.g. Copy for rental application only", text: $watermarkText)
                        .textFieldStyle(.roundedBorder)
                }
                Text(useWatermark
                     ? "This text is repeated across every page of the file you share, so a copy of your ID can't easily be reused for something else. The copy in My Scans stays clean."
                     : "Stamp a line of text across every page, for example what a copy is for.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            }
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
                Label(format == .pdf ? "Share / Save to Files" : "Share pictures (\(format.rawValue))", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.primary)
            .disabled(isRebuilding || isPreparingShare || (format == .pdf && usePassword && password.isEmpty))

            Button {
                save(asNew: replacing == nil)
            } label: {
                Label(replacing == nil ? "Save to My Scans" : "Save changes", systemImage: "tray.and.arrow.down")
            }
            .buttonStyle(.secondary)
            .disabled(isRebuilding)

            if replacing != nil {
                Button {
                    save(asNew: true)
                } label: {
                    Label("Save as a new scan", systemImage: "plus.square.on.square")
                }
                .buttonStyle(.secondary)
                .disabled(isRebuilding)
            }

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

    // MARK: Options

    private var options: ExportOptions {
        ExportOptions(
            quality: OutputQuality(rawValue: qualityRaw) ?? .best,
            layout: PageLayout(rawValue: layoutRaw) ?? .original
        )
    }

    /// Builds the PDF again with the chosen options. The pages and their text are reused.
    private func rebuild() {
        rebuildTask?.cancel()
        isRebuilding = true

        let images = source.images
        let texts = source.texts
        let pdfTitle = source.suggestedTitle ?? "Scan"
        let chosen = options
        rebuildTask = Task {
            let data = await Task.detached(priority: .userInitiated) {
                PDFBuilder.makePDF(from: images, text: texts, title: pdfTitle, options: chosen)
            }.value
            guard !Task.isCancelled else { return }
            if let data { pdfData = data }
            isRebuilding = false
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
        isPreparingShare = true
        Task {
            defer { isPreparingShare = false }
            do {
                shareItem = ShareItems(urls: try await makeShareFiles())
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// The file(s) to hand to the share sheet: one PDF (watermarked and locked if chosen), or one
    /// picture per page.
    private func makeShareFiles() async throws -> [URL] {
        let folder = FileManager.default.temporaryDirectory
        let name = FileNames.safe(cleanTitle)

        switch format {
        case .pdf:
            var data = pdfData
            let mark = watermarkText.trimmingCharacters(in: .whitespacesAndNewlines)
            if useWatermark, !mark.isEmpty {
                var chosen = options
                chosen.watermark = mark
                let images = source.images
                let texts = source.texts
                let pdfTitle = source.suggestedTitle ?? "Scan"
                if let stamped = await Task.detached(priority: .userInitiated, operation: {
                    PDFBuilder.makePDF(from: images, text: texts, title: pdfTitle, options: chosen)
                }).value {
                    data = stamped
                }
            }

            let url = folder.appendingPathComponent("\(name).pdf")
            if usePassword {
                guard let document = PDFDocument(data: data),
                      document.write(to: url, withOptions: [
                        PDFDocumentWriteOption.userPasswordOption: password,
                        PDFDocumentWriteOption.ownerPasswordOption: password
                      ]) else {
                    throw ShareError.lockFailed
                }
            } else {
                try data.write(to: url, options: .atomic)
            }
            return [url]

        case .jpg, .png:
            let images = source.images
            let quality = options.quality
            let chosen = format
            return try await Task.detached(priority: .userInitiated) {
                var urls: [URL] = []
                for (index, image) in images.enumerated() {
                    let sized = ImageProcessing.scaled(image, maxDimension: quality.maxPixels)
                    let encoded = chosen == .jpg ? sized.jpegData(compressionQuality: quality.jpegQuality) : sized.pngData()
                    guard let encoded else { throw ShareError.encodeFailed }
                    let suffix = images.count == 1 ? "" : "-\(index + 1)"
                    let url = folder.appendingPathComponent("\(name)\(suffix).\(chosen.fileExtension)")
                    try encoded.write(to: url, options: .atomic)
                    urls.append(url)
                }
                return urls
            }.value
        }
    }

    private func save(asNew: Bool) {
        errorMessage = nil
        do {
            if let replacing, !asNew {
                try LocalScanStore.shared.replace(replacing, pdf: pdfData, title: cleanTitle, pageCount: pageCount, searchText: source.searchText)
            } else {
                try LocalScanStore.shared.save(pdf: pdfData, title: cleanTitle, pageCount: pageCount, searchText: source.searchText)
            }
            Haptics.success()
            onSaved()
        } catch {
            Haptics.warning()
            errorMessage = "Couldn't save the scan: \(error.localizedDescription)"
        }
    }
}
