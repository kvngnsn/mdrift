import Cocoa
import WebKit

struct Draft: Codable {
    var content: String
    var savedContent: String
    var path: String?
    var name: String
    var lineEnding: String
    var hasBOM: Bool
    var originalData: Data?
}

final class MdriftDocument: NSObject, NSWindowDelegate, WKScriptMessageHandler, WKNavigationDelegate
{
    unowned let app: MdriftApp
    let id: UUID
    var window: NSWindow!
    var webView: WKWebView!
    let images = LocalImages()
    var defaults: UserDefaults { app.defaults }
    var ready = false
    var content = ""
    var savedContent = ""
    var fileURL: URL?
    var displayName: String
    var lineEnding = "\n"
    var hasBOM = false
    var originalData: Data?
    var recoveryWork: DispatchWorkItem?
    var showWelcome: Bool
    var focusOnReady = false
    var recovered = false
    var dirty: Bool { content != savedContent }
    var recoveryURL: URL { app.recoveryDirectory.appendingPathComponent(id.uuidString + ".json") }

    init(app: MdriftApp, id: UUID = UUID(), name: String, welcome: Bool = false) {
        self.app = app
        self.id = id
        displayName = name
        showWelcome = welcome
        super.init()
    }

    func restore(_ draft: Draft) {
        content = draft.content
        savedContent = draft.savedContent
        displayName = draft.name
        fileURL = draft.path.map { URL(fileURLWithPath: $0) }
        originalData = draft.originalData
        lineEnding = draft.lineEnding
        hasBOM = draft.hasBOM
        recovered = true
    }

    func show(tabOf parent: MdriftDocument?) {
        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "app")
        config.setURLSchemeHandler(images, forURLScheme: "mdrift-asset")
        config.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = false
        webView.setValue(false, forKey: "drawsBackground")
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered,
            defer: false)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = false
        window.minSize = NSSize(width: 600, height: 440)
        window.contentView = webView
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.tabbingIdentifier = "MdriftDocuments"
        // Suppress automatic grouping only while showing an explicit new
        // window. App-wide suppression also disables native Merge/Show Tabs.
        window.tabbingMode = parent == nil ? .disallowed : .automatic
        window.setFrameAutosaveName("MdriftWindow")
        if defaults.string(forKey: "NSWindow Frame MdriftWindow") == nil { window.center() }
        updateTitle()
        if let parent {
            parent.window.addTabbedWindow(window, ordered: .above)
        } else if let previous = app.documents.dropLast().last {
            window.cascadeTopLeft(
                from: NSPoint(
                    x: previous.window.frame.minX + 24, y: previous.window.frame.maxY - 24))
        }
        window.makeKeyAndOrderFront(nil)
        window.tabbingMode = .automatic
        // Keep the native + button available even in a single-tab window.
        if window.tabGroup?.isTabBarVisible != true { window.toggleTabBar(nil) }
        let html = Bundle.main.resourceURL!.appendingPathComponent("web/index.html")
        webView.loadFileURL(html, allowingReadAccessTo: html.deletingLastPathComponent())
    }

    func call(_ method: String, _ value: Any) {
        guard ready, JSONSerialization.isValidJSONObject([value]),
            let data = try? JSONSerialization.data(
                withJSONObject: [value], options: [.fragmentsAllowed]),
            let json = String(data: data, encoding: .utf8)
        else { return }
        webView.evaluateJavaScript("window.mdrift.\(method)(...\(json))", completionHandler: nil)
    }

    func preferences() -> [String: Any] {
        guard let theme = defaults.object(forKey: "ui.theme") else { return [:] }
        return ["theme": theme]
    }

    func pushDocument(recovered: Bool = false) {
        images.directory = fileURL?.deletingLastPathComponent()
        call(
            "loadDocument",
            [
                "content": content, "savedContent": savedContent, "name": displayName,
                "folder": fileURL?.deletingLastPathComponent().lastPathComponent
                    ?? "Unsaved document", "path": fileURL?.path ?? "", "recovered": recovered,
                "preferences": preferences(),
            ])
        updateTitle()
    }

    func updateTitle() {
        window.title = "\(displayName) — mdrift"
        window.isDocumentEdited = dirty
        window.representedURL = fileURL
        window.tab.title = displayName
        window.tab.toolTip = fileURL?.path ?? displayName
    }

    func userContentController(
        _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
    ) {
        guard message.frameInfo.isMainFrame, let body = message.body as? [String: Any],
            let action = body["action"] as? String
        else { return }
        switch action {
        case "ready":
            ready = true
            if showWelcome {
                content = body["welcome"] as? String ?? ""
                savedContent = content
                displayName = "Welcome.md"
                showWelcome = false
            }
            pushDocument(recovered: recovered)
            recovered = false
            if focusOnReady {
                call("command", "focus")
                focusOnReady = false
            }
        case "change":
            guard let text = body["content"] as? String else { return }
            content = text
            updateTitle()
            scheduleRecovery()
        case "open": app.openDocument()
        case "save": saveDocument()
        case "preference":
            if let key = body["key"] as? String, key == "theme", let value = body["value"] {
                defaults.set(value, forKey: "ui.\(key)")
                for document in app.documents where document !== self {
                    document.call("setTheme", value)
                }
            }
        case "appearance":
            let dark = body["theme"] as? String == "dark"
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            window.backgroundColor =
                dark
                ? NSColor(calibratedWhite: 8.0 / 255, alpha: 1)
                : NSColor(
                    calibratedRed: 247.0 / 255, green: 247.0 / 255, blue: 245.0 / 255, alpha: 1)
        case "openLink":
            if let string = body["url"] as? String, let url = URL(string: string),
                ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "")
            {
                NSWorkspace.shared.open(url)
            }
        case "openRelative":
            if let path = body["path"] as? String, let root = fileURL?.deletingLastPathComponent(),
                let url = URL(string: path, relativeTo: root)?.absoluteURL, url.isFileURL,
                ["md", "markdown", "mdown", "mkd", "txt"].contains(url.pathExtension.lowercased())
            {
                app.openURLs([url], tabOf: self)
            }
        default: break
        }
    }

    func scheduleRecovery() {
        recoveryWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.writeRecovery() }
        recoveryWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    func writeRecovery() {
        recoveryWork?.cancel()
        recoveryWork = nil
        guard dirty else {
            clearRecovery()
            return
        }
        do {
            try FileManager.default.createDirectory(
                at: app.recoveryDirectory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            let draft = Draft(
                content: content, savedContent: savedContent, path: fileURL?.path,
                name: displayName, lineEnding: lineEnding, hasBOM: hasBOM,
                originalData: originalData)
            try JSONEncoder().encode(draft).write(to: recoveryURL, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600], ofItemAtPath: recoveryURL.path)
            call("recoveryStatus", true)
        } catch { call("recoveryStatus", false) }
    }

    func clearRecovery() {
        recoveryWork?.cancel()
        recoveryWork = nil
        try? FileManager.default.removeItem(at: recoveryURL)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { canClose() }
    func windowWillClose(_ notification: Notification) { app.documentClosed(self) }
    func webView(
        _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        let index = Bundle.main.resourceURL!.appendingPathComponent("web/index.html")
        let request = navigationAction.request.url
        let allowed =
            request?.isFileURL == true && request?.standardizedFileURL == index.standardizedFileURL
        decisionHandler(allowed ? .allow : .cancel)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        writeRecovery()
        ready = false
        webView.reload()
    }
}
