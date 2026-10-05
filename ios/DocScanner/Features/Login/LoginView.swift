import AuthenticationServices
import SwiftUI

struct LoginView: View {
    @EnvironmentObject var session: SessionStore
    @State private var serverURLText = ServerConfig.baseURL?.absoluteString ?? ""
    @State private var email = ""
    @State private var password = ""
    @State private var mode: Mode = .logIn
    @State private var isSubmitting = false
    @FocusState private var focusedField: Field?

    private enum Mode: String, CaseIterable {
        case logIn = "Log in"
        case signUp = "Sign up"
    }

    private enum Field {
        case email
        case password
    }

    var body: some View {
        ZStack {
            background

            ScrollView {
                VStack(spacing: 22) {
                    hero
                    card
                    guestButton
                    footer
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 28)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    // MARK: Pieces

    private var background: some View {
        ZStack {
            Theme.brandGradient
            Circle()
                .fill(Theme.amber.opacity(0.30))
                .frame(width: 320, height: 320)
                .blur(radius: 70)
                .offset(x: 150, y: -300)
            Circle()
                .fill(Color.white.opacity(0.14))
                .frame(width: 280, height: 280)
                .blur(radius: 60)
                .offset(x: -160, y: 280)
        }
        .ignoresSafeArea()
    }

    private var hero: some View {
        VStack(spacing: 12) {
            LogoMark(size: 92)
            Text("Doc Scanner")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("Scan, crop, filter & export PDFs")
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.8))
        }
        .padding(.top, 24)
    }

    private var card: some View {
        VStack(spacing: 14) {
            Picker("Mode", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            #if DEBUG
            field(icon: "server.rack") {
                TextField("Server URL (debug only)", text: $serverURLText)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            #endif

            field(icon: "envelope") {
                TextField("Email", text: $email)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)
                    .textContentType(.username)
                    .focused($focusedField, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .password }
            }

            field(icon: "lock") {
                SecureField(mode == .signUp ? "Password (8+ characters)" : "Password", text: $password)
                    .textContentType(mode == .signUp ? .newPassword : .password)
                    .focused($focusedField, equals: .password)
                    .submitLabel(.go)
                    .onSubmit { Task { await submit() } }
            }

            if let error = session.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.red.opacity(0.85), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            Button {
                Task { await submit() }
            } label: {
                if isSubmitting {
                    ProgressView().tint(.white)
                } else {
                    Text(mode == .logIn ? "Log in" : "Create account")
                }
            }
            .buttonStyle(.primary)
            .disabled(isSubmitting || email.isEmpty || password.isEmpty)

            if isSubmitting {
                WakeHint()
            }

            HStack {
                Rectangle().fill(Color.secondary.opacity(0.3)).frame(height: 1)
                Text("or").font(.footnote).foregroundStyle(.secondary)
                Rectangle().fill(Color.secondary.opacity(0.3)).frame(height: 1)
            }

            SignInWithAppleButton(mode == .logIn ? .signIn : .signUp, onRequest: { request in
                request.requestedScopes = [.email]
            }, onCompletion: handleAppleCompletion)
            .signInWithAppleButtonStyle(.black)
            .frame(height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.white.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.2), radius: 20, x: 0, y: 10)
        .animation(.easeInOut(duration: 0.2), value: mode)
    }

    private func field<Content: View>(icon: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 22)
            content()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(Color(.systemBackground).opacity(0.85), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var guestButton: some View {
        VStack(spacing: 6) {
            Button {
                Haptics.tap()
                session.continueAsGuest()
            } label: {
                Text("Continue as Guest")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background(Color.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.45), lineWidth: 1)
                    )
            }
            Text("Scan, crop, filter and export a PDF — nothing is saved to an account.")
                .font(.footnote)
                .foregroundStyle(Color.white.opacity(0.8))
                .multilineTextAlignment(.center)
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Link("Privacy Policy", destination: ServerConfig.productionURL.appendingPathComponent("privacy.html"))
            Text("·")
            Link("Support", destination: ServerConfig.productionURL.appendingPathComponent("support.html"))
        }
        .font(.footnote)
        .foregroundStyle(Color.white.opacity(0.85))
        .tint(.white)
    }

    // MARK: Actions

    private func submit() async {
        focusedField = nil
        ServerConfig.baseURL = URL(string: serverURLText)
        isSubmitting = true
        defer { isSubmitting = false }

        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let succeeded: Bool
        switch mode {
        case .logIn:
            succeeded = await session.login(email: trimmedEmail, password: password)
        case .signUp:
            succeeded = await session.register(email: trimmedEmail, password: password)
        }
        if succeeded { Haptics.success() }
    }

    private func handleAppleCompletion(_ result: Result<ASAuthorization, Error>) {
        ServerConfig.baseURL = URL(string: serverURLText)
        switch result {
        case .success(let authorization):
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = credential.identityToken,
                let token = String(data: tokenData, encoding: .utf8)
            else {
                session.errorMessage = "Couldn't read the Apple credential."
                return
            }
            let code = credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
            Task {
                _ = await session.loginWithApple(identityToken: token, authorizationCode: code, email: credential.email)
            }
        case .failure(let error):
            // Closing Apple's sheet isn't an error worth showing.
            if (error as? ASAuthorizationError)?.code != .canceled {
                session.errorMessage = error.localizedDescription
            }
        }
    }
}
