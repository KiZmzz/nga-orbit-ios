import SwiftUI
import WebKit
import NGAKit

struct WebsiteLogin: View {
    let session: SessionStore
    let login: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var webError: String?
    @State private var saving = false
    @State private var reloadVersion = 0
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text("请在 NGA 网站完成操作，然后点「完成」。密码只在网站内输入。")
                    .font(.footnote).foregroundStyle(.secondary).padding(12)
                if let message = webError {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(message).font(.subheadline)
                        Text(session.network.message).font(.footnote).foregroundStyle(.secondary)
                        HStack {
                            Button("重新加载") {
                                webError = nil
                                Task { await session.network.requestAccess(to: session.host.url); reloadVersion += 1 }
                            }.buttonStyle(.borderedProminent)
                            Button("系统设置") { session.network.openSettings() }.buttonStyle(.bordered)
                        }
                    }.padding().frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemBackground))
                }
                WebsiteView(session: session, login: login, reloadVersion: reloadVersion, error: $webError)
            }
            .navigationTitle(login ? "NGA 网页登录" : "NGA 网页验证")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        saving = true
                        Task { await session.sync(); dismiss() }
                    }.disabled(saving)
                }
            }
            .task { await session.network.requestAccess(to: session.host.url); reloadVersion += 1 }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active && webError != nil { reloadVersion += 1 }
            }
            .onChange(of: session.network.available) { _, available in
                if available && webError != nil { reloadVersion += 1 }
            }
        }
    }
}

private struct WebsiteView: UIViewRepresentable {
    let session: SessionStore
    let login: Bool
    let reloadVersion: Int
    @Binding var error: String?
    func makeCoordinator() -> Coordinator { Coordinator(error: $error, network: session.network) }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = session.websiteStore
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        view.allowsBackForwardNavigationGestures = true
        let url = login ? URL(string: "/nuke.php?__lib=login&__act=account&login", relativeTo: session.host.url)!.absoluteURL : session.host.url
        view.load(URLRequest(url: url))
        context.coordinator.entryURL = url
        context.coordinator.reloadVersion = reloadVersion
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {
        if context.coordinator.reloadVersion != reloadVersion {
            context.coordinator.reloadVersion = reloadVersion
            if view.url != nil { view.reload() }
            else if let url = context.coordinator.entryURL { view.load(URLRequest(url: url)) }
        }
    }
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        @Binding var error: String?
        let network: Connectivity
        var entryURL: URL?
        var reloadVersion = 0
        init(error: Binding<String?>, network: Connectivity) { _error = error; self.network = network }
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { error = nil }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            if (error as NSError).code != NSURLErrorCancelled { self.error = network.describe(error) }
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { self.error = network.describe(error) }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url, url.scheme == "https" || url.scheme == "about" else {
                error = "网页尝试打开非 HTTPS 地址，请使用网站提供的其他登录方式。"
                decisionHandler(.cancel); return
            }
            decisionHandler(.allow)
        }
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if action.targetFrame == nil, action.request.url?.scheme == "https" { webView.load(action.request) }
            return nil
        }
        private func presenter(_ view: WKWebView) -> UIViewController? {
            var parent = view.window?.rootViewController
            while let presented = parent?.presentedViewController { parent = presented }
            return parent
        }
        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor () -> Void) {
            guard let parent = presenter(webView) else { completionHandler(); return }
            let alert = UIAlertController(title: "NGA 网页", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "好", style: .default) { _ in completionHandler() })
            parent.present(alert, animated: true)
        }
        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor (Bool) -> Void) {
            guard let parent = presenter(webView) else { completionHandler(false); return }
            let alert = UIAlertController(title: "NGA 网页", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(false) })
            alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in completionHandler(true) })
            parent.present(alert, animated: true)
        }
    }
}
