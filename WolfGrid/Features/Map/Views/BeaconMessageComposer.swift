import MessageUI
import SwiftUI

enum BeaconMessageComposer {
    static let unavailableUserMessage = "Couldn't open Messages. Try again in a moment."

    static var canSendText: Bool {
        MFMessageComposeViewController.canSendText()
    }
}

struct BeaconMessageComposeRequest: Identifiable, Equatable {
    let id = UUID()
    let recipients: [String]
    let body: String
}

struct BeaconMessageComposeSheet: UIViewControllerRepresentable {
    let request: BeaconMessageComposeRequest
    let onComplete: (MessageComposeResult) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.messageComposeDelegate = context.coordinator
        controller.recipients = request.recipients
        controller.body = request.body
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {
        uiViewController.recipients = request.recipients
        uiViewController.body = request.body
    }

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        private let onComplete: (MessageComposeResult) -> Void

        init(onComplete: @escaping (MessageComposeResult) -> Void) {
            self.onComplete = onComplete
        }

        func messageComposeViewController(
            _ controller: MFMessageComposeViewController,
            didFinishWith result: MessageComposeResult
        ) {
            onComplete(result)
            controller.dismiss(animated: true)
        }
    }
}

struct BeaconActivityShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // No-op.
    }
}
