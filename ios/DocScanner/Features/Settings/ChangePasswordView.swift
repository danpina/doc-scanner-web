import SwiftUI

/// Change your password — also the way to replace the temporary one an admin gave you.
struct ChangePasswordView: View {
    @EnvironmentObject var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var current = ""
    @State private var new = ""
    @State private var confirm = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var canSave: Bool {
        !current.isEmpty && new.count >= 8 && new == confirm && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Current (or temporary) password", text: $current)
                        .textContentType(.password)
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
                            Text("Change password")
                        }
                    }
                    .buttonStyle(.primary)
                    .disabled(!canSave)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Change password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .keyboardDismissible()
        }
    }

    private func save() async {
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }

        if let error = await session.changePassword(current: current, new: new) {
            Haptics.warning()
            errorMessage = error
        } else {
            Haptics.success()
            dismiss()
        }
    }
}
