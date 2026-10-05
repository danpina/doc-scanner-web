import Foundation

/// The backend base URL. Defaults to the deployed production host; Debug builds
/// can override it (Login screen) to point at a local dev server or LAN IP.
enum ServerConfig {
    static let productionURL = URL(string: "https://doc-scanner-web.onrender.com")!

    private static let key = "serverBaseURL"

    static var baseURL: URL? {
        get {
            #if DEBUG
            if let raw = UserDefaults.standard.string(forKey: key), !raw.isEmpty, let url = URL(string: raw) {
                return url
            }
            #endif
            return productionURL
        }
        set {
            #if DEBUG
            UserDefaults.standard.set(newValue?.absoluteString, forKey: key)
            #endif
        }
    }
}
