import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var confirmDelete = false
    @State private var isDeleting = false
    @State private var deleteError: String?
    @State private var serverURLText = ServerConfig.baseURL?.absoluteString ?? ""

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
                    HStack(spacing: 14) {
                        AvatarView(email: session.user?.email ?? "?", size: 52)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.user?.email ?? "")
                                .font(.headline)
                                .lineLimit(1)
                            Text("Signed in")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Button {
                        Task {
                            await session.logout()
                        }
                    } label: {
                        Label("Log out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }

                Section {
                    Link(destination: ServerConfig.productionURL.appendingPathComponent("privacy.html")) {
                        Label("Privacy Policy", systemImage: "hand.raised")
                    }
                    Link(destination: ServerConfig.productionURL.appendingPathComponent("support.html")) {
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

                #if DEBUG
                Section("Server (debug builds only)") {
                    TextField("https://your-app.example.com", text: $serverURLText)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Update server URL") {
                        ServerConfig.baseURL = URL(string: serverURLText)
                    }
                }
                #endif

                Section {
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        HStack {
                            Label("Delete account", systemImage: "trash")
                            if isDeleting {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isDeleting)

                    if let deleteError {
                        Text(deleteError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                } footer: {
                    Text("Permanently deletes your account and every scan saved to it.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                "Delete your account?",
                isPresented: $confirmDelete,
                titleVisibility: .visible
            ) {
                Button("Delete account", role: .destructive) {
                    Task { await deleteAccount() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes your account and all of your saved scans. It can't be undone.")
            }
        }
    }

    private func deleteAccount() async {
        deleteError = nil
        isDeleting = true
        defer { isDeleting = false }
        if let error = await session.deleteAccount() {
            Haptics.warning()
            deleteError = error
        }
    }
}
