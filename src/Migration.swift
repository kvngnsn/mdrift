import Cocoa

// Import the earlier app's drafts once. Copying leaves the old installation's
// recovery files intact, including when migration is interrupted.
extension MdriftApp {
    func migrateLegacyState() {
        guard !defaults.bool(forKey: "migration.markdown.complete"),
            let legacyDataDirectory
        else { return }

        let fileManager = FileManager.default
        do {
            if fileManager.fileExists(atPath: legacyDataDirectory.path) {
                try fileManager.createDirectory(
                    at: dataDirectory,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700])
                let oldSingleDraft = legacyDataDirectory.appendingPathComponent("Recovery.json")
                try copyLegacyDraft(
                    oldSingleDraft, to: dataDirectory.appendingPathComponent("Recovery.json"))

                let oldDraftsDirectory = legacyDataDirectory.appendingPathComponent(
                    "Drafts", isDirectory: true)
                if fileManager.fileExists(atPath: oldDraftsDirectory.path) {
                    try fileManager.createDirectory(
                        at: recoveryDirectory,
                        withIntermediateDirectories: true,
                        attributes: [.posixPermissions: 0o700])
                    let files = try fileManager.contentsOfDirectory(
                        at: oldDraftsDirectory,
                        includingPropertiesForKeys: nil)
                    for file in files where file.pathExtension == "json" {
                        try copyLegacyDraft(
                            file,
                            to: recoveryDirectory.appendingPathComponent(file.lastPathComponent))
                    }
                }
            }

            let preferences =
                legacyPreferences ?? defaults.persistentDomain(forName: "local.kavin.markdown")
                ?? [:]
            for key in ["lastFile", "ui.theme"] where defaults.object(forKey: key) == nil {
                if let value = preferences[key] { defaults.set(value, forKey: key) }
            }
            if defaults.object(forKey: "NSWindow Frame MdriftWindow") == nil,
                let frame = preferences["NSWindow Frame MarkdownWindow"]
            {
                defaults.set(frame, forKey: "NSWindow Frame MdriftWindow")
            }
            defaults.set(true, forKey: "migration.markdown.complete")
        } catch {
            let alert = NSAlert()
            alert.messageText = "Some older drafts could not be imported."
            alert.informativeText =
                "The originals are still in \(legacyDataDirectory.path).\n\n\(error.localizedDescription)"
            alert.runModal()
        }
    }

    private func copyLegacyDraft(_ source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: source.path),
            !fileManager.fileExists(atPath: destination.path)
        else { return }
        try fileManager.copyItem(at: source, to: destination)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
    }
}
