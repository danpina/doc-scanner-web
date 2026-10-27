import SwiftUI

@main
struct DocScannerApp: App {
    @StateObject private var inbox = ImportInbox()

    var body: some Scene {
        WindowGroup {
            RootView(inbox: inbox)
                .onOpenURL { url in
                    inbox.receive(url)
                }
        }
    }
}
