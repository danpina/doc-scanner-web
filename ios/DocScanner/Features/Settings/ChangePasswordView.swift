import SwiftUI

/// Change your password — also the way to replace the temporary one an admin gave you, and
/// (for an account created with Apple) to set a first password so you can log in by email too.
struct ChangePasswordView: View {
    @EnvironmentObject var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var current = ""
    @State private var new = ""
    @State private var confirm = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showSuccess = false

    /// An account that has no password yet doesn't need to prove a current one.
    private var requiresCurrent: Bool {
        session.user?.hasPassword ?? true
    }

    private var title: String {
        requiresCurrent ? "Change password" : "Set a password"
    }

    private var canSave: Bool {
        (!requiresCurrent || !current.isEmpty) && new.count >= 8 && new == confirm && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                if requiresCurrent {
                    Section {
                        SecureField("Current (or temporary) password", text: $current)
                            .textContentType(.password)
                    }
                } else {
                    Section {
                        Text("You signed up with Apple, so this account has no password yet. Set one to also be able to log in with your email.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    SecureField("New password", text: $new)
                        .textContentType(.newPassword)
                    SecureField("Repeat new password", text: $confirm)
                        .textContentType(.newPassword)
                } footer: {
                    if !new.isEmpty && new.count < 8 {
                        Text("At least 8 characters.")
                            .foregroundStyle(.red)
                    } else if !confirm.isEmpty && new != confirm {
                        Text("The two passwords don't match.")
                            .foregroundStyle(.red)
                    } else {
                        Text("At least 8 characters.")
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text(title)
                        }
                    }
                    .buttonStyle(.primary)
                    .disabled(!canSave)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .keyboardDismissible()
            .alert("Password updated", isPresented: $showSuccess) {
                Button("OK") { dismiss() }
            } message: {
                Text("Use your new password the next time you log in. Your other devices have been logged out.")
            }
        }
    }

    private func save() async {
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }

        if let error = await session.changePassword(current: requiresCurrent ? current : nil, new: new) {
            Haptics.warning()
            errorMessage = error
        } else {
            Haptics.success()
            showSuccess = true
        }
    }
}
