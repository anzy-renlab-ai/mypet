import AppKit
import SwiftUI
import OSLog

private let log = Logger(subsystem: "ai.mypet", category: "Menubar")

/// Owns the NSStatusItem (menubar icon + dropdown menu).
/// Routes "Feed now" to FeedCoordinator.
@MainActor
final class MenubarController: NSObject {

    private var statusItem: NSStatusItem?
    // Identity refs so menuWillOpen can recognise these submenus without
    // matching on their (localized) titles — comparing `menu.title == "Recent
    // tips"` silently failed under the Chinese locale, leaving the submenu
    // stuck on "(载入中…)".
    private weak var recentSubmenu: NSMenu?
    private weak var levelSubmenu: NSMenu?
    private weak var screensSubmenu: NSMenu?
    private let coordinator: FeedCoordinator
    private let feedLog: FeedLog
    private let onShowOnboarding: () -> Void
    private let onQuit: () -> Void
    private let onBringHere: () -> Void
    private let onSnapTo: (PetWindow.Edge) -> Void
    private let onMoveToScreen: (NSScreen) -> Void
    private let currentDisplayID: () -> CGDirectDisplayID?

    init(
        coordinator: FeedCoordinator,
        feedLog: FeedLog,
        onShowOnboarding: @escaping () -> Void,
        onQuit: @escaping () -> Void,
        onBringHere: @escaping () -> Void = {},
        onSnapTo: @escaping (PetWindow.Edge) -> Void = { _ in },
        onMoveToScreen: @escaping (NSScreen) -> Void = { _ in },
        currentDisplayID: @escaping () -> CGDirectDisplayID? = { nil }
    ) {
        self.coordinator = coordinator
        self.feedLog = feedLog
        self.onShowOnboarding = onShowOnboarding
        self.onQuit = onQuit
        self.onBringHere = onBringHere
        self.onSnapTo = onSnapTo
        self.onMoveToScreen = onMoveToScreen
        self.currentDisplayID = currentDisplayID
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
            title: L10n.t("Feed now", "立即喂猫"),
            action: #selector(feedNow),
            keyEquivalent: ""
        )
        feedItem.target = self
        menu.addItem(feedItem)

        // Recent tips submenu — populated lazily on open
        let recentTitle = L10n.t("Recent tips", "最近的 tip")
        let recentParent = NSMenuItem(title: recentTitle, action: nil, keyEquivalent: "")
        let recentSubmenu = NSMenu(title: recentTitle)
        let placeholder = NSMenuItem(
            title: L10n.t("(loading…)", "(载入中…)"),
            action: nil, keyEquivalent: ""
        )
        placeholder.isEnabled = false
        recentSubmenu.addItem(placeholder)
        recentSubmenu.delegate = self
        recentParent.submenu = recentSubmenu
        self.recentSubmenu = recentSubmenu
        menu.addItem(recentParent)

        let bringItem = NSMenuItem(
            title: L10n.t("Bring cat to this screen", "把小猫拽到这块屏"),
            action: #selector(bringHere),
            keyEquivalent: ""
        )
        bringItem.target = self
        menu.addItem(bringItem)

