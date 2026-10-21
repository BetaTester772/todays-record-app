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
    /// 화면이 ready를 보내면 불린다. 다시 불러온 뒤에도 다시 불린다.
    var onReady: ((RecordWebView) -> Void)?
    private(set) var isReady = false
    /// 메뉴 막대와 Dock이 덮는 화면 가장자리(포인트). 준비되면 화면에 보낸다.
    var insets = NSEdgeInsetsZero {
        didSet { sendInsets() }
    }
    /// 그리기 멈춤(명세 4.7). 바뀔 때와 준비될 때 화면에 보낸다.
    var paused = false {
        didSet { if paused != oldValue { sendPaused() } }
    }
    /// 그리기를 멈춰도 소리는 계속 낼지(창이 다른 창에 가려졌을 때만). 명세 6장 29.
    var keepSound = false {
        didSet { if keepSound != oldValue { sendPaused() } }
    }
    private let pageURL: URL?

    init(frame: NSRect, role: Role, screenID: String, options: LaunchOptions) {
        self.role = role
        self.screenID = screenID
        self.pageURL = Bundle.main.url(forResource: "index", withExtension: "html")

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        // 레코드 소리(명세 6장 29)는 사용자가 누르지 않아도 재생돼야 한다.
        config.mediaTypesRequiringUserActionForPlayback = []
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
        isReady = false
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

    // MARK: - Swift → JavaScript (명세 5장)

    func sendNowPlaying(_ payload: [String: Any]) {
        call("nowPlaying", [payload])
    }

    func sendArt(dataURL: String, version: String) {
        call("art", [dataURL, version])
    }

    private func sendPaused() {
        call("setPaused", [paused, ["sound": keepSound]])
    }

    private func sendInsets() {
        call("setInsets", [["top": insets.top, "right": insets.right, "bottom": insets.bottom, "left": insets.left]])
    }

    func sendOptions(_ options: [String: Any]) {
        call("setOptions", [options])
    }

    func clearRecord() {
        call("clearRecord", [])
    }

    /// 설정 창의 Play Test Sound. 소리를 꺼 둬도 한 번 들려준다.
    func testSound() {
        call("testSound", [])
    }

    /// 투명 배경이면 웹뷰도 배경을 그리지 않는다. 명세 4.4.
    func setTransparent(_ transparent: Bool) {
        underPageBackgroundColor = transparent ? .clear : nil
        setValue(!transparent, forKey: "drawsBackground")
    }

    func sendVolume(_ payload: [String: Any]) {
        call("setVolume", [payload])
    }

    /// 인자를 JSON 배열로 직렬화해서 넘긴다. 따옴표와 줄바꿈이 안전하게 이스케이프된다.
    private func call(_ function: String, _ arguments: [Any]) {
        guard isReady else { return }
        guard let data = try? JSONSerialization.data(withJSONObject: arguments) else {
            Log.web.error("\(function, privacy: .public) 인자를 직렬화하지 못함")
            return
        }
        let script = "TodaysRecord.\(function).apply(null, \(String(decoding: data, as: UTF8.self)));"
        evaluateJavaScript(script) { _, error in
            if let error {
                Log.web.error("\(function, privacy: .public) 호출 실패 \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - JavaScript → Swift

    fileprivate func receive(_ message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else {
            Log.web.debug("알 수 없는 메시지 \(String(describing: message.body))")
            return
        }
        switch type {
        case "ready":
            Log.web.info("ready screen=\(self.screenID, privacy: .public)")
            isReady = true
            sendInsets()
            onReady?(self)
            sendPaused()
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
