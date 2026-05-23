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
    private var groomingTimer: Timer?

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
            },
            onBringHere: { [weak self] in
                self?.petWindow?.placeBottomRight()
            },
            onSnapTo: { [weak self] edge in
                self?.petWindow?.snap(to: edge)
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

        // Rare spontaneous grooming while idle. Every 90s there's a 4%
        // chance of triggering a licking or washing animation that auto-
        // returns to idle after 5s. Only fires from .idle so it never
        // interrupts feed / petting / edge states (non-intrusive principle).
        groomingTimer = Timer.scheduledTimer(withTimeInterval: 90, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self,
                      self.coordinator.state == .idle,
                      Double.random(in: 0..<1) < 0.04 else { return }
                let kind: PetState = Bool.random() ? .licking : .washing
                self.coordinator.triggerGrooming(kind)
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                self.coordinator.groomingDidFinish()
            }
        }

        // Probe idle transitions on app activate. Also re-anchor the cat
        // to the screen that currently has the cursor — the user might
        // have switched monitors while the cat was sitting somewhere
        // they can no longer see.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.coordinator.evaluateIdle()
                self?.petWindow?.placeBottomRight()
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
        // Single click while a tip bubble is visible → copy tip text to the
        // clipboard, then dismiss. SwiftUI's onTapGesture can't fire with
        // ignoresMouseEvents=true so this dismiss path lives in MouseMonitor.
        // The click still passes through to whatever app is behind us
        // (acceptable; suppressing it would need Accessibility).
        monitor.onSingleClick = { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self, let tip = self.coordinator.tip else { return }
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(tip, forType: .string)
                self.coordinator.dismissTip()
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
        // when it clears.
        //
        // When SHOWING a tip: resize the window FIRST without animation, so
        // the SwiftUI bubble has a full content frame on its first layout
        // pass. Otherwise the bubble was being clipped by the still-growing
        // window and the user had to click to force a redraw before the
        // text became visible.
        //
        // When HIDING: animate the shrink — looks tidy on tip dismiss.
        tipCancellable = coordinator.$tip.sink { [weak self] tip in
            guard let self, let w = self.petWindow else { return }
            w.setExpanded(tip != nil, animate: tip == nil)
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
        // Cat center in window content coords (y-up, origin bottom-left).
        // Measured against the rendered sprite (196×200 window): the cat is
        // horizontally centered and bottom-anchored, center ≈ (98, 61), with
        // head/ears reaching y≈122. The old (130,50) r50 circle sat too low
        // and to the right — at the cat's x it only reached y≈88, so hovering
        // the head (the natural place to pet) missed. Centered on the sprite.
        let cx: CGFloat = 95, cy: CGFloat = 65
        let dx = p.x - cx, dy = p.y - cy
        return dx * dx + dy * dy <= 60 * 60
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

    /// Hide the badge for cooldown / error tips — those are app messages,
    /// not LLM output. (The "接我回家" welcome tip has been removed in favor
    /// of always showing the real LLM response, so we no longer skip it.)
    private func themeBadge(for coord: FeedCoordinator) -> ThemeBadge? {
        guard coord.lastError == nil else { return nil }
        if coord.tip?.contains("消化") == true { return nil }
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
