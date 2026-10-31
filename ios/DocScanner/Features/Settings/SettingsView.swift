import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(TextRecognizer.settingKey) private var recognizeText = true

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label {
                        Text("Your scans are stored only on this iPhone. Doc Scanner has no account and sends nothing to a server. If iCloud Backup is on, they are included in your iPhone's backup.")
                            .font(.subheadline)
                    } icon: {
                        Image(systemName: "lock.iphone")
                            .foregroundStyle(Theme.brandGradient)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Your scans")
                } footer: {
                    Text("Deleting the app deletes the scans saved in it. Share a scan to Files first if you want to keep a copy.")
                }

                Section {
                    Toggle(isOn: $recognizeText) {
                        Label("Make scans searchable", systemImage: "text.magnifyingglass")
                    }
                } header: {
                    Text("Text recognition")
                } footer: {
                    Text("Reads the words on each page when you export, so you can search your scans and select text in the PDF. It happens on your iPhone; nothing is sent anywhere. Exporting takes a little longer.")
                }

                Section {
                    Link(destination: AppLinks.privacy) {
                        Label("Privacy Policy", systemImage: "hand.raised")
                    }
                    Link(destination: AppLinks.terms) {
                        Label("Terms of Use", systemImage: "doc.text")
                    }
                    Link(destination: AppLinks.support) {
                        Label("Support", systemImage: "questionmark.circle")
                    }
                    Link(destination: AppLinks.contact) {
                        Label("Contact us", systemImage: "bubble.left.and.bubble.right")
                    }
                    Link(destination: AppLinks.licenses) {
                        Label("Open-source notices", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    HStack {
                        Label("Version", systemImage: "info.circle")
                        Spacer()
                        Text(versionText).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
