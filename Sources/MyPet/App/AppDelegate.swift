import AppKit
import SwiftUI
import OSLog
import Combine

let logger = Logger(subsystem: "ai.mypet", category: "App")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var petWindow: PetWindow?
    private var onboardingWindow: NSWindow?
    private var menubar: MenubarController?
    private var coordinator: FeedCoordinator!
    private var feedLog: FeedLog!
    private var tipCancellable: AnyCancellable?

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
            feedLog: feedLog,
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

        // Grow the window to fit a tip bubble while one is showing, shrink back
        // when it clears. Without this the bubble is wider than the window and
        // the tip text gets clipped.
        tipCancellable = coordinator.$tip.sink { [weak self] tip in
            guard let self, let w = self.petWindow else { return }
            w.setExpanded(tip != nil, animate: true)
            w.placeBottomRight()
        }
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

/// Hover the turtle 1s to feed. Fills the window, which resizes between
/// compact and expanded as a tip bubble shows/hides (handled in AppDelegate).
@MainActor
struct PetRootView: View {
    @ObservedObject var coordinator: FeedCoordinator

    var body: some View {
        VStack(spacing: 4) {
            if let tip = coordinator.tip {
                TipBubble(text: tip, themeBadge: themeBadge(for: coordinator)) {
                    coordinator.dismissTip()
                }
                .padding(.top, 8)
                .frame(maxWidth: .infinity, alignment: .center)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            Spacer(minLength: 0)
            HStack {
                Spacer(minLength: 0)
                TurtleView(
                    state: coordinator.state,
                    excited: coordinator.excited,
                    onFeed: { Task { await coordinator.feed() } }
                )
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: coordinator.tip)
    }

    /// Hide the badge for first-feed welcome / cooldown / error tips —
    /// those are app messages, not LLM output.
    private func themeBadge(for coord: FeedCoordinator) -> ThemeBadge? {
        guard coord.lastError == nil else { return nil }
        if coord.tip?.contains("消化") == true { return nil }
        if coord.tip?.contains("接我回家") == true { return nil }
        switch coord.lastTheme {
        case .claudeTip:  return .claudeTip
        case .promptIdea: return .promptIdea
        case .techNews:   return .techNews
        case .til:        return .til
        case .devJoke:    return .devJoke
        case .haiku:      return .haiku
        }
    }
}
