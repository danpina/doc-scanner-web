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
            Task { @MainActor in self?.user = nil }
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
            await refreshMe()
            if user != nil { isGuest = false }
            return user != nil
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func continueAsGuest() {
        errorMessage = nil
        isGuest = true
    }

    func logout() async {
        try? await APIClient.shared.sendNoContent("/api/logout", method: .post)
        user = nil
    }
}
