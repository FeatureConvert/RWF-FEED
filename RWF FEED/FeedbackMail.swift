//
//  FeedbackMail.swift
//  RWF FEED
//
//  Lets the user email a bug report or feature request straight from the app. Uses the
//  native Mail compose sheet (MFMailComposeViewController) when a Mail account is
//  configured, since that never requires the app to touch SMTP credentials or an email
//  API — it just hands off a pre-filled draft for the user to review and send themselves.
//  Falls back to a mailto: URL (handed to whatever mail client is installed) if Mail isn't
//  configured on this device.
//

import SwiftUI
import MessageUI
import UIKit

enum FeedbackMail {
    static let recipient = "Nexrax@icloud.com"
    static let subject = "RWF Feed Feedback"

    static var body: String {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return """
        Bug or feature request:


        ---
        App version: \(appVersion) (\(buildNumber))
        iOS: \(UIDevice.current.systemVersion)
        Device: \(UIDevice.current.model)
        """
    }

    /// Best-effort fallback for devices with no Mail account configured (MFMailCompose
    /// requires one). mailto: at least hands off to whatever mail client is installed, if any.
    static var mailtoURL: URL? {
        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? subject
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? body
        return URL(string: "mailto:\(recipient)?subject=\(encodedSubject)&body=\(encodedBody)")
    }
}

/// Wraps MFMailComposeViewController for SwiftUI — pre-filled to FeedbackMail's recipient,
/// subject, and body, dismissing itself once the user sends, cancels, or the compose fails.
struct MailComposeView: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.setToRecipients([FeedbackMail.recipient])
        controller.setSubject(FeedbackMail.subject)
        controller.setMessageBody(FeedbackMail.body, isHTML: false)
        controller.mailComposeDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(dismiss: dismiss)
    }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        private let dismiss: DismissAction

        init(dismiss: DismissAction) {
            self.dismiss = dismiss
        }

        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            dismiss()
        }
    }
}
