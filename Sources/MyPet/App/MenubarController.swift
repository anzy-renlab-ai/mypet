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
    private let onShowOnboarding: () -> Void
    private let onQuit: () -> Void

    init(
        coordinator: FeedCoordinator,
        onShowOnboarding: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.coordinator = coordinator
        self.onShowOnboarding = onShowOnboarding
        self.onQuit = onQuit
        super.init()
        install()
    }

    private func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            if let img = NSImage(systemSymbolName: "tortoise.fill", accessibilityDescription: "mypet") {
                img.isTemplate = true
                button.image = img
            } else {
                button.title = "🐢"
            }
            button.toolTip = "mypet"
        }
        item.menu = buildMenu()
        statusItem = item
        log.info("menubar installed")
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
        // Triggered each open — keep label fresh.
        Task { @MainActor in
            if let item = menu.items.first(where: { $0.action == #selector(toggleLogin) }) {
                item.title = LoginItem.isEnabled() ? "✓ 开机自启" : "开机自启"
            }
        }
    }
}
