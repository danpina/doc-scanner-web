import Foundation

/// The only web addresses the app knows about: two static pages, opened in the browser from
/// Settings. The app itself never contacts a server.
enum AppLinks {
    static let privacy = URL(string: "https://danpina.github.io/doc-scanner-web/privacy.html")!
    static let support = URL(string: "https://danpina.github.io/doc-scanner-web/support.html")!
}
