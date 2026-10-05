import SwiftUI

@main
struct DocScannerApp: App {
    @StateObject private var session = SessionStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
        }
    }
}
