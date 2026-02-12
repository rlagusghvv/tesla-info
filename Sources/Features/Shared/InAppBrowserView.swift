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
        let webView: WKWebView
        if let persistentWebView {
            webView = persistentWebView
        } else {
            webView = SharedInAppBrowserPool.shared.webView()
        }
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

private final class SharedInAppBrowserPool {
    static let shared = SharedInAppBrowserPool()

    private var cached: WKWebView?

    private init() {}

    func webView() -> WKWebView {
        if let cached {
            return cached
        }

        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.websiteDataStore = .default()

        let created = WKWebView(frame: .zero, configuration: configuration)
        cached = created
        return created
    }
}
