import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

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
                    Link(destination: AppLinks.privacy) {
                        Label("Privacy Policy", systemImage: "hand.raised")
                    }
                    Link(destination: AppLinks.support) {
                        Label("Support", systemImage: "questionmark.circle")
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
