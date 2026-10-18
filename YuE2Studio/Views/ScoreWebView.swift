import SwiftUI
import WebKit

/// 乐谱 WebView：加载 bundle 内 abcjs 渲染 ABC（离线可用）。
struct ScoreWebView: View {
    let abc: String

    var body: some View {
        ZStack {
            Theme.card
            ABCWebView(html: ScoreRenderer.html(forScore: abc))
                .background(Theme.card)
        }
    }
}

private struct ABCWebView: UIViewRepresentable {
    let html: String

    func makeUIView(context: Context) -> WKWebView {
        let wv = WKWebView()
        wv.isOpaque = false
        wv.backgroundColor = .clear
        wv.scrollView.backgroundColor = .clear
        return wv
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let base = Bundle.main.resourceURL
        webView.loadHTMLString(html, baseURL: base)
    }
}

#Preview {
    ScoreWebView(abc: "X:1\nT:Test\nM:4/4\nL:1/4\nK:C\nCDEF GABc|")
        .frame(height: 300)
}
