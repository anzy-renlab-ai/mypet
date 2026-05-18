import Foundation

/// Visual states the cat can be in. String-backed so the rawValue is also
/// the key used by `CatTheme` to look up the corresponding APNG/PNG asset.
enum PetState: String, Equatable {
    // MARK: Core feedback cycle (all user-triggered)
    case idle
    case eating
    case excited
    case purring

    // MARK: Mood
    /// Quiet passive sadness after 24h with no feed. Per non-intrusive
    /// principle: just looks forlorn, does NOT actively beg for attention.
    case hungry

    // MARK: Sleep progression — passive degradation, never grabs attention.
    /// 5 min idle → drowsy sitting, eyes 35% heavy
    case sleepy
    /// 15 min idle → eyes fully closed, head dropped to chest, still seated
    case dozing
    /// 30 min idle → curled up on side, deep sleep
    case sleeping

    // MARK: Spatial interaction — set externally by PetWindow when the
    // user drags the window near a screen edge.
    case clingTop
    case peekLeft
    case peekRight

    // MARK: Engagement
    /// Cursor lingers on the cat for ≥1s → cat tilts head into a pet.
    case petting

    // MARK: Personality moments — spontaneous low-frequency from idle.
    /// Cat licks its own front paw.
    case licking
    /// Cat uses a (presumably-licked) paw to wipe its face.
    case washing
}

/// Pure state machine — no UI, no I/O. Drives transitions on events.
///
/// State graph (highlights):
///
///   ┌────────── idle ──────────┐
///   │  feed→  eating  →  excited (3s)  →  purring (8s)  →  idle
///   │  idle ≥ 5min  →  sleepy ─→ dozing (15min) ─→ sleeping (30min)
///   │  ≥ 24h no feed  →  hungry
///   │  window at edge →  clingTop / peekLeft / peekRight
///   │  hover ≥ 1s on cat → petting
///   │  rare ambient → licking / washing
///   └──────────────────────────┘
///
/// Edge states override sleep progression but never the active feed cycle.
/// Hover-petting only from restful states. Any user interaction wakes.
struct PetStateMachine {

    /// Sleep progression timings (seconds since last event).
    /// Defaults reflect the redesigned cadence (5min / 15min / 30min).
    var sleepyAfter: TimeInterval = 5 * 60
    var dozeAfter: TimeInterval = 15 * 60
    var sleepAfter: TimeInterval = 30 * 60

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

    init(sleepyAfter: TimeInterval = 5 * 60, hungryAfter: TimeInterval = 24 * 3600, now: Date = Date()) {
        self.sleepyAfter = sleepyAfter
        self.hungryAfter = hungryAfter
        self.lastEventAt = now
    }

    // MARK: - Feed cycle

    mutating func startFeed(now: Date = Date()) {
        state = .eating
        lastEventAt = now
    }

    mutating func feedSucceeded(now: Date = Date()) {
        state = .excited
        excited = true
        lastEventAt = now
        lastFeedAt = now
    }

    mutating func excitedDidFinish(now: Date = Date()) {
        state = .purring
        excited = false
        lastEventAt = now
    }

    mutating func purringDidFinish(now: Date = Date()) {
        state = .idle
        lastEventAt = now
    }

    mutating func feedFailed(now: Date = Date()) {
        state = .hungry
        lastEventAt = now
    }

    // MARK: - Idle decay

    /// Caller invokes when an idle event happens (app activate, mouse near,
    /// menu opened, post-feed transition). Evaluates whether to escalate.
    /// Sleep progression: idle → sleepy (5min) → dozing (15min) → sleeping (30min).
    mutating func evaluateIdleTransitions(now: Date = Date()) {
        let sinceFeed = now.timeIntervalSince(lastFeedAt)
        let sinceEvent = now.timeIntervalSince(lastEventAt)

        if lastFeedAt != .distantPast, sinceFeed >= hungryAfter,
           [.idle, .sleepy, .dozing, .sleeping].contains(state) {
            state = .hungry
            return
        }

        switch state {
        case .idle:
            if sinceEvent >= sleepyAfter { state = .sleepy }
        case .sleepy:
            if sinceEvent >= dozeAfter { state = .dozing }
        case .dozing:
            if sinceEvent >= sleepAfter { state = .sleeping }
        default:
            break
        }
    }

    /// Wake the cat. Any restful / passive state → idle.
    mutating func wake(now: Date = Date()) {
        if [.sleepy, .hungry, .dozing, .sleeping, .petting, .licking, .washing].contains(state) {
            state = .idle
        }
        lastEventAt = now
    }

    // MARK: - Spatial interaction (set by PetWindow.edge proximity)

    private static let edgeOverridable: Set<PetState> = [
        .idle, .sleepy, .dozing, .sleeping, .hungry, .petting, .licking, .washing
    ]

    /// Set an edge state if the cat isn't busy with the feed cycle.
    /// Returns true if the state actually changed.
    @discardableResult
    mutating func enterEdge(_ edge: PetState, now: Date = Date()) -> Bool {
        guard [.clingTop, .peekLeft, .peekRight].contains(edge) else { return false }
        guard PetStateMachine.edgeOverridable.contains(state) else { return false }
        if state == edge { return false }
        state = edge
        lastEventAt = now
        return true
    }

    /// User dragged the window away from an edge → return to idle.
    mutating func leaveEdge(now: Date = Date()) {
        if [.clingTop, .peekLeft, .peekRight].contains(state) {
            state = .idle
            lastEventAt = now
        }
    }

    // MARK: - Engagement: petting

    private static let pettingEnterable: Set<PetState> = [.idle, .sleepy, .hungry]

    /// Hover lingered ≥1s on the cat → cat accepts a pet.
    /// Only fires from restful states; never overrides feed cycle or edge.
    @discardableResult
    mutating func enterPetting(now: Date = Date()) -> Bool {
        guard PetStateMachine.pettingEnterable.contains(state) else { return false }
        state = .petting
        lastEventAt = now
        return true
    }

    /// Cursor moved off the cat → leave petting.
    mutating func leavePetting(now: Date = Date()) {
        if state == .petting {
            state = .idle
            lastEventAt = now
        }
    }

    // MARK: - Personality moments

    /// Spontaneous low-frequency grooming. Only from idle. Caller is
    /// responsible for rate-limiting and "only when user was recently
    /// active" gating (non-intrusive principle).
    @discardableResult
    mutating func enterGrooming(_ kind: PetState, now: Date = Date()) -> Bool {
        guard kind == .licking || kind == .washing else { return false }
        guard state == .idle else { return false }
        state = kind
        lastEventAt = now
        return true
    }

    /// Grooming animation finished → back to idle.
    mutating func groomingDidFinish(now: Date = Date()) {
        if state == .licking || state == .washing {
            state = .idle
            lastEventAt = now
        }
    }
}
