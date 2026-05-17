import Foundation
import OSLog
import SwiftUI

private let log = Logger(subsystem: "ai.mypet", category: "FeedCoordinator")

/// Abstraction over `ClaudeSubprocess.shared.feed` for testability.
protocol Feeder {
    func feed(prompt: String) async -> Result<FeedSuccess, ClaudeSubprocessError>
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
    /// Tokens consumed by the most recent successful feed (input + output).
    @Published private(set) var lastTokens: Int = 0
    /// Running total tokens this session.
    @Published private(set) var totalTokens: Int = 0

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

    /// Theme of a single feed. Rotating among themes makes every feed feel
    /// different — programmers come back to see what the cat says next.
    /// The active theme is published so the UI can hint it (optional).
    enum TipTheme: String, CaseIterable {
        case claudeTip      // Claude Code tip
        case techNews       // tiny tech news headline
        case devJoke        // one-liner programmer joke
        case til            // today-I-learned fact
        case promptIdea     // a Claude Code prompt to try right now
        case dayouShi       // 程序员打油诗 (Chinese satirical verse)

        /// Convenience: prompt for the current system language.
        var prompt: String { prompt(for: SystemLanguage.current) }

        /// Locale-aware prompt. Chinese users get Chinese prompts so the tip
        /// itself comes back in Chinese — otherwise English.
        func prompt(for lang: SystemLanguage) -> String {
            switch lang {
            case .zh: return promptZh
            case .en: return promptEn
            }
        }

        private var promptEn: String {
            switch self {
            case .claudeTip:
                return "Share ONE non-obvious Claude Code tip a daily user would actually thank you for. " +
                    "Max 140 chars. No preamble, no list markers. End with one relevant emoji."
            case .techNews:
                return "Give ONE short tech-news headline from the last 7 days. " +
                    "Max 140 chars. Just the headline, no source. End with one relevant emoji."
            case .devJoke:
                return "Tell ONE original one-liner programmer joke. Max 140 chars. " +
                    "Make it actually funny (groan-funny ok). End with one relevant emoji."
            case .til:
                return "Share ONE 'today I learned' fact about software / computing that a senior engineer " +
                    "would still find surprising. Max 140 chars. End with one relevant emoji."
            case .promptIdea:
                return "Suggest ONE specific prompt to type into Claude Code right now, that would teach the " +
                    "user something useful about their own codebase. Max 140 chars. Wrap in backticks. End with 🐱."
            case .dayouShi:
                return "Write ONE four-line Chinese 打油诗 (dǎyóushī — a punny, irreverent " +
                    "quatrain) about a programmer's daily struggle. Output the four lines in " +
                    "Chinese, separated by slashes. Max 60 Chinese chars total. End with one relevant emoji."
            }
        }

        private var promptZh: String {
            switch self {
            case .claudeTip:
                return "用中文给我一条非常实用、不为人熟知的 Claude Code 使用小技巧。" +
                    "不超过 100 个汉字。不要前言、不要列表符号。末尾加一个相关的 emoji。"
            case .techNews:
                return "用中文给我一句过去 7 天内的科技新闻头条。" +
                    "不超过 100 个汉字。只给标题，不给来源。末尾加一个相关的 emoji。"
            case .devJoke:
                return "用中文讲一个程序员一句话冷笑话，原创为佳。不超过 100 个汉字。" +
                    "要真的好笑（无奈一笑也算）。末尾加一个相关的 emoji。"
            case .til:
                return "用中文分享一条软件 / 计算机领域的「今日新知」，要让资深工程师也觉得意外。" +
                    "不超过 100 个汉字。末尾加一个相关的 emoji。"
            case .promptIdea:
                return "用中文建议一条现在就能粘进 Claude Code 的 prompt，能让用户对自己的代码库有新发现。" +
                    "不超过 100 个汉字。把 prompt 用反引号包起来。末尾加 🐱。"
            case .dayouShi:
                return "用中文写一首四句程序员主题的打油诗，要俏皮、押韵、接地气，" +
                    "四句之间用斜杠分隔。总字数不超过 60 字。末尾加一个相关的 emoji。"
            }
        }
    }

    /// Coarse language bucket — keeps prompt switching to two well-tested cases.
    enum SystemLanguage {
        case en, zh

        static var current: SystemLanguage {
            let primary = Locale.preferredLanguages.first ?? Locale.current.identifier
            return primary.lowercased().hasPrefix("zh") ? .zh : .en
        }
    }

    /// Pick a theme for the next feed. Weighted toward Claude Code content
    /// (tip + promptIdea = ~50%) since that's the niche the project lives in.
    static func nextTheme(rng: () -> Double = { Double.random(in: 0..<1) }) -> TipTheme {
        let r = rng()
        switch r {
        case ..<0.30: return .claudeTip
        case ..<0.50: return .promptIdea
        case ..<0.68: return .techNews
        case ..<0.82: return .til
        case ..<0.92: return .devJoke
        default:      return .dayouShi
        }
    }

    /// Theme used by the most recent (or in-flight) feed. Surfaced for tests
    /// and a future UI hint.
    @Published private(set) var lastTheme: TipTheme = .claudeTip

    /// Default prompt for one-shot callers / smoke tests. Keep the symbol
    /// so existing tests that read `defaultPrompt` still compile.
    static let defaultPrompt = TipTheme.claudeTip.prompt

    /// User clicked Feed. Orchestrates the full cycle.
    func feed() async {
        // Already feeding? ignore.
        guard machine.state != .eating else { return }

        // Cooldown gate — give the user feedback instead of silently doing nothing.
        if let last = try? await log.lastFeedTimestamp() {
            let sinceLast = Date().timeIntervalSince(last)
            if sinceLast < cooldownSeconds {
                let remaining = Int((cooldownSeconds - sinceLast).rounded(.up))
                Self.log.info("feed rejected: cooldown active (\(remaining)s left)")
                tip = "还在消化呢，再等 \(remaining) 秒 🐾"
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                tip = nil
                return
            }
        }

        // Start: state → eating
        machine.startFeed()
        state = .eating
        excited = false
        tip = nil
        lastError = nil

        // Pick a fresh theme per feed and route its prompt to the subprocess.
        let theme = Self.nextTheme()
        lastTheme = theme
        let result = await feeder.feed(prompt: theme.prompt)

        switch result {
        case .success(let success):
            await handleSuccess(success)
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

    private func handleSuccess(_ success: FeedSuccess) async {
        let receivedTip = success.tip
        machine.feedSucceeded()
        state = .excited
        excited = true
        lastTokens = success.tokens
        totalTokens += success.tokens

        // Record to log (tokens captured in the entry too)
        do {
            try await log.append(.init(ts: Date(), tip: receivedTip, exitCode: 0, tokens: success.tokens))
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
            ? "喵～我是 mypet 的小猫，谢谢你接我回家 🐾"
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
            return "小猫找不到 Claude Code，去 docs.anthropic.com/claude-code 装一下吧 🐾"
        case .notAuthenticated:
            return "你的 Claude 没登录！跑 `claude login` 再喂猫 🐾"
        case .rateLimited:
            return "限速中... 一会儿再来 🌀"
        case .timeout:
            return "Claude 想了太久，下次试试 🕐"
        case .cancelled:
            return "小猫被打断了 🐾"
        case .emptyOutput:
            return "Claude 给了个空响应，再喂一次？🤔"
        case .systemError, .nonZeroExit:
            return "出了点问题，过会再试 🐾"
        case .busy:
            return "小猫正在吃，等等再喂 🐾"
        }
    }
}
