import AppKit
import WebKit

/// 레코드 화면 웹뷰와 브리지. 명세 4.4, 5장.
final class RecordWebView: WKWebView {
    enum Role: String {
        case primary
        case mirror
    }

    static let messageName = "todaysRecord"

    let role: Role
    let screenID: String
    private let pageURL: URL?

    init(frame: NSRect, role: Role, screenID: String, options: LaunchOptions) {
        self.role = role
        self.screenID = screenID
        self.pageURL = Bundle.main.url(forResource: "index", withExtension: "html")

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let controller = WKUserContentController()
        controller.addUserScript(WKUserScript(
            source: Self.nativeScript(role: role, screenID: screenID, demo: options.demo),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        config.userContentController = controller

        super.init(frame: frame, configuration: config)

        // 핸들러가 웹뷰를 강하게 잡으면 순환 참조가 생기므로 약한 참조 상자를 둔다.
        controller.add(WeakMessageHandler(self), name: Self.messageName)
        navigationDelegate = self
        isInspectable = options.windowed
        allowsBackForwardNavigationGestures = false
        allowsMagnification = false

        load()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func load() {
        guard let pageURL else {
            Log.web.error("번들에서 index.html을 찾지 못함")
            return
        }
        loadFileURL(pageURL, allowingReadAccessTo: pageURL.deletingLastPathComponent())
    }

    private static func nativeScript(role: Role, screenID: String, demo: Bool) -> String {
        let native: [String: Any] = ["role": role.rawValue, "screen": screenID, "demo": demo]
        let data = (try? JSONSerialization.data(withJSONObject: native)) ?? Data("{}".utf8)
        let json = String(decoding: data, as: UTF8.self)
        return "window.__TR_NATIVE__ = \(json);"
    }

    fileprivate func receive(_ message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else {
            Log.web.debug("알 수 없는 메시지 \(String(describing: message.body))")
            return
        }
        switch type {
        case "ready":
            Log.web.info("ready screen=\(self.screenID, privacy: .public)")
        case "log":
            Log.web.debug("js: \(String(describing: body["message"] ?? ""))")
        default:
            Log.web.debug("메시지 \(type)")
        }
    }
}

extension RecordWebView: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        let scheme = navigationAction.request.url?.scheme
        if scheme == "file" || scheme == "about" {
            decisionHandler(.allow)
        } else {
            Log.web.notice("이동 차단 \(navigationAction.request.url?.absoluteString ?? "")")
            decisionHandler(.cancel)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Log.web.info("페이지 로드 완료 screen=\(self.screenID, privacy: .public)")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Log.web.error("페이지 로드 실패 \(error.localizedDescription)")
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        Log.web.error("웹 콘텐츠 프로세스 종료, 다시 불러옴")
        load()
    }
}

private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: RecordWebView?

    init(_ target: RecordWebView) {
        self.target = target
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.receive(message)
    }
}
