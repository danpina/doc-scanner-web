import Foundation

/// GET /api/me — the signed-in user.
struct User: Decodable, Equatable {
    let id: String
    let email: String
    let isAdmin: Bool
    /// True for accounts created with Sign in with Apple (they have no password to change).
    /// Optional so a server that doesn't send it yet still decodes.
    let hasApple: Bool?
    /// False for an account created with Sign in with Apple that never chose a password: the
    /// app then offers "Set a password". Optional for older servers; nil is treated as "has one".
    let hasPassword: Bool?
}

/// POST /api/login only confirms the login; we refetch /api/me for the full User.
struct LoginResponse: Decodable {
    let email: String
}
