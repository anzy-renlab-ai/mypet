import Foundation
import OSLog

private let log = Logger(subsystem: "ai.mypet", category: "FeedLog")

/// Append-only JSON log of feed events.
///
/// Storage: ~/Library/Application Support/mypet/feed-log.json (production)
/// Tests inject a custom URL.
/// All mutations serialized via actor to prevent concurrent-write corruption.
actor FeedLog {

    struct Entry: Codable, Equatable {
        let ts: Date
        let tip: String
        let exitCode: Int32
        /// Tokens consumed by this feed (input + output). 0 for failures or
        /// older entries written before token capture was wired.
        let tokens: Int

        init(ts: Date, tip: String, exitCode: Int32, tokens: Int = 0) {
            self.ts = ts
            self.tip = tip
            self.exitCode = exitCode
            self.tokens = tokens
        }

        // Decoder accepts entries missing the tokens field (old log files).
        enum CodingKeys: String, CodingKey { case ts, tip, exitCode, tokens }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            ts = try c.decode(Date.self, forKey: .ts)
            tip = try c.decode(String.self, forKey: .tip)
            exitCode = try c.decode(Int32.self, forKey: .exitCode)
            tokens = (try? c.decode(Int.self, forKey: .tokens)) ?? 0
        }
    }

    private let url: URL

    init(url: URL) {
        self.url = url
    }

    /// Default production location.
    static func defaultURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("mypet", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("feed-log.json")
    }

    /// Cap log size to avoid unbounded growth. Oldest entries dropped.
    /// 1000 entries × ~200B JSON ≈ 200KB max — generous for years of use.
    static let maxEntries: Int = 1000

    func append(_ entry: Entry) async throws {
        var entries = try readUnchecked()
        entries.append(entry)
        if entries.count > Self.maxEntries {
            entries = Array(entries.suffix(Self.maxEntries))
        }
        try persist(entries)
    }

    func read() async throws -> [Entry] {
        try readUnchecked()
    }

    func lastFeedTimestamp() async throws -> Date? {
        let entries = try readUnchecked()
        return entries.last?.ts
    }

    /// Most recent N successful tips, newest first. Skips failure entries
    /// (exitCode != 0) and empty tips. Used by the menubar "Recent tips" submenu.
    func recentTips(limit: Int = 10) async throws -> [Entry] {
        let entries = try readUnchecked()
        return entries
            .reversed()
            .filter { $0.exitCode == 0 && !$0.tip.isEmpty }
            .prefix(limit)
            .map { $0 }
    }

    func cooldownActive(seconds: TimeInterval) async throws -> Bool {
        guard let last = try await lastFeedTimestamp() else { return false }
        return Date().timeIntervalSince(last) < seconds
    }

    func isHungry(after seconds: TimeInterval) async throws -> Bool {
        guard let last = try await lastFeedTimestamp() else {
            // Never-fed cat is not yet hungry — onboarding handles first feed.
            return false
        }
        return Date().timeIntervalSince(last) >= seconds
    }

    // MARK: - Private

    private func readUnchecked() throws -> [Entry] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            log.warning("read failed, treating as empty: \(error.localizedDescription)")
            return []
        }
        if data.isEmpty { return [] }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([Entry].self, from: data)
        } catch {
            log.warning("corrupt JSON, recovering as empty: \(error.localizedDescription)")
            return []
        }
    }

    private func persist(_ entries: [Entry]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(entries)
        try data.write(to: url, options: .atomic)
    }
}