        // Snap-to-edge submenu — the click-through window can't be dragged,
        // so this is how the user triggers the spatial states.
        let snapTitle = L10n.t("Snap to edge", "靠边站")
        let snapParent = NSMenuItem(title: snapTitle, action: nil, keyEquivalent: "")
        let snapMenu = NSMenu(title: snapTitle)
        let snapItems: [(String, PetWindow.Edge)] = [
            (L10n.t("⬆ Cling to top",       "⬆ 挂屏顶 (clingTop)"), .top),
            (L10n.t("⬅ Peek from left",     "⬅ 左边探出 (peekLeft)"), .left),
            (L10n.t("➡ Peek from right",    "➡ 右边探出 (peekRight)"), .right),
            (L10n.t("⬇ Back to bottom-right", "⬇ 回到右下角"), .bottom),
        ]
        for (label, edge) in snapItems {
            let item = NSMenuItem(title: label, action: #selector(snapTo(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = edge
            snapMenu.addItem(item)
        }
        snapParent.submenu = snapMenu
        menu.addItem(snapParent)

        // Move-to-screen submenu — populated lazily on open (the list of
        // monitors changes at runtime when displays are plugged/unplugged).
        let screensTitle = L10n.t("Move to screen", "移到这块屏")
        let screensParent = NSMenuItem(title: screensTitle, action: nil, keyEquivalent: "")
        let screensMenu = NSMenu(title: screensTitle)
        let scrPlaceholder = NSMenuItem(title: L10n.t("(loading…)", "(载入中…)"), action: nil, keyEquivalent: "")
        scrPlaceholder.isEnabled = false
        screensMenu.addItem(scrPlaceholder)
        screensMenu.delegate = self
        screensParent.submenu = screensMenu
        self.screensSubmenu = screensMenu
        menu.addItem(screensParent)

        menu.addItem(.separator())

        let loginToggle = NSMenuItem(
            title: LoginItem.isEnabled()
                ? L10n.t("✓ Launch at login", "✓ 开机自启")
                : L10n.t("Launch at login", "开机自启"),
            action: #selector(toggleLogin),
            keyEquivalent: ""
        )
        loginToggle.target = self
        menu.addItem(loginToggle)

        let aboutItem = NSMenuItem(
            title: L10n.t("Reconfigure…", "重新设置…"),
            action: #selector(showOnboarding),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)

        // Diagnostics — for bug reports + live log-verbosity control.
        let diagParent = NSMenuItem(title: L10n.t("Diagnostics", "诊断"), action: nil, keyEquivalent: "")
        let diagMenu = NSMenu()

        let revealLogs = NSMenuItem(
            title: L10n.t("Show logs in Finder", "在 Finder 中显示日志"),
            action: #selector(revealLogs), keyEquivalent: ""
        )
        revealLogs.target = self
        diagMenu.addItem(revealLogs)

        let levelParent = NSMenuItem(title: L10n.t("Log level", "日志等级"), action: nil, keyEquivalent: "")
        let levelMenu = NSMenu()
        for lvl in LogLevel.allCases {
            let it = NSMenuItem(title: lvl.label, action: #selector(setLogLevel(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = lvl.rawValue
            it.state = (Log.shared.level == lvl) ? .on : .off
            levelMenu.addItem(it)
        }
        levelMenu.delegate = self
        levelParent.submenu = levelMenu
        self.levelSubmenu = levelMenu
        diagMenu.addItem(levelParent)

        diagParent.submenu = diagMenu
        menu.addItem(diagParent)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: L10n.t("Quit mypet", "退出 mypet"),
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

    @objc private func revealLogs() {
        NSWorkspace.shared.activateFileViewerSelecting([Log.shared.directoryURL])
    }

    @objc private func setLogLevel(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? Int, let lvl = LogLevel(rawValue: raw) else { return }
        Log.shared.level = lvl
        Log.shared.info(.app, "log level set to \(lvl.label) via menubar")
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

    @objc private func bringHere() {
        onBringHere()
    }

    @objc private func snapTo(_ sender: NSMenuItem) {
        guard let edge = sender.representedObject as? PetWindow.Edge else { return }
        onSnapTo(edge)
    }

    @objc private func moveToScreen(_ sender: NSMenuItem) {
        guard let screen = sender.representedObject as? NSScreen else { return }
        onMoveToScreen(screen)
    }

    /// Rebuild the move-to-screen submenu from the live monitor list. The
    /// current screen gets a checkmark; the primary display is labelled. With a
    /// single display we show a disabled hint instead of a useless one-entry
    /// list.
    private func refreshScreensSubmenu(_ submenu: NSMenu) {
        submenu.removeAllItems()
        let screens = NSScreen.screens
        let mainID = NSScreen.main?.displayID
        let activeID = currentDisplayID()
        guard screens.count > 1 else {
            let only = NSMenuItem(title: L10n.t("(only one display)", "(只有一块屏)"), action: nil, keyEquivalent: "")
            only.isEnabled = false
            submenu.addItem(only)
            return
        }
        for (i, screen) in screens.enumerated() {
            let id = screen.displayID
            let r = screen.frame
            var label = screen.localizedName
            if label.isEmpty { label = L10n.t("Display \(i + 1)", "显示器 \(i + 1)") }
            if id == mainID { label += L10n.t(" (main)", "(主屏)") }
            label += "  \(Int(r.width))×\(Int(r.height))"
            let item = NSMenuItem(title: label, action: #selector(moveToScreen(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = screen
            item.state = (id != nil && id == activeID) ? .on : .off
            submenu.addItem(item)
        }
    }

    @objc private func quit() {
        onQuit()
    }
}

extension MenubarController: NSMenuDelegate {
    nonisolated func menuWillOpen(_ menu: NSMenu) {
        // Triggered each open. Match submenus by identity (not localized title).
        Task { @MainActor in
            if menu === self.recentSubmenu {
                self.refreshRecentTipsSubmenu(menu)
                return
            }
            if menu === self.screensSubmenu {
                self.refreshScreensSubmenu(menu)
                return
            }
            if menu === self.levelSubmenu {
                // Refresh checkmarks so the active level shows even when it was
                // changed since the menu was last built.
                for item in menu.items {
                    if let raw = item.representedObject as? Int {
                        item.state = (raw == Log.shared.level.rawValue) ? .on : .off
                    }
                }
                return
            }
            if let item = menu.items.first(where: { $0.action == #selector(self.toggleLogin) }) {
                item.title = LoginItem.isEnabled()
                    ? L10n.t("✓ Launch at login", "✓ 开机自启")
                    : L10n.t("Launch at login", "开机自启")
            }
        }
    }
}
