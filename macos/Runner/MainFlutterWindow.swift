import Cocoa
import FlutterMacOS
import WebKit
import IOKit.pwr_mgt

class MainFlutterWindow: NSWindow {
  private var host: MacHost?

  override func awakeFromNib() {
    let controller = FlutterViewController()
    contentViewController = controller
    title = "此刻"
    appearance = NSAppearance(named: .darkAqua)
    titlebarAppearsTransparent = true
    toolbarStyle = .unified
    backgroundColor = .windowBackgroundColor
    contentMinSize = NSSize(width: 640, height: 480)
    if !setFrameUsingName("ShikeMainWindow") {
      let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
      setContentSize(NSSize(width: min(1440, screen.width * 0.92), height: min(900, screen.height * 0.92)))
      center()
    }
    setFrameAutosaveName("ShikeMainWindow")
    RegisterGeneratedPlugins(registry: controller)
    host = MacHost(window: self, messenger: controller.engine.binaryMessenger)
    super.awakeFromNib()
  }
}

/// WebKit is a private data worker; all visible UI remains native Flutter.
final class MacHost: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
  private weak var window: NSWindow?
  private let channel: FlutterMethodChannel
  private var web: WKWebView?
  private var ready: FlutterResult?
  private var observers: [NSObjectProtocol] = []
  private var workspaceObservers: [NSObjectProtocol] = []
  private var assertion: IOPMAssertionID = 0
  private var wantsAwake = false
  private var awakeFailed = false
  private var resumeSerial = 0
  private var sleeping = false

  init(window: NSWindow, messenger: FlutterBinaryMessenger) {
    self.window = window
    channel = FlutterMethodChannel(name: "com.kingxcode.shike/macos", binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in self?.handle(call, result: result) }
    let center = NotificationCenter.default
    for name in [NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification,
                 NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification,
                 NSWindow.didChangeOcclusionStateNotification] {
      observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in self?.publish() })
    }
    for name in [NSApplication.didHideNotification, NSApplication.didUnhideNotification] {
      observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.publish() })
    }
    observers.append(center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in self?.stop() })
    let workspace = NSWorkspace.shared.notificationCenter
    workspaceObservers.append(workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
      self?.sleeping = true; self?.publish()
    })
    workspaceObservers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
      self?.sleeping = false; self?.resumeSerial += 1; self?.publish(resume: true)
    })
  }

  private var visible: Bool {
    guard let window = window else { return false }
    return !sleeping && window.isVisible && !window.isMiniaturized && !NSApp.isHidden
  }
  private var state: [String: Any] {
    return ["visible": visible, "resumeSerial": resumeSerial,
            "wakeSupported": true, "wakeStatus": !wantsAwake ? "off" : awakeFailed ? "failed" : assertion != 0 ? "active" : "released",
            "fullscreenSupported": true, "fullscreen": window?.styleMask.contains(.fullScreen) == true,
            "fullscreenError": false]
  }
  private func json(_ value: Any) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])
    return String(decoding: data, as: UTF8.self)
  }
  private func event(_ value: [String: Any]) { channel.invokeMethod("serviceEvent", arguments: value) }
  private func publish(resume: Bool = false) {
    updateAwake()
    event(["type":"state", "state":state])
    if let source = try? json(["visible": visible, "resume": resume]) {
      web?.evaluateJavaScript("void timeNestMac.call('visibility-host','visibility',\(source))", completionHandler: nil)
    }
  }
  private func updateAwake() {
    if wantsAwake && visible {
      if assertion == 0 {
        let status = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
          IOPMAssertionLevel(kIOPMAssertionLevelOn), "此刻时钟展示" as CFString, &assertion)
        awakeFailed = status != kIOReturnSuccess
        if awakeFailed { assertion = 0 }
      }
    } else if assertion != 0 {
      IOPMAssertionRelease(assertion); assertion = 0
    }
  }
  private func open(_ raw: Any?) {
    guard let text = raw as? String, text.count < 4096,
          let url = URL(string: text), ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
          let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else { return }
    NSWorkspace.shared.open(url)
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "supportDirectory":
      do {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        result(base.appendingPathComponent("TimeNest", isDirectory: true).path)
      } catch { result(FlutterError(code:"storage", message:"无法创建应用存储目录。", details:nil)) }
    case "state": result(state)
    case "startService":
      guard let args = call.arguments as? [String: Any], let scripts = args["scripts"] as? [String], scripts.count == 3,
            let storage = args["storage"] as? [String: String], let source = try? json(storage) else {
        result(FlutterError(code:"arguments",message:"服务启动参数无效。",details:nil)); return
      }
      stopWorker()
      ready = result
      let config = WKWebViewConfiguration()
      config.websiteDataStore = .nonPersistent()
      if #available(macOS 14.0, *) { config.preferences.inactiveSchedulingPolicy = .none }
      config.userContentController.add(self, name:"shike")
      config.userContentController.addUserScript(WKUserScript(source:"globalThis.__shikeStorage = \(source);",injectionTime:.atDocumentStart,forMainFrameOnly:true))
      for script in scripts {
        config.userContentController.addUserScript(WKUserScript(source:script,injectionTime:.atDocumentStart,forMainFrameOnly:true))
      }
      let view = WKWebView(frame: NSRect(x:0,y:0,width:1,height:1),configuration:config)
      view.navigationDelegate = self
      web = view
      // A real public base origin also makes the existing HTTPS probe measurable.
      // The HTML and scripts themselves come exclusively from this app bundle.
      view.loadHTMLString("<html><head><meta http-equiv='Content-Security-Policy' content=\"default-src 'none'; connect-src https: wss:; script-src 'unsafe-inline'\"></head><body></body></html>",baseURL:URL(string:"https://kingxcode.github.io/time_nest/"))
    case "serviceCall":
      guard let args = call.arguments as? [String:Any], let id = args["id"] as? String,
            let method = args["method"] as? String, let payload = args["args"] as? [String:Any],
            let web = web, let idJSON = try? json(id), let methodJSON = try? json(method), let argsJSON = try? json(payload) else {
        result(FlutterError(code:"unavailable",message:"Mac 数据服务尚未就绪。",details:nil)); return
      }
      web.evaluateJavaScript("void timeNestMac.call(\(idJSON),\(methodJSON),\(argsJSON))") { _,error in
        if let error = error { result(FlutterError(code:"javascript",message:error.localizedDescription,details:nil)) }
        else { result(nil) }
      }
    case "keepAwake": wantsAwake = call.arguments as? Bool == true; awakeFailed = false; publish(); result(nil)
    case "fullscreen": window?.toggleFullScreen(nil); result(nil)
    case "presentation":
      wantsAwake = true; publish()
      if window?.styleMask.contains(.fullScreen) != true { window?.toggleFullScreen(nil) }
      result(nil)
    case "playSound": NSSound.beep(); result(nil)
    case "openUrl": open(call.arguments); result(nil)
    default: result(FlutterMethodNotImplemented)
    }
  }

  func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
    guard message.frameInfo.isMainFrame, message.webView === web, let raw = message.body as? String, raw.utf8.count <= 16000000 else { return }
    // Passing JSON text preserves integer timestamps/sequence IDs in Dart.
    // Structured WK messages otherwise encode all JavaScript numbers as doubles.
    if raw.hasPrefix("{\"type\":\"openUrl\"") {
      if let data = raw.data(using: .utf8), let value = try? JSONSerialization.jsonObject(with: data) as? [String:Any] { open(value["url"]) }
      return
    }
    channel.invokeMethod("serviceEvent", arguments: raw)
  }
  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    let callback = ready; ready = nil
    webView.evaluateJavaScript("typeof timeNestMac === 'object' && typeof timeNestDashboard === 'object' && typeof timeNestNetwork === 'object'") { [weak self] value,error in
      if value as? Bool == true { callback?(nil); self?.publish() }
      else { callback?(FlutterError(code:"worker",message:"Mac 数据脚本加载失败。",details:error?.localizedDescription)) }
    }
  }
  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { fail(error) }
  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { fail(error) }
  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    fail(NSError(domain:"TimeNest",code:1,userInfo:[NSLocalizedDescriptionKey:"Mac 数据进程已中断。请重新打开应用。 "]))
    event(["type":"engineError"])
  }
  private func fail(_ error: Error) {
    ready?(FlutterError(code:"worker",message:error.localizedDescription,details:nil)); ready = nil
  }
  private func stopWorker() {
    ready?(FlutterError(code:"cancelled",message:"旧数据服务已关闭。",details:nil)); ready = nil
    web?.stopLoading(); web?.navigationDelegate = nil
    web?.configuration.userContentController.removeScriptMessageHandler(forName:"shike")
    web = nil
  }
  private func stop() {
    wantsAwake = false; updateAwake(); stopWorker()
  }
  deinit {
    if assertion != 0 { IOPMAssertionRelease(assertion) }
    for observer in observers { NotificationCenter.default.removeObserver(observer) }
    for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
  }
}
