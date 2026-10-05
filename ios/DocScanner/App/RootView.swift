import SwiftUI

struct RootView: View {
    @EnvironmentObject var session: SessionStore

    var body: some View {
        Group {
            if session.isCheckingSession {
                VStack(spacing: 12) {
                    ProgressView()
                    WakeHint().padding(.horizontal)
                }
            } else if session.user != nil {
                ScansListView()
            } else if session.isGuest {
                ScanFlowView(
                    allowsSaving: false,
                    closeTitle: "Log in",
                    onClose: { session.isGuest = false },
                    onSaved: {}
                )
            } else {
                LoginView()
            }
        }
        .task { await session.bootstrap() }
    }
}
