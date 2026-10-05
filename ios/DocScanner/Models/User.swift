import Foundation

/// GET /api/me — the signed-in user.
struct User: Decodable, Equatable {
    let id: String
    let email: String
    let isAdmin: Bool
}

/// POST /api/login only confirms the login; we refetch /api/me for the full User.
struct LoginResponse: Decodable {
    let email: String
}
