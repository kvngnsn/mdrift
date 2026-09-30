import Cocoa
import UniformTypeIdentifiers

// One document owns one native window. AppKit groups these windows into tabs,
// keeping the editor, undo history, image directory and save state independent.
final class MdriftApp: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    var documents: [MdriftDocument] = []
    var pendingURLs: [URL] = []
    var launched = false
    #if NATIVE_TESTS
        var afterLaunch: (() -> Void)?
    #endif
    var untitledCount = 0
    let defaults: UserDefaults
    let dataDirectory: URL
    let legacyDataDirectory: URL?
    let legacyPreferences: [String: Any]?
    var recoveryDirectory: URL { dataDirectory.appendingPathComponent("Drafts", isDirectory: true) }
    var activeDocument: MdriftDocument? {
        documents.first { $0.window === NSApp.keyWindow }
            ?? documents.first { $0.window === NSApp.mainWindow }
            ?? documents.last
    }

    init(
        dataDirectory: URL? = nil, defaults: UserDefaults = .standard,
        legacyDataDirectory: URL? = nil, legacyPreferences: [String: Any]? = nil
    ) {
        let supportDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        self.defaults = defaults
        self.dataDirectory =
            dataDirectory
            ?? supportDirectory.appendingPathComponent("local.mdrift", isDirectory: true)
        // Tests inject a separate directory and never read the user's old app.
        self.legacyDataDirectory =
            legacyDataDirectory
            ?? (dataDirectory == nil
                ? supportDirectory.appendingPathComponent("local.kavin.markdown", isDirectory: true)
                : nil)
        self.legacyPreferences = legacyPreferences
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = true
        migrateLegacyState()
        buildMenu()
        launched = true
        restoreDrafts()
        let urls = pendingURLs
        pendingURLs.removeAll()
        if !urls.isEmpty { openURLs(urls) }
        if documents.isEmpty, let path = defaults.string(forKey: "lastFile"),
            FileManager.default.fileExists(atPath: path)
        {
            openURLs([URL(fileURLWithPath: path)], showError: false)
        }
        if documents.isEmpty { _ = createDocument(welcome: true) }
        NSApp.activate(ignoringOtherApps: true)
        #if NATIVE_TESTS
            Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { _ in self.afterLaunch?() }
        #endif
    }

    @discardableResult func createDocument(
        tabOf parent: MdriftDocument? = nil, draft: Draft? = nil, id: UUID = UUID(),
        welcome: Bool = false
    ) -> MdriftDocument {
        untitledCount += 1
        let name = untitledCount == 1 ? "untitled.md" : "untitled \(untitledCount).md"
        let document = MdriftDocument(app: self, id: id, name: name, welcome: welcome)
        document.focusOnReady = !welcome && draft == nil
        if let draft { document.restore(draft) }
        documents.append(document)
        document.show(tabOf: parent)
        return document
    }

    @objc func newTab() { createDocument(tabOf: activeDocument).call("command", "focus") }
    @objc func newWindow() { createDocument().call("command", "focus") }
    @objc func newWindowForTab(_ sender: Any?) { newTab() }
    @objc func saveDocument() { activeDocument?.saveDocument() }
    @objc func saveAsDocument() { activeDocument?.saveAsDocument() }
    @objc func closeTab() { activeDocument?.window.performClose(nil) }
    @objc func closeWindow() {
        guard let active = activeDocument else { return }
        let windows = active.window.tabGroup?.windows ?? [active.window!]
        let group = windows.compactMap { window in documents.first { $0.window === window } }
        guard group.allSatisfy({ $0.canClose() }) else { return }
        for document in group { document.window.close() }
    }

    @objc func openDocument() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            .plainText, UTType(filenameExtension: "md") ?? .plainText,
            UTType(filenameExtension: "markdown") ?? .plainText,
        ]
        panel.allowsOtherFileTypes = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.message = "Choose Markdown or plain-text documents to open in tabs."
        panel.directoryURL = activeDocument?.fileURL?.deletingLastPathComponent()
        if panel.runModal() == .OK { openURLs(panel.urls) }
    }

    func canonicalURL(_ url: URL) -> URL { url.standardizedFileURL.resolvingSymlinksInPath() }
    func document(for url: URL) -> MdriftDocument? {
        documents.first { $0.fileURL.map { canonicalURL($0) == canonicalURL(url) } ?? false }
    }

    func openURLs(_ urls: [URL], tabOf parent: MdriftDocument? = nil, showError: Bool = true) {
        guard launched else {
            pendingURLs.append(contentsOf: urls)
            return
        }
        var target = parent ?? activeDocument
        for url in urls {
            if let existing = document(for: url) {
                existing.window.makeKeyAndOrderFront(nil)
                target = existing
                continue
            }
            let document = MdriftDocument(app: self, name: url.lastPathComponent)
            guard document.readDocument(url, showError: showError) else { continue }
            documents.append(document)
            document.show(tabOf: target)
            target = document
        }
    }

    func restoreDrafts() {
        let files =
            (try? FileManager.default.contentsOfDirectory(
                at: recoveryDirectory, includingPropertiesForKeys: nil)) ?? []
        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        where file.pathExtension == "json" {
            guard let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent),
                let data = try? Data(contentsOf: file),
                let draft = try? JSONDecoder().decode(Draft.self, from: data)
            else { continue }
            _ = createDocument(tabOf: activeDocument, draft: draft, id: id)
        }
        // Migrate the original single-document recovery without discarding it
        // until the replacement has been written successfully.
        let legacy = dataDirectory.appendingPathComponent("Recovery.json")
        if let data = try? Data(contentsOf: legacy),
            let draft = try? JSONDecoder().decode(Draft.self, from: data)
        {
            let recovered = createDocument(tabOf: activeDocument, draft: draft)
            recovered.writeRecovery()
            if !recovered.dirty
                || FileManager.default.fileExists(atPath: recovered.recoveryURL.path)
            {
                try? FileManager.default.removeItem(at: legacy)
            }
        }
    }

    func documentClosed(_ document: MdriftDocument) {
        document.clearRecovery()
        document.webView.configuration.userContentController.removeScriptMessageHandler(
            forName: "app")
        documents.removeAll { $0 === document }
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        openURLs(filenames.map { URL(fileURLWithPath: $0) })
        sender.reply(toOpenOrPrint: .success)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool)
        -> Bool
    {
        if !flag {
            if let document = activeDocument {
                document.window.deminiaturize(nil)
                document.window.makeKeyAndOrderFront(nil)
            } else {
                newWindow()
            }
        }
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard documents.allSatisfy({ $0.canClose() }) else { return .terminateCancel }
        for document in documents { document.clearRecovery() }
        return .terminateNow
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if [#selector(saveDocument), #selector(saveAsDocument), #selector(webCommand(_:))].contains(
            item.action)
        {
            return activeDocument?.ready == true
        }
        if [#selector(closeTab), #selector(closeWindow)].contains(item.action) {
            return activeDocument != nil
        }
        return true
    }
}
