import SwiftUI

/// Asks the server to email a reset link. The link opens a web page where the new password is
/// chosen, so the app only has to collect the email address.
struct ForgotPasswordView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var email: String
    @State private var isSending = false
    @State private var sent = false
    @State private var errorMessage: String?

    init(email: String = "") {
        _email = State(initialValue: email)
    }

    private var canSend: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    var body: some View {
        NavigationStack {
            Form {
                if sent {
                    Section {
                        VStack(spacing: 10) {
                            Image(systemName: "envelope.badge")
                                .font(.system(size: 40))
                                .foregroundStyle(Theme.brandGradient)
                            Text("Check your email")
                                .font(.headline)
                            Text("If an account exists for that address, we've sent a link to choose a new password. It works once and expires in an hour.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }

                    Section {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "tray.full.fill")
                                .font(.title3)
                                .foregroundStyle(Theme.blueDeep)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Can't find it? Check your spam or junk folder.")
                                    .font(.subheadline.weight(.semibold))
                                Text("Reset emails often end up there. If you find it, mark it \"Not spam\" so the link works.")
                                    .font(.footnote)
                            }
                            .foregroundStyle(Color.black.opacity(0.85))
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(Theme.amber.opacity(0.85))

                    Section {
                        Button("Done") { dismiss() }
                            .buttonStyle(.primary)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                } else {
                    Section {
                        TextField("Email", text: $email)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.emailAddress)
                            .textContentType(.username)
                    } footer: {
                        Text("We'll email you a link to choose a new password. If you signed up with Apple you don't have a password; just use Sign in with Apple.")
                    }

                    if let errorMessage {
                        Section {
                            Text(errorMessage)
                                .foregroundStyle(.red)
                        }
                    }

                    Section {
                        Button {
                            Task { await send() }
                        } label: {
                            if isSending {
                                ProgressView().tint(.white)
                            } else {
                                Text("Send reset link")
                            }
                        }
                        .buttonStyle(.primary)
                        .disabled(!canSend)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)

                        if isSending {
                            WakeHint()
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .navigationTitle("Forgot password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .keyboardDismissible()
        }
    }

    private func send() async {
        errorMessage = nil
        isSending = true
        defer { isSending = false }

        struct ForgotBody: Encodable {
            let email: String
        }
        do {
            try await APIClient.shared.sendNoContent(
                "/api/forgot-password", method: .post,
                body: ForgotBody(email: email.trimmingCharacters(in: .whitespacesAndNewlines))
            )
            Haptics.success()
            sent = true
        } catch {
            Haptics.warning()
            errorMessage = error.localizedDescription
        }
    }
}
