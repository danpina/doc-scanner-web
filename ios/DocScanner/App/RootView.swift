import SwiftUI

struct RootView: View {
    @ObservedObject var inbox: ImportInbox

    var body: some View {
        ScansListView(inbox: inbox)
    }
}
