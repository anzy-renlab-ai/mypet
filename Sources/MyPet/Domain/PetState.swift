import Foundation

/// The 6 visual states from DESIGN.md.
///
/// Base states drive a sprite (or vector) layer. `excited` is an overlay
/// that briefly covers any base state.
enum PetState: Equatable {
    case idle
    case eating
    case excited
    case purring
    case sleepy
    case hungry
}

/// Pure state machine — no UI, no I/O. Drives transitions on events.
///
/// Diagram:
///
///   feed→  ┌─ eating ─┐  done→  ┌─ excited ─┐  3s→  ┌─ purring ─┐  3s→
///   ─────►│          │────────►│   (5s)    │──────►│  (8s)     │────►
///   idle ◄┘          └◄─error──┘           └──────►│ idle      │
///         │          │
///         │  24h idle│
///         ▼          ▼
///       hungry    sleepy
///
/// Hungry is event-driven (D11): only checked on app activate, mouse near,
/// or after feed. We expose `evaluateIdleTransitions` for callers to invoke.
struct PetStateMachine {

    /// Sleepy after this many seconds of no events.
    var sleepyAfter: TimeInterval = 2 * 3600

    /// Hungry after this many seconds since last successful feed.
    var hungryAfter: TimeInterval = 24 * 3600

    /// Current base state.
    private(set) var state: PetState = .idle

    /// Overlay flag: excited shown above base. Resolved by view layer.
    private(set) var excited: Bool = false

    /// Timestamps used for derived transitions.
    /// `lastEventAt` defaults to launch time so a fresh app stays idle
    /// rather than immediately falling into sleepy.
    /// `lastFeedAt` stays `.distantPast` until a real feed succeeds.
    private(set) var lastEventAt: Date
    private(set) var lastFeedAt: Date = .distantPast

    init(sleepyAfter: TimeInterval = 2 * 3600, hungryAfter: TimeInterval = 24 * 3600, now: Date = Date()) {
        self.sleepyAfter = sleepyAfter
        self.hungryAfter = hungryAfter
        self.lastEventAt = now
    }

    // MARK: - Mutations

    mutating func startFeed(now: Date = Date()) {
        state = .eating
        lastEventAt = now
    }

    mutating func feedSucceeded(now: Date = Date()) {
        state = .excited      // for the burst flash
        excited = true
        lastEventAt = now
        lastFeedAt = now
    }

    /// After the excited burst, transition to purring (showing tip).
    mutating func excitedDidFinish(now: Date = Date()) {
        state = .purring
        excited = false
        lastEventAt = now
    }

    /// After purring (tip dismissed), back to idle.
    mutating func purringDidFinish(now: Date = Date()) {
        state = .idle
        lastEventAt = now
    }

    /// On feed error: skip eating, show hungry-with-error overlay; caller
    /// is responsible for the specific fallback animation.
    mutating func feedFailed(now: Date = Date()) {
        state = .hungry
        lastEventAt = now
    }

    /// Caller invokes when an idle event happens (app activate, mouse near,
    /// menu opened, post-feed transition). Evaluates whether to escalate.
    mutating func evaluateIdleTransitions(now: Date = Date()) {
        guard state == .idle else { return }
        let sinceFeed = now.timeIntervalSince(lastFeedAt)
        let sinceEvent = now.timeIntervalSince(lastEventAt)
        if lastFeedAt != .distantPast, sinceFeed >= hungryAfter {
            state = .hungry
        } else if sinceEvent >= sleepyAfter {
            state = .sleepy
        }
    }

    /// Wake the cat (mouse enters interactive zone or app activated).
    mutating func wake(now: Date = Date()) {
        if state == .sleepy || state == .hungry {
            state = .idle
        }
        lastEventAt = now
    }
}
