import Contacts
import ContactsUI
import SwiftUI

/// Apple's own "new contact" screen, filled in from a scanned business card. The user checks
/// the details and taps Done to save, or Cancel; the app itself never reads the address book.
struct ContactSheet: UIViewControllerRepresentable {
    let contact: CNMutableContact
    let onFinish: () -> Void

    func makeUIViewController(context: Context) -> UINavigationController {
        let controller = CNContactViewController(forNewContact: contact)
        controller.delegate = context.coordinator
        return UINavigationController(rootViewController: controller)
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    final class Coordinator: NSObject, CNContactViewControllerDelegate {
        let onFinish: () -> Void

        init(onFinish: @escaping () -> Void) {
            self.onFinish = onFinish
        }

        func contactViewController(_ viewController: CNContactViewController, didCompleteWith contact: CNContact?) {
            onFinish()
        }
    }
}
