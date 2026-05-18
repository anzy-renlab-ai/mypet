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
    private var mouseMonitor: MouseMonitor?

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
        // Create the window first (empty contentView), then build the
        // MouseMonitor against it, then install the SwiftUI root view that
        // references the monitor. This avoids a chicken-and-egg between
        // monitor.init(window:) and the view that needs the monitor.
        let window = PetWindow()
        window.placeBottomRight()

        let monitor = MouseMonitor(window: window)
        monitor.onDoubleClick = { [weak self] in
            Task { @MainActor [weak self] in
                await self?.coordinator.feed()
            }
        }
        mouseMonitor = monitor

        // Edge proximity (window near top/left/right) → spatial state.
        window.onEdgeState = { [weak self] edge in
            self?.coordinator.setEdgeState(edge)
        }

        let host = NSHostingView(rootView: PetRootView(coordinator: coordinator, mouseMonitor: monitor))
        host.autoresizingMask = [.width, .height]
        host.frame = NSRect(origin: .zero, size: PetWindow.compactSize)
        window.contentView = host
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

/// Click-through window root. Cursor and feed events arrive via the global
/// `MouseMonitor` (the window itself has `ignoresMouseEvents = true`).
@MainActor
struct PetRootView: View {
    @ObservedObject var coordinator: FeedCoordinator
    @ObservedObject var mouseMonitor: MouseMonitor

    /// True when the cursor is currently over the drawn cat area. Bottom-
    /// right of the compact window, approximate hit-test radius.
    private var cursorOverCat: Bool {
        guard let p = mouseMonitor.cursorPos else { return false }
        // Cat center inside the 180×180 window content coords (y-up).
        let cx: CGFloat = 130, cy: CGFloat = 50
        let dx = p.x - cx, dy = p.y - cy
        return dx * dx + dy * dy <= 50 * 50
    }

    var body: some View {
        VStack(spacing: 4) {
            if let tip = coordinator.tip {
                TipBubble(text: tip,
                          themeBadge: themeBadge(for: coordinator),
                          tokens: tokensChip(for: coordinator)) {
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
                    cursorPos: mouseMonitor.cursorPos
                )
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: coordinator.tip)
        // Hover ≥1s over the cat → petting state. Leaving immediately exits.
        // The .task auto-cancels on id change, so dwell timing is precise.
        .task(id: cursorOverCat) {
            if cursorOverCat {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                coordinator.setPetting(true)
            } else {
                coordinator.setPetting(false)
            }
        }
    }

    /// Tokens chip mirrors the badge gating: only show when a real LLM tip
    /// is on screen (skip welcome / cooldown / errors).
    private func tokensChip(for coord: FeedCoordinator) -> Int? {
        guard themeBadge(for: coord) != nil else { return nil }
        return coord.lastTokens > 0 ? coord.lastTokens : nil
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
        case .dayouShi:   return .dayouShi
        }
    }
}
