import Cocoa

// Menu actions route to the currently selected document.
extension MdriftApp {
    func buildMenu() {
        let main = NSMenu()
        let appRoot = NSMenuItem()
        main.addItem(appRoot)
        let appMenu = NSMenu()
        appRoot.submenu = appMenu
        appMenu.addItem(withTitle: "About mdrift", action: #selector(showAbout), keyEquivalent: "")
            .target = self
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Hide mdrift", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(
            withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(
            withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Quit mdrift", action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")

        let file = addMenu("File", to: main)
        addItem("New Tab", action: #selector(newTab), key: "t", to: file)
        addItem("New Document", action: #selector(newTab), key: "n", to: file)
        addItem(
            "New Window", action: #selector(newWindow), key: "n", modifiers: [.command, .shift],
            to: file)
        addItem("Open…", action: #selector(openDocument), key: "o", to: file)
        file.addItem(.separator())
        addItem("Save", action: #selector(saveDocument), key: "s", to: file)
        addItem(
            "Save As…", action: #selector(saveAsDocument), key: "s", modifiers: [.command, .shift],
            to: file)
        file.addItem(.separator())
        addItem("Close Tab", action: #selector(closeTab), key: "w", to: file)
        addItem(
            "Close Window", action: #selector(closeWindow), key: "w",
            modifiers: [.command, .shift], to: file)

        let edit = addMenu("Edit", to: main)
        addWebItem("Undo", command: "undo", key: "z", to: edit)
        addWebItem("Redo", command: "redo", key: "z", modifiers: [.command, .shift], to: edit)
        edit.addItem(.separator())
        for (title, action, key, modifiers) in [
            ("Cut", #selector(NSText.cut(_:)), "x", NSEvent.ModifierFlags.command),
            ("Copy", #selector(NSText.copy(_:)), "c", .command),
            ("Paste", #selector(NSText.paste(_:)), "v", .command),
        ] {
            let item = edit.addItem(withTitle: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
        }
        addWebItem("Select All", command: "selectAll", key: "a", to: edit)

        let view = addMenu("View", to: main)
        addWebItem("Toggle Light / Dark", command: "theme", key: "", to: view)
        view.addItem(.separator())
        let fullscreen = view.addItem(
            withTitle: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)),
            keyEquivalent: "f")
        fullscreen.keyEquivalentModifierMask = [.command, .control]
        let windowMenu = addMenu("Window", to: main)
        windowMenu.addItem(
            withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m")
        windowMenu.addItem(
            withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        let next = windowMenu.addItem(
            withTitle: "Show Next Tab", action: #selector(NSWindow.selectNextTab(_:)),
            keyEquivalent: "\t")
        next.keyEquivalentModifierMask = [.control]
        let previous = windowMenu.addItem(
            withTitle: "Show Previous Tab", action: #selector(NSWindow.selectPreviousTab(_:)),
            keyEquivalent: "\t")
        previous.keyEquivalentModifierMask = [.control, .shift]
        windowMenu.addItem(
            withTitle: "Move Tab to New Window", action: #selector(NSWindow.moveTabToNewWindow(_:)),
            keyEquivalent: "")
        windowMenu.addItem(
            withTitle: "Merge All Windows", action: #selector(NSWindow.mergeAllWindows(_:)),
            keyEquivalent: "")
        windowMenu.addItem(
            withTitle: "Show Tab Bar", action: #selector(NSWindow.toggleTabBar(_:)),
            keyEquivalent: "")
        NSApp.windowsMenu = windowMenu
        NSApp.mainMenu = main
    }

    func addMenu(_ title: String, to menu: NSMenu) -> NSMenu {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let child = NSMenu(title: title)
        item.submenu = child
        menu.addItem(item)
        return child
    }

    func addItem(
        _ title: String, action: Selector, key: String, modifiers: NSEvent.ModifierFlags = .command,
        to menu: NSMenu
    ) {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        item.target = self
        item.keyEquivalentModifierMask = modifiers
    }

    func addWebItem(
        _ title: String, command: String, key: String, modifiers: NSEvent.ModifierFlags = .command,
        to menu: NSMenu
    ) {
        let item = menu.addItem(
            withTitle: title, action: #selector(webCommand(_:)), keyEquivalent: key)
        item.target = self
        item.representedObject = command
        item.keyEquivalentModifierMask = modifiers
    }

    @objc func webCommand(_ sender: NSMenuItem) {
        if let command = sender.representedObject as? String {
            activeDocument?.call("command", command)
        }
    }

    @objc func showAbout() {
        let version =
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "mdrift", .applicationVersion: version,
            .credits: NSAttributedString(
                string: "Plain text, live.\n\nAll documents stay on this Mac."),
        ])
    }

}
