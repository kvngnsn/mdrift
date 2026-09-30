import Cocoa
import WebKit

// Runs the real AppKit/WKWebView implementation with temporary files and a
// separate app identity. It never opens or alters the installed user's drafts.
enum NativeVerification {
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }

    static func wait(_ message: String, until condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(20)
        while !condition(), Date() < deadline {
            while let event = NSApp.nextEvent(
                matching: .any, until: .distantPast, inMode: .default, dequeue: true)
            { NSApp.sendEvent(event) }
            NSApp.updateWindows()
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        check(condition(), message)
    }

    @discardableResult static func js(_ document: MdriftDocument, _ script: String) -> Any? {
        var done = false
        var value: Any?
        var failure: Error?
        document.webView.evaluateJavaScript(script) { result, error in
            value = result
            failure = error
            done = true
        }
        wait("JavaScript response", until: { done })
        check(failure == nil, "JavaScript: \(script)\n\(failure?.localizedDescription ?? "")")
        return value
    }

    static func edit(_ document: MdriftDocument, _ text: String) {
        document.window.makeKeyAndOrderFront(nil)
        let encoded = String(data: try! JSONEncoder().encode(text), encoding: .utf8)!
        js(
            document,
            "window.mdrift.command('selectAll'); document.execCommand('insertText', false, \(encoded))"
        )
        wait("native change notification", until: { document.content == text })
    }

    static func respond(_ response: NSApplication.ModalResponse) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSApp.stopModal(withCode: response)
        }
    }

    static func run() {
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["MDRIFT_QA_DATA"]!)
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let defaults = UserDefaults(suiteName: "local.mdrift.qa.fixtures")!
        defaults.removePersistentDomain(forName: "local.mdrift.qa.fixtures")
        let controller = MdriftApp(
            dataDirectory: root.appendingPathComponent("Recovery"), defaults: defaults)
        let app = NSApplication.shared
        app.delegate = controller
        app.setActivationPolicy(.regular)
        controller.afterLaunch = {
            if ProcessInfo.processInfo.environment["MDRIFT_QA_MANUAL"] == "1" { return }
            verify(controller, root: root)
            if ProcessInfo.processInfo.environment["MDRIFT_QA_KEEP_OPEN"] != "1" {
                for document in controller.documents { document.window.close() }
                defaults.removePersistentDomain(forName: "local.mdrift.qa.fixtures")
                exit(0)
            }
        }
        app.run()
    }

    static func verify(_ app: MdriftApp, root: URL) {
        verifyMigration(root: root)
        wait("initial window", until: { app.documents.first?.ready == true })
        check(app.documents.first!.window.title.hasSuffix(" — mdrift"), "native window branding")
        check(
            NSApp.mainMenu?.items.first?.submenu?.item(withTitle: "About mdrift") != nil,
            "menu branding")
        app.documents.first!.window.close()
        verifyFileHandling(app, root: root)
        let firstURL = root.appendingPathComponent("First.md")
        let secondURL = root.appendingPathComponent("Second.md")
        let firstBytes = Data([0xef, 0xbb, 0xbf]) + Data("# First\r\n\r\nOriginal one.\r\n".utf8)
        try! firstBytes.write(to: firstURL)
        try! "# Second\n\nOriginal two.\n".write(to: secondURL, atomically: true, encoding: .utf8)
        app.openURLs([firstURL, secondURL])
        wait(
            "both file editors ready",
            until: { app.documents.count == 2 && app.documents.allSatisfy(\.ready) })
        let first = app.document(for: firstURL)!
        let second = app.document(for: secondURL)!
        check(first.window.tabGroup === second.window.tabGroup, "multi-open uses one tab group")
        check(first.window.tabGroup?.windows.count == 2, "two native tabs")
        check(
            js(first, "window.mdrift.getText()") as? String == "# First\n\nOriginal one.\n",
            "first web document")
        check(
            js(second, "window.mdrift.getText()") as? String == "# Second\n\nOriginal two.\n",
            "second web document")
        app.openURLs([firstURL])
        check(
            app.documents.count == 2 && app.activeDocument === first,
            "opening existing file focuses its tab")
        edit(first, "# First\n\nEdited one.\n")
        edit(second, "# Second\n\nEdited two.\n")
        check(first.dirty && second.dirty, "both documents dirty independently")
        js(first, "window.mdrift.command('undo')")
        wait("first undo", until: { !first.dirty })
        check(second.content == "# Second\n\nEdited two.\n", "undo does not touch other tab")
        js(first, "window.mdrift.command('redo')")
        wait("first redo", until: { first.dirty })
        first.writeRecovery()
        second.writeRecovery()
        check(first.recoveryURL != second.recoveryURL, "unique recovery paths")
        check(
            FileManager.default.fileExists(atPath: first.recoveryURL.path)
                && FileManager.default.fileExists(atPath: second.recoveryURL.path),
            "both drafts on disk")
        first.window.makeKeyAndOrderFront(nil)
        app.saveDocument()
        check(!first.dirty && second.dirty, "Save routes to selected tab")
        check(
            (try! Data(contentsOf: firstURL)) == Data([0xef, 0xbb, 0xbf])
                + Data("# First\r\n\r\nEdited one.\r\n".utf8), "BOM and CRLF preserved")
        check(
            (try! String(contentsOf: secondURL, encoding: .utf8)) == "# Second\n\nOriginal two.\n",
            "other file stays unchanged")
        check(
            !FileManager.default.fileExists(atPath: first.recoveryURL.path)
                && FileManager.default.fileExists(atPath: second.recoveryURL.path),
            "saving one preserves other recovery")
        second.window.makeKeyAndOrderFront(nil)
        respond(.alertSecondButtonReturn)
        app.closeTab()
        check(app.documents.contains { $0 === second } && second.dirty, "Cancel keeps dirty tab")
        second.window.moveTabToNewWindow(nil)
        check(first.window.tabGroup !== second.window.tabGroup, "detach tab to separate window")
        app.newWindow()
        let third = app.documents.last!
        wait("new window ready", until: { third.ready })
        check(third.window.tabGroup !== second.window.tabGroup, "New Window stays separate")
        check(js(third, "window.mdrift.getText()") as? String == "", "new window is empty")
        check(
            NSApp.sendAction(
                #selector(NSResponder.newWindowForTab(_:)), to: nil, from: third.window),
            "native plus button action resolves")
        let fourth = app.documents.last!
        wait("new tab ready", until: { fourth.ready })
        check(
            fourth !== third && fourth.window.tabGroup === third.window.tabGroup,
            "native plus adds tab in current window")
        third.window.makeKeyAndOrderFront(nil)
        app.closeWindow()
        check(app.documents.count == 2, "Close Window closes its tabs only")
        first.window.makeKeyAndOrderFront(nil)
        first.window.mergeAllWindows(nil)
        check(first.window.tabGroup === second.window.tabGroup, "merge separate windows into tabs")
        let recoveryData = try! Data(contentsOf: second.recoveryURL)
        let recovered = try! JSONDecoder().decode(Draft.self, from: recoveryData)
        check(
            recovered.content == second.content && recovered.savedContent == second.savedContent,
            "recovery retains edited and saved states")
        respond(.alertSecondButtonReturn)
        check(
            app.applicationShouldTerminate(NSApp) == .terminateCancel,
            "Cancel stops quitting all windows")
        check(
            FileManager.default.fileExists(atPath: second.recoveryURL.path),
            "cancelled quit preserves recovery")
        respond(.alertThirdButtonReturn)
        app.closeWindow()
        check(app.documents.isEmpty, "close group after Don't Save")
        check(
            !FileManager.default.fileExists(atPath: second.recoveryURL.path),
            "discard clears only closed draft")
        try! FileManager.default.createDirectory(
            at: app.dataDirectory, withIntermediateDirectories: true)
        try! recoveryData.write(to: app.dataDirectory.appendingPathComponent("Recovery.json"))
        app.restoreDrafts()
        wait("legacy draft ready", until: { app.documents.count == 1 && app.documents[0].ready })
        let restored = app.documents[0]
        check(
            restored.content == recovered.content && restored.dirty,
            "legacy recovery migrated intact")
        check(
            !FileManager.default.fileExists(
                atPath: app.dataDirectory.appendingPathComponent("Recovery.json").path),
            "legacy removed after successful migration")
        // Simulate reloading a terminated web process: it must retain native state.
        restored.webViewWebContentProcessDidTerminate(restored.webView)
        wait("editor reload", until: { restored.ready })
        check(
            js(restored, "window.mdrift.getText()") as? String == recovered.content,
            "web process restart retains draft")
        edit(restored, "# Second\n\nEdited two.\n\nStill here.")
        restored.writeRecovery()
        let other = app.createDocument(tabOf: restored)
        wait("additional recovery tab", until: { other.ready })
        edit(other, "# Unsaved\n\nAnother independent draft.")
        other.writeRecovery()
        let recoveries = [restored.recoveryURL, other.recoveryURL].map { try! Data(contentsOf: $0) }
        for document in app.documents { document.window.close() }
        for data in recoveries {
            try! data.write(
                to: app.recoveryDirectory.appendingPathComponent(UUID().uuidString + ".json"))
        }
        app.restoreDrafts()
        wait(
            "all drafts restored",
            until: { app.documents.count == 2 && app.documents.allSatisfy(\.ready) })
        check(
            Set(app.documents.map(\.content))
                == Set([
                    "# Second\n\nEdited two.\n\nStill here.",
                    "# Unsaved\n\nAnother independent draft.",
                ]), "multiple recovered contents")
        check(
            app.documents[0].window.tabGroup === app.documents[1].window.tabGroup,
            "recovered drafts open together")
        js(app.documents[0], "window.mdrift.command('theme')")
        wait(
            "shared theme",
            until: {
                app.documents[0].window.appearance?.name == app.documents[1].window.appearance?.name
            })
        print(
            "PASS: native branding, tabs/windows, multi-open, duplicate focus, independent edit/undo/save, BOM/CRLF, per-tab recovery, close/quit cancellation, detach/merge, native plus, migration, multiple recovered drafts, web-process reload, file guards, local images, relative links."
        )
        fflush(stdout)
        if ProcessInfo.processInfo.environment["MDRIFT_QA_KEEP_OPEN"] == "1" {
            _ = app.createDocument()
            app.documents.first!.window.makeKeyAndOrderFront(nil)
        }
    }

    static func verifyMigration(root: URL) {
        let suite = "local.mdrift.qa.migration"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let oldDirectory = root.appendingPathComponent("Old App")
        let newDirectory = root.appendingPathComponent("New App")
        let oldDrafts = oldDirectory.appendingPathComponent("Drafts")
        try! FileManager.default.createDirectory(at: oldDrafts, withIntermediateDirectories: true)
        let draft = Draft(
            content: "Recovered notes", savedContent: "", path: nil,
            name: "Notes.md", lineEnding: "\n", hasBOM: false, originalData: nil)
        let bytes = try! JSONEncoder().encode(draft)
        let names = [UUID().uuidString + ".json", UUID().uuidString + ".json"]
        for name in names { try! bytes.write(to: oldDrafts.appendingPathComponent(name)) }
        try! bytes.write(to: oldDirectory.appendingPathComponent("Recovery.json"))
        defaults.set("dark", forKey: "ui.theme")
        let controller = MdriftApp(
            dataDirectory: newDirectory, defaults: defaults, legacyDataDirectory: oldDirectory,
            legacyPreferences: [
                "ui.theme": "light", "lastFile": "/example/notes.md",
                "NSWindow Frame MarkdownWindow": "100 100 800 600",
            ])
        controller.migrateLegacyState()
        check(
            defaults.string(forKey: "ui.theme") == "dark", "migration preserves current preferences"
        )
        check(
            defaults.string(forKey: "lastFile") == "/example/notes.md",
            "migration imports old preferences")
        check(
            defaults.string(forKey: "NSWindow Frame MdriftWindow") == "100 100 800 600",
            "window frame migrated")
        for name in names {
            let destination = controller.recoveryDirectory.appendingPathComponent(name)
            check(
                (try! Data(contentsOf: destination)) == bytes, "draft imported without modification"
            )
            check(
                (try! Data(contentsOf: oldDrafts.appendingPathComponent(name))) == bytes,
                "original draft retained")
        }
        check(
            (try! Data(contentsOf: newDirectory.appendingPathComponent("Recovery.json"))) == bytes,
            "single legacy draft copied")
        check(
            (try! Data(contentsOf: oldDirectory.appendingPathComponent("Recovery.json"))) == bytes,
            "single original retained")
        let discarded = controller.recoveryDirectory.appendingPathComponent(names[0])
        try! FileManager.default.removeItem(at: discarded)
        controller.migrateLegacyState()
        check(
            !FileManager.default.fileExists(atPath: discarded.path),
            "migration does not resurrect discarded drafts")
    }

    static func verifyFileHandling(_ app: MdriftApp, root: URL) {
        let folder = root.appendingPathComponent("Files", isDirectory: true)
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let invalid = folder.appendingPathComponent("Invalid.md")
        try! Data([0xff, 0x00]).write(to: invalid)
        app.openURLs([invalid], showError: false)
        check(app.documents.isEmpty, "invalid text does not create a document")
        let large = folder.appendingPathComponent("Large.md")
        try! Data(repeating: 65, count: 10_000_001).write(to: large)
        app.openURLs([large], showError: false)
        check(app.documents.isEmpty, "oversized files rejected")

        let file = folder.appendingPathComponent("Conflicts.md")
        try! "Original".write(to: file, atomically: true, encoding: .utf8)
        app.openURLs([file])
        let document = app.document(for: file)!
        wait("conflict editor ready", until: { document.ready })
        edit(document, "Edited")
        try! "External edit".write(to: file, atomically: true, encoding: .utf8)
        respond(.alertSecondButtonReturn)
        check(!document.saveCurrent(), "external-change cancellation")
        check(
            (try! String(contentsOf: file, encoding: .utf8)) == "External edit",
            "external edit preserved after cancel")
        check(document.dirty, "cancel leaves local edit unsaved")
        respond(.alertThirdButtonReturn)
        check(document.saveCurrent(), "explicit replace succeeds")
        check(
            (try! String(contentsOf: file, encoding: .utf8)) == "Edited",
            "replace writes local edit")

        let image = folder.appendingPathComponent("pixel.png")
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.setColor(NSColor(deviceRed: 1, green: 1, blue: 1, alpha: 1), atX: 0, y: 0)
        try! bitmap.representation(using: .png, properties: [:])!.write(to: image)
        let outside = root.appendingPathComponent("outside.png")
        try! FileManager.default.copyItem(at: image, to: outside)
        try! FileManager.default.createSymbolicLink(
            at: folder.appendingPathComponent("escape.png"), withDestinationURL: outside)
        edit(document, "# Images\n\n![Local](pixel.png)\n\n![Blocked](escape.png)\n\nEnd.")
        js(document, "document.activeElement.blur()")
        wait(
            "local image loads",
            until: {
                js(document, "document.querySelector('img[alt=Local]')?.naturalWidth") as? Int == 1
            })
        wait(
            "escaped image fails",
            until: {
                js(document, "document.querySelector('img[alt=Blocked]')?.complete") as? Bool
                    == true
            })
        check(
            js(document, "document.querySelector('img[alt=Blocked]').naturalWidth") as? Int == 0,
            "images cannot escape document directory")

        let linkedFile = folder.appendingPathComponent("Linked.md")
        try! "# Linked".write(to: linkedFile, atomically: true, encoding: .utf8)
        js(
            document,
            "void window.webkit.messageHandlers.app.postMessage({action:'openRelative', path:'Linked.md'})"
        )
        wait(
            "relative link opens document", until: { app.document(for: linkedFile)?.ready == true })
        check(
            app.document(for: linkedFile)!.window.tabGroup === document.window.tabGroup,
            "relative link opens in current tab group")
        for document in app.documents { document.window.close() }
    }
}
