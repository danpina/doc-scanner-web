import Combine
import Foundation

@MainActor
final class SessionStore: ObservableObject {
    @Published var user: User?
    /// Guest mode: the whole scan/crop/filter/export flow, but nothing is saved to an account.
    @Published var isGuest = false
    @Published var isCheckingSession = true
    @Published var errorMessage: String?

    init() {
        APIClient.shared.onUnauthorized = { [weak self] in
            Task { @MainActor in
                // Only explain it if someone was actually signed in; on a fresh launch the
                // first /api/me check is expected to say "not logged in".
                if self?.user != nil {
                    self?.errorMessage = "Your session has ended. Please log in again."
                }
                self?.user = nil
            }
        }
    }

    func bootstrap() async {
        await refreshMe()
        isCheckingSession = false
    }

    func refreshMe() async {
        do {
            user = try await APIClient.shared.send("/api/me", method: .get)
        } catch {
            user = nil
        }
    }

    /// Runs right after the server accepted a log-in/sign-up/Apple request. The session cookie
    /// should now authenticate `/api/me`; if it doesn't, say so instead of silently staying on the
    /// login screen.
    private func finishSignIn() async -> Bool {
        do {
            user = try await APIClient.shared.send("/api/me", method: .get)
            isGuest = false
            return true
        } catch {
            user = nil
            errorMessage = "The server accepted your details, but the app couldn't open your account (\(error.localizedDescription)). Please try again."
            return false
        }
    }

    func login(email: String, password: String) async -> Bool {
        errorMessage = nil
        do {
            struct LoginBody: Encodable {
                let email: String
                let password: String
            }
            let _: LoginResponse = try await APIClient.shared.send(
                "/api/login", method: .post,
                body: LoginBody(email: email, password: password)
            )
            return await finishSignIn()
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func register(email: String, password: String) async -> Bool {
        errorMessage = nil
        do {
            struct RegisterBody: Encodable {
                let email: String
                let password: String
            }
            let _: LoginResponse = try await APIClient.shared.send(
                "/api/register", method: .post,
                body: RegisterBody(email: email, password: password)
            )
            return await finishSignIn()
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func loginWithApple(identityToken: String, authorizationCode: String?, email: String?) async -> Bool {
        errorMessage = nil
        do {
            struct AppleBody: Encodable {
                let identityToken: String
                let authorizationCode: String?
                let email: String?
            }
            let _: LoginResponse = try await APIClient.shared.send(
                "/api/auth/apple", method: .post,
                body: AppleBody(identityToken: identityToken, authorizationCode: authorizationCode, email: email)
            )
            return await finishSignIn()
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func continueAsGuest() {
        errorMessage = nil
        isGuest = true
    }

    /// Changes the password — or sets the first one (pass `current: nil`) for an account created
    /// with Apple. Returns an error message on failure, nil on success.
    func changePassword(current: String?, new: String) async -> String? {
        do {
            struct ChangeBody: Encodable {
                let currentPassword: String?
                let newPassword: String
            }
            try await APIClient.shared.sendNoContent(
                "/api/me/password", method: .post,
                body: ChangeBody(currentPassword: current, newPassword: new)
            )
            await refreshMe()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Permanently deletes the signed-in account (saved scans included). Returns an error
    /// message on failure, nil on success.
    func deleteAccount() async -> String? {
        do {
            try await APIClient.shared.sendNoContent("/api/me", method: .delete)
            user = nil
            isGuest = false
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func logout() async {
        try? await APIClient.shared.sendNoContent("/api/logout", method: .post)
        user = nil
    }
}
