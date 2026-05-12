import Foundation
import OSLog
import SwiftUI

private let log = Logger(subsystem: "ai.mypet", category: "FeedCoordinator")

/// Abstraction over `ClaudeSubprocess.shared.feed` for testability.
protocol Feeder {
    func feed(prompt: String) async -> Result<String, ClaudeSubprocessError>
}

extension ClaudeSubprocess: Feeder {}

/// Orchestrates the full feed cycle:
/// 1. Check cooldown
/// 2. State → eating
/// 3. Invoke feeder (claude subprocess)
/// 4. On success: state → excited (3s overlay) → purring (show tip) → idle on dismiss
/// 5. On error: classify and route to error fallback
///
/// All UI state mutations on @MainActor for SwiftUI.
@MainActor
final class FeedCoordinator: ObservableObject {

    // MARK: - Published state for SwiftUI

    @Published private(set) var state: PetState = .idle
    @Published private(set) var excited: Bool = false
    @Published private(set) var tip: String?
    @Published private(set) var lastError: ClaudeSubprocessError?
    @Published private(set) var isFirstFeed: Bool = true
    @Published private(set) var feedCount: Int = 0

    // MARK: - Configuration

    var cooldownSeconds: TimeInterval = 60
    var excitedOverlaySeconds: TimeInterval = 3
    var tipDisplaySeconds: TimeInterval = 8
    var sleepyAfter: TimeInterval = 2 * 3600
    var hungryAfter: TimeInterval = 24 * 3600

    // MARK: - Dependencies

    private var machine = PetStateMachine()
    private let feeder: Feeder
    private let log: FeedLog

    init(feeder: Feeder = ClaudeSubprocess.shared, log: FeedLog) {
        self.feeder = feeder
        self.log = log
    }

    // MARK: - Public API

    /// Returns the prompt currently used for sprite generation.
    /// Hardcoded for v0.1; v0.2 will surface a setting.
    static let defaultPrompt =
        "Give me ONE Claude Code tip OR one short tech news headline. " +
        "Output exactly one item. Max 140 characters. No preamble, no list markers. " +
        "End with one relevant emoji."

    /// User clicked Feed. Orchestrates the full cycle.
    func feed() async {
        // Cooldown gate
        if let last = try? await log.lastFeedTimestamp() {
            let sinceLast = Date().timeIntervalSince(last)
            if sinceLast < cooldownSeconds {
                Self.log.info("feed rejected: cooldown active (\(Int(self.cooldownSeconds - sinceLast))s left)")
                return
            }
        }

        // Start: state → eating
        machine.startFeed()
        state = .eating
        excited = false
        tip = nil
        lastError = nil

        // Call feeder (subprocess, may take seconds)
        let result = await feeder.feed(prompt: Self.defaultPrompt)

        switch result {
        case .success(let receivedTip):
            await handleSuccess(tip: receivedTip)
        case .failure(let error):
            await handleFailure(error: error)
        }
    }

    /// User dismissed the tip bubble. Move from purring → idle.
    func dismissTip() {
        guard machine.state == .purring else { return }
        machine.purringDidFinish()
        state = machine.state
        tip = nil
    }

    /// Triggered on app activation / mouse approach / window key.
    /// Reconciles idle transitions (sleepy after 2h, hungry after 24h).
    func evaluateIdle() {
        machine.evaluateIdleTransitions()
        state = machine.state
    }

    /// Wake the cat (sleepy → idle, hungry → idle).
    func wake() {
        machine.wake()
        state = machine.state
    }

    // MARK: - Private

    private func handleSuccess(tip receivedTip: String) async {
        machine.feedSucceeded()
        state = .excited
        excited = true

        // Record to log
        do {
            try await log.append(.init(ts: Date(), tip: receivedTip, exitCode: 0))
        } catch {
            Self.log.error("log append failed: \(error.localizedDescription)")
        }

        feedCount += 1

        // Excited overlay duration
        try? await Task.sleep(nanoseconds: UInt64(excitedOverlaySeconds * 1_000_000_000))

        // Transition: excited → purring + show tip
        machine.excitedDidFinish()
        state = machine.state
        excited = false
        tip = isFirstFeed
            ? "你好啊，我是 mypet 的小乌龟，谢谢你接我回家 🐢"
            : receivedTip
        isFirstFeed = false

        // Auto-dismiss tip after duration (user can also click)
        let pinnedTip = tip
        try? await Task.sleep(nanoseconds: UInt64(tipDisplaySeconds * 1_000_000_000))
        if tip == pinnedTip {
            dismissTip()
        }
    }

    private func handleFailure(error: ClaudeSubprocessError) async {
        Self.log.error("feed failed: \(String(describing: error))")
        machine.feedFailed()
        state = machine.state
        lastError = error

        // Record failure
        do {
            try await log.append(.init(ts: Date(), tip: "", exitCode: -1))
        } catch {
            Self.log.error("log append failed: \(error.localizedDescription)")
        }

        // Map error to a friendly tip bubble (user-facing)
        tip = friendlyMessage(for: error)

        try? await Task.sleep(nanoseconds: UInt64(tipDisplaySeconds * 1_000_000_000))
        tip = nil
        lastError = nil
        // Hungry stays until next interaction (D11: event-driven, not timed)
    }

    /// Static logger access (avoid name clash with `log` instance).
    private static let log = Logger(subsystem: "ai.mypet", category: "FeedCoordinator")

    private func friendlyMessage(for error: ClaudeSubprocessError) -> String {
        switch error {
        case .binaryNotFound:
            return "乌龟找不到 Claude Code，去 docs.anthropic.com/claude-code 装一下吧 🐢"
        case .notAuthenticated:
            return "你的 Claude 没登录！跑 `claude login` 再喂乌龟 🐾"
        case .rateLimited:
            return "度转中... 一会儿再来 🌀"
        case .timeout:
            return "Claude 想了太久，下次试试 🕐"
        case .cancelled:
            return "乌龟被打断了 🐾"
        case .emptyOutput:
            return "Claude 给了个空响应，再喂一次？🤔"
        case .systemError, .nonZeroExit:
            return "出了点问题，过会再试 🐾"
        case .busy:
            return "乌龟正在吃，等等再喂 🐢"
        }
    }
}
