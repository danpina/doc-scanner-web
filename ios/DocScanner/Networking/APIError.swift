import Foundation

struct APIError: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
