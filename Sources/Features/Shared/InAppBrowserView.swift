import SwiftUI
import WebKit

struct InAppBrowserView: UIViewRepresentable {
    let url: URL
    var persistentWebView: WKWebView? = nil

    final class Coordinator: NSObject, WKNavigationDelegate {
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            // iPad in-car use can trigger memory pressure; WKWebView sometimes blanks out.
            // A simple reload usually recovers.
            webView.reload()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        if let persistentWebView {
            persistentWebView.navigationDelegate = context.coordinator
            persistentWebView.allowsBackForwardNavigationGestures = true
            persistentWebView.scrollView.contentInsetAdjustmentBehavior = .never
            persistentWebView.isOpaque = false
            persistentWebView.backgroundColor = .clear
            persistentWebView.scrollView.backgroundColor = .clear
            return persistentWebView
        }

        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.navigationDelegate = context.coordinator

        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard webView.url != url else { return }
        webView.load(URLRequest(url: url))
    }
}
