import AppKit

@MainActor
enum MainMenu {
    static func build() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(submenu("OpenWebull", items: [
            NSMenuItem(title: "About OpenWebull", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""),
            .separator(),
            NSMenuItem(title: "Settings…", action: #selector(AppDelegate.showSettings(_:)), keyEquivalent: ","),
            .separator(),
            NSMenuItem(title: "Hide OpenWebull", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"),
            item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            NSMenuItem(title: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: ""),
            .separator(),
            NSMenuItem(title: "Quit OpenWebull", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"),
        ]))
        menu.addItem(submenu("Edit", items: [
            NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"),
            item("Redo", Selector(("redo:")), "z", [.command, .shift]),
            .separator(),
            NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"),
            NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"),
            NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"),
            NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"),
            .separator(),
            NSMenuItem(title: "Find Symbol…", action: #selector(AppDelegate.findSymbol(_:)), keyEquivalent: "f"),
        ]))
        menu.addItem(submenu("View", items: Workspace.allCases.map { workspace in
            let entry = NSMenuItem(title: workspace.title, action: #selector(AppDelegate.showWorkspace(_:)), keyEquivalent: "\(workspace.rawValue + 1)")
            entry.tag = workspace.rawValue
            return entry
        } + [
            .separator(),
            item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]),
        ]))
        menu.addItem(submenu("Trade", items: [
            item("Cancel All Working Orders", #selector(AppDelegate.cancelAllOrders(_:)), "k", [.command, .shift]),
        ]))
        let window = submenu("Window", items: [
            NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"),
            NSMenuItem(title: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: ""),
        ])
        NSApp.windowsMenu = window.submenu
        menu.addItem(window)
        return menu
    }

    private static func submenu(_ title: String, items: [NSMenuItem]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: title)
        items.forEach(submenu.addItem)
        item.submenu = submenu
        return item
    }

    private static func item(_ title: String, _ action: Selector, _ key: String, _ modifiers: NSEvent.ModifierFlags) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        return item
    }
}
