import SwiftUI

extension View {
    /// Lets the user get rid of the keyboard: a "Done" button above it, and
    /// dragging the scroll content down dismisses it too.
    func keyboardDismissible() -> some View {
        self
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil, from: nil, for: nil
                        )
                    }
                }
            }
    }
}
