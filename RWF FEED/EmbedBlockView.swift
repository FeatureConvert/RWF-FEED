//
//  EmbedBlockView.swift
//  RWF FEED
//
//  Renders an iframe embed from a post — raider.io's own widgets (boss-rankings
//  leaderboards, pull-attempt charts) or a Twitch clip — inline via WKWebView.
//

import SwiftUI
import WebKit

private struct WebEmbed: UIViewRepresentable {
    let info: EmbedInfo
    @Binding var height: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(info: info, height: $height)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        if !info.isTwitchClip {
            config.userContentController.add(context.coordinator, name: "heightUpdate")
        }
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        load(into: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    private func load(into webView: WKWebView) {
        if info.isTwitchClip {
            // Twitch clip embeds check the `parent` query param against the *actual*
            // origin of the page embedding the iframe. Loading the clip URL directly (as
            // the WKWebView's own top-level document) has no such parent, so Twitch
            // refuses to play it. Wrapping it in a tiny shell document whose base URL is
            // raider.io makes the nested iframe's parent genuinely be raider.io, matching
            // the `parent=raider.io` the clip URL already declares.
            let html = """
            <html><body style="margin:0;padding:0;background:transparent;">
            <iframe src="\(info.url.absoluteString)" frameborder="0" allowfullscreen \
            style="width:100%;height:100%;border:0;"></iframe>
            </body></html>
            """
            webView.loadHTMLString(html, baseURL: URL(string: "https://raider.io"))
        } else {
            webView.load(URLRequest(url: info.url))
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let info: EmbedInfo
        @Binding var height: CGFloat

        init(info: EmbedInfo, height: Binding<CGFloat>) {
            self.info = info
            _height = height
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Twitch's player lives inside a nested iframe we don't control, so measuring
            // our shell document's height wouldn't reflect the real player size — only
            // auto-fit raider.io's own widget pages, which render directly in this document.
            guard !info.isTwitchClip else { return }
            // The widget's own content (the ranking table) typically arrives via an async
            // fetch *after* the page finishes loading, so a single measurement here would
            // catch it too early. A ResizeObserver reports every subsequent height change
            // as that content streams in; the two setTimeout fallbacks cover browsers/timing
            // where the observer's initial callback fires before layout has settled.
            let js = """
            (function() {
              function report() {
                window.webkit.messageHandlers.heightUpdate.postMessage(document.documentElement.scrollHeight);
              }
              report();
              new ResizeObserver(report).observe(document.body);
              setTimeout(report, 500);
              setTimeout(report, 1500);
            })();
            """
            webView.evaluateJavaScript(js)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let number = message.body as? NSNumber else { return }
            let measured = CGFloat(truncating: number)
            guard measured > 0 else { return }
            DispatchQueue.main.async {
                self.height = min(max(measured, 60), 700)
            }
        }
    }
}

struct EmbedBlockView: View {
    let info: EmbedInfo
    @State private var height: CGFloat

    init(info: EmbedInfo) {
        self.info = info
        _height = State(initialValue: info.height)
    }

    var body: some View {
        WebEmbed(info: info, height: $height)
            .frame(height: height)
            .background(Theme.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
