import SwiftUI

/// Place this next to a spinner. It stays invisible unless the wait runs past a few
/// seconds, then explains why: the free hosting plan sleeps when idle and takes up
/// to a minute to wake on the first request.
struct WakeHint: View {
    @State private var visible = false

    var body: some View {
        Group {
            if visible {
                Text("Waking up the server… this can take up to a minute the first time.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !Task.isCancelled { visible = true }
        }
    }
}
