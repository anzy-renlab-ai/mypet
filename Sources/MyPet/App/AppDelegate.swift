import AppKit
import SwiftUI
import OSLog

let logger = Logger(subsystem: "ai.mypet", category: "App")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var petWindow: PetWindow?
    private var onboardingWindow: NSWindow?
    private var menubar: MenubarController?
    private var coordinator: FeedCoordinator!
    private var feedLog: FeedLog!

    private var hasShownOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: "mypet.onboarding.shown") }
        set { UserDefaults.standard.set(newValue, forKey: "mypet.onboarding.shown") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("mypet launching")
        NSApp.setActivationPolicy(.accessory)

        feedLog = FeedLog(url: FeedLog.defaultURL())
        coordinator = FeedCoordinator(log: feedLog)

        menubar = MenubarController(
            coordinator: coordinator,
            onShowOnboarding: { [weak self] in
                self?.showOnboarding()
            },
            onQuit: {
                NSApp.terminate(nil)
            }
        )

        installPetWindow()

        if !hasShownOnboarding {
            showOnboarding()
        }

        // Debug: auto-feed on launch when MYPET_AUTO_FEED is set.
        if ProcessInfo.processInfo.environment["MYPET_AUTO_FEED"] != nil {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                logger.info("MYPET_AUTO_FEED set — firing feed()")
                await coordinator.feed()
            }
        }

        // Probe idle transitions on app activate
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.coordinator.evaluateIdle()
            }
        }
    }

    private func installPetWindow() {
        let window = PetWindow(rootView: AnyView(petRoot()))
        window.placeBottomRight()
        window.makeKeyAndOrderFront(nil)
        petWindow = window
    }

    private func petRoot() -> some View {
        PetRootView(coordinator: coordinator)
    }

    private func showOnboarding() {
        let view = OnboardingView(
            coordinator: coordinator,
            onComplete: { [weak self] in
                self?.dismissOnboarding()
            }
        )
        let host = NSHostingController(rootView: view)
        host.view.wantsLayer = true
        host.view.layer?.cornerRadius = 22
        host.view.layer?.masksToBounds = true

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 380),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = host
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.center()
        window.makeKeyAndOrderFront(nil)
        // Make draggable from any background area
        window.isMovableByWindowBackground = true
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow = window
    }

    private func dismissOnboarding() {
        hasShownOnboarding = true
        onboardingWindow?.close()
        onboardingWindow = nil
    }
}

/// Tap the cat to feed. No separate button.
@MainActor
struct PetRootView: View {
    @ObservedObject var coordinator: FeedCoordinator

    var body: some View {
        ZStack {
            // Tip bubble above cat
            if let tip = coordinator.tip {
                VStack {
                    TipBubble(text: tip) {
                        coordinator.dismissTip()
                    }
                    .padding(.top, 20)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .zIndex(2)
            }

            // Turtle — hover 1s to feed
            TurtleView(
                state: coordinator.state,
                excited: coordinator.excited,
                onFeed: { Task { await coordinator.feed() } }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .zIndex(1)
        }
        .frame(width: 140, height: 120)
    }
}
