//
//  InAppBrowser.swift
//  RWF FEED
//
//  Feed post text can contain <a href> links (e.g. references to raider.io pages, tweets,
//  external articles). By default, tapping a link in a SwiftUI Text hands off to the
//  system's default browser via the openURL environment action. This overrides that action
//  at the app root so links open in an in-app Safari sheet instead — SFSafariViewController
//  is WebKit-based, but comes with the full browser chrome (address bar, reader mode, share)
//  for free, so there's no custom WKWebView/navigation UI to build and maintain.
//

import SwiftUI
import SafariServices

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

private struct IdentifiableURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

private struct InAppLinksModifier: ViewModifier {
    @State private var presentedURL: IdentifiableURL?

    func body(content: Content) -> some View {
        content
            .environment(\.openURL, OpenURLAction { url in
                presentedURL = IdentifiableURL(url: url)
                return .handled
            })
            .sheet(item: $presentedURL) { wrapper in
                SafariView(url: wrapper.url)
                    .ignoresSafeArea()
            }
    }
}

extension View {
    /// Routes every link tap underneath this view (including in sheets presented from it)
    /// through an in-app Safari sheet instead of the system browser.
    func opensLinksInApp() -> some View {
        modifier(InAppLinksModifier())
    }
}
