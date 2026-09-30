import Cocoa
import UniformTypeIdentifiers

// Native file dialogs, UTF-8 decoding, and explicit saves.
extension MdriftDocument {
    func canClose() -> Bool {
        guard dirty else { return true }
        window.makeKeyAndOrderFront(nil)
        let alert = NSAlert()
        alert.messageText = "Save changes to “\(displayName)”?"
        alert.informativeText = "Your changes will be lost if you don’t save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Don’t Save")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return saveCurrent()
        case .alertThirdButtonReturn: return true
        default: return false
        }
    }

    @discardableResult func readDocument(_ url: URL, showError: Bool = true) -> Bool {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard (attributes[.size] as? NSNumber)?.intValue ?? 0 <= 10_000_000 else {
                throw NSError(
                    domain: "mdrift", code: 1,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "This document is larger than 10 MB. Open a smaller text file."
                    ])
            }
            let data = try Data(contentsOf: url)
            let bom = data.starts(with: [0xEF, 0xBB, 0xBF])
            let payload = bom ? Data(data.dropFirst(3)) : data
            guard let text = String(data: payload, encoding: .utf8), !text.contains("\0") else {
                throw NSError(
                    domain: "mdrift", code: 2,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "This file isn’t UTF-8 text. Export it as a UTF-8 Markdown or text file, then open it again."
                    ])
            }
            lineEnding = text.contains("\r\n") ? "\r\n" : text.contains("\r") ? "\r" : "\n"
            content = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(
                of: "\r", with: "\n")
            savedContent = content
            hasBOM = bom
            originalData = data
            fileURL = url
            displayName = url.lastPathComponent
            remember(url)
            return true
        } catch {
            if showError { showErrorAlert("Couldn’t open this file", error.localizedDescription) }
            return false
        }
    }

    @objc func saveDocument() {
        guard ready else { return }
        _ = saveCurrent()
    }

    @objc func saveAsDocument() {
        guard ready else { return }
        _ = saveCurrent(saveAs: true)
    }

    func saveCurrent(saveAs: Bool = false) -> Bool {
        var destination = saveAs ? nil : fileURL
        if let url = destination, let baseline = originalData,
            (try? Data(contentsOf: url)) != baseline
        {
            let alert = NSAlert()
            alert.messageText = "This file changed outside mdrift."
            alert.informativeText =
                "Save a copy to keep both versions, or replace the file on disk with your current text."
            alert.addButton(withTitle: "Save a Copy…")
            alert.addButton(withTitle: "Cancel")
            alert.addButton(withTitle: "Replace File")
            switch alert.runModal() {
            case .alertFirstButtonReturn: destination = nil
            case .alertThirdButtonReturn: break
            default: return false
            }
        }
        if destination == nil {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText, .plainText]
            panel.allowsOtherFileTypes = true
            panel.canCreateDirectories = true
            panel.nameFieldStringValue = displayName
            if let folder = fileURL?.deletingLastPathComponent() { panel.directoryURL = folder }
            guard panel.runModal() == .OK, let url = panel.url else { return false }
            destination = url
        }
        guard let url = destination else { return false }
        if let existing = app.document(for: url), existing !== self {
            showErrorAlert(
                "This file is already open in another tab",
                "Choose a different name, or close the other tab before saving over it.")
            return false
        }
        do {
            var data = Data(
                (lineEnding == "\n"
                    ? content : content.replacingOccurrences(of: "\n", with: lineEnding)).utf8)
            if hasBOM { data.insert(contentsOf: [0xEF, 0xBB, 0xBF], at: 0) }
            try data.write(to: url, options: .atomic)
            fileURL = url
            displayName = url.lastPathComponent
            savedContent = content
            originalData = data
            images.directory = url.deletingLastPathComponent()
            clearRecovery()
            remember(url)
            updateTitle()
            call(
                "didSave",
                [
                    "content": content, "name": displayName,
                    "folder": url.deletingLastPathComponent().lastPathComponent, "path": url.path,
                ])
            return true
        } catch {
            showErrorAlert("Couldn’t save this file", error.localizedDescription)
            writeRecovery()
            return false
        }
    }

    func remember(_ url: URL) {
        defaults.set(url.path, forKey: "lastFile")
    }

    func showErrorAlert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}
