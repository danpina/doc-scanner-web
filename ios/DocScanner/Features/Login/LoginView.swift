import SwiftUI

struct LoginView: View {
    @EnvironmentObject var session: SessionStore
    @State private var serverURLText = ServerConfig.baseURL?.absoluteString ?? ""
    @State private var email = ""
    @State private var password = ""
    @State private var isSubmitting = false

    private let brandColor = Color(red: 0.04, green: 0.42, blue: 1.0)

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 10) {
                        Image(systemName: "doc.viewfinder")
                            .font(.system(size: 40))
                            .foregroundStyle(.white)
                            .frame(width: 84, height: 84)
                            .background(brandColor.gradient, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        Text("Doc Scanner")
                            .font(.largeTitle.bold())
                        Text("Scan, crop, filter & export PDFs")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .listRowBackground(Color.clear)

                #if DEBUG
                Section("Server (debug builds only)") {
                    TextField("https://your-app.example.com", text: $serverURLText)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text("Defaults to the production server. For a local dev server in the Simulator, use http://localhost:3000.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                #endif

                Section("Log in") {
                    TextField("Email", text: $email)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                    SecureField("Password", text: $password)
                }

                if let error = session.errorMessage {
                    Text(error).foregroundStyle(.red)
                }

                Section {
                    Button {
                        Task { await submit() }
                    } label: {
                        Group {
                            if isSubmitting {
                                ProgressView().tint(.white)
                            } else {
                                Text("Log in")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(brandColor)
                    .disabled(isSubmitting || email.isEmpty || password.isEmpty)
                    .listRowInsets(EdgeInsets())

                    if isSubmitting {
                        WakeHint()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                }
                .listRowBackground(Color.clear)

                Section {
                    Button {
                        session.continueAsGuest()
                    } label: {
                        Text("Continue as Guest")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .listRowInsets(EdgeInsets())
                } footer: {
                    Text("Guest mode: scan, crop, filter and export a PDF — nothing is saved to an account.")
                }
                .listRowBackground(Color.clear)
            }
            .toolbar(.hidden, for: .navigationBar)
            .keyboardDismissible()
        }
    }

    private func submit() async {
        ServerConfig.baseURL = URL(string: serverURLText)
        isSubmitting = true
        defer { isSubmitting = false }
        _ = await session.login(
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password
        )
    }
}
