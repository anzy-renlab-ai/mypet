import AppKit
import SwiftUI
import OSLog

private let log = Logger(subsystem: "ai.mypet", category: "Menubar")

/// Owns the NSStatusItem (menubar icon + dropdown menu).
/// Routes "Feed now" to FeedCoordinator.
@MainActor
final class MenubarController: NSObject {

    private var statusItem: NSStatusItem?
    private let coordinator: FeedCoordinator
    private let feedLog: FeedLog
    private let onShowOnboarding: () -> Void
    private let onQuit: () -> Void

    init(
        coordinator: FeedCoordinator,
        feedLog: FeedLog,
        onShowOnboarding: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.coordinator = coordinator
        self.feedLog = feedLog
        self.onShowOnboarding = onShowOnboarding
        self.onQuit = onQuit
        super.init()
        install()
    }

    private func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = Self.twoPawsTemplateImage()
            button.toolTip = "mypet"
        }
        item.menu = buildMenu()
        statusItem = item
        log.info("menubar installed")
    }

    /// Rasterize the 🐾 emoji into a template image. macOS uses the alpha
    /// channel as the silhouette mask, so we keep the emoji's cute two-paw
    /// shape AND get proper menubar tinting (white in dark mode, black in
    /// light mode — no more sore-thumb black-on-blue).
    private static func twoPawsTemplateImage() -> NSImage {
        let fontSize: CGFloat = 14
        let attr = NSAttributedString(
            string: "🐾",
            attributes: [.font: NSFont.systemFont(ofSize: fontSize)]
        )
        let glyphSize = attr.size()
        let pad: CGFloat = 2
        let size = NSSize(width: ceil(glyphSize.width) + pad * 2,
                          height: ceil(glyphSize.height))

        let img = NSImage(size: size)
        img.lockFocus()
        attr.draw(at: NSPoint(x: pad, y: 0))
        img.unlockFocus()
        img.isTemplate = true
        return img
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let feedItem = NSMenuItem(
            title: "Feed now",
            action: #selector(feedNow),
            keyEquivalent: ""
        )
        feedItem.target = self
        menu.addItem(feedItem)

        // Recent tips submenu — populated lazily on open
        let recentParent = NSMenuItem(title: "Recent tips", action: nil, keyEquivalent: "")
        let recentSubmenu = NSMenu(title: "Recent tips")
        let placeholder = NSMenuItem(title: "(载入中…)", action: nil, keyEquivalent: "")
        placeholder.isEnabled = false
        recentSubmenu.addItem(placeholder)
        recentSubmenu.delegate = self
        recentParent.submenu = recentSubmenu
        menu.addItem(recentParent)

        menu.addItem(.separator())

        let loginToggle = NSMenuItem(
            title: LoginItem.isEnabled() ? "✓ 开机自启" : "开机自启",
            action: #selector(toggleLogin),
            keyEquivalent: ""
        )
        loginToggle.target = self
        menu.addItem(loginToggle)

        let aboutItem = NSMenuItem(
            title: "重新设置…",
            action: #selector(showOnboarding),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit mypet",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        // Refresh menu state when opened (login item could change externally)
        menu.delegate = self
        return menu
    }

    @objc private func feedNow() {
        Task { @MainActor in
            await coordinator.feed()
        }
    }

    @objc private func copyTipFromMenu(_ sender: NSMenuItem) {
        guard let tip = sender.representedObject as? String else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(tip, forType: .string)
    }

    /// Refill the Recent tips submenu from FeedLog. Capped to 10 entries.
    private func refreshRecentTipsSubmenu(_ submenu: NSMenu) {
        Task { @MainActor in
            let entries = (try? await feedLog.recentTips(limit: 10)) ?? []
            submenu.removeAllItems()
            if entries.isEmpty {
                let empty = NSMenuItem(title: "(还没喂过)", action: nil, keyEquivalent: "")
                empty.isEnabled = false
                submenu.addItem(empty)
                return
            }
            let fmt = DateFormatter()
            fmt.dateFormat = "MM-dd HH:mm"
            for entry in entries {
                let shortTip = entry.tip.count > 50
                    ? String(entry.tip.prefix(49)) + "…"
                    : entry.tip
                let title = "\(fmt.string(from: entry.ts))  \(shortTip)"
                let item = NSMenuItem(title: title, action: #selector(copyTipFromMenu(_:)), keyEquivalent: "")
                item.target = self
                item.toolTip = entry.tip
                item.representedObject = entry.tip
                submenu.addItem(item)
            }
            submenu.addItem(.separator())
            let hint = NSMenuItem(title: "点击复制 · 共 \(entries.count) 条", action: nil, keyEquivalent: "")
            hint.isEnabled = false
            submenu.addItem(hint)
        }
    }

    @objc private func toggleLogin() {
        if LoginItem.isEnabled() {
            LoginItem.disable()
        } else {
            LoginItem.enable()
        }
        // Rebuild menu to reflect new state
        statusItem?.menu = buildMenu()
    }

    @objc private func showOnboarding() {
        onShowOnboarding()
    }

    @objc private func quit() {
        onQuit()
    }
}

extension MenubarController: NSMenuDelegate {
    nonisolated func menuWillOpen(_ menu: NSMenu) {
        // Triggered each open — keep label fresh + refill Recent tips submenu.
        let menuTitle = menu.title
        Task { @MainActor in
            if menuTitle == "Recent tips" {
                self.refreshRecentTipsSubmenu(menu)
                return
            }
            if let item = menu.items.first(where: { $0.action == #selector(toggleLogin) }) {
                item.title = LoginItem.isEnabled() ? "✓ 开机自启" : "开机自启"
            }
        }
    }
}
