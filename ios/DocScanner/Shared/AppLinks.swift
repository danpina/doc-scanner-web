import Foundation

/// The only web addresses the app knows about: five static pages, opened in the browser from
/// Settings. The app itself never contacts a server.
enum AppLinks {
    static let privacy = URL(string: "https://danpina.github.io/doc-scanner-web/privacy.html")!
    static let support = URL(string: "https://danpina.github.io/doc-scanner-web/support.html")!
    static let contact = URL(string: "https://danpina.github.io/doc-scanner-web/contact.html")!
    static let terms = URL(string: "https://danpina.github.io/doc-scanner-web/terms.html")!
    static let licenses = URL(string: "https://danpina.github.io/doc-scanner-web/licenses.html")!
}
