import SwiftUI
import MessageUI

struct BeaconMessageDraft: Identifiable {
    let id = UUID()
    let recipients: [String]
    let body: String
}

struct BeaconMessageComposer: UIViewControllerRepresentable {
    let recipients: [String]
    let body: String
    let onComplete: (MessageComposeResult) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(dismiss: dismiss, onComplete: onComplete)
    }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.messageComposeDelegate = context.coordinator
        controller.recipients = recipients
        controller.body = body
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        private let dismiss: DismissAction
        private let onComplete: (MessageComposeResult) -> Void

        init(dismiss: DismissAction, onComplete: @escaping (MessageComposeResult) -> Void) {
            self.dismiss = dismiss
            self.onComplete = onComplete
        }

        func messageComposeViewController(
            _ controller: MFMessageComposeViewController,
            didFinishWith result: MessageComposeResult
        ) {
            onComplete(result)
            dismiss()
        }
    }
}
