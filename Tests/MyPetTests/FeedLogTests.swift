import XCTest
@testable import MyPet

final class FeedLogTests: XCTestCase {

    var tmpURL: URL!

    override func setUp() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mypet-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tmpURL = dir.appendingPathComponent("feed-log.json")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tmpURL.deletingLastPathComponent())
    }

    // MARK: - Basic append/read

    func test_read_returnsEmpty_whenFileMissing() async throws {
        let log = FeedLog(url: tmpURL)
        let entries = try await log.read()
        XCTAssertTrue(entries.isEmpty)
    }

    func test_append_writesEntry() async throws {
        let log = FeedLog(url: tmpURL)
        try await log.append(.init(ts: Date(), tip: "hi", exitCode: 0))
        let entries = try await log.read()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].tip, "hi")
    }

    func test_append_preservesOrder_acrossMultipleCalls() async throws {
        let log = FeedLog(url: tmpURL)
        let dates = (0..<3).map { Date(timeIntervalSinceNow: TimeInterval($0)) }
        for (i, d) in dates.enumerated() {
            try await log.append(.init(ts: d, tip: "tip\(i)", exitCode: 0))
        }
        let entries = try await log.read()
        XCTAssertEqual(entries.map { $0.tip }, ["tip0", "tip1", "tip2"])
    }

    // MARK: - Corruption recovery

    func test_read_recoversFromCorruptJSON_byRecreating() async throws {
        try "not valid json {{{".write(to: tmpURL, atomically: true, encoding: .utf8)
        let log = FeedLog(url: tmpURL)
        let entries = try await log.read()
        XCTAssertTrue(entries.isEmpty, "Corrupt JSON should be treated as empty")
        // Next append must succeed
        try await log.append(.init(ts: Date(), tip: "fresh", exitCode: 0))
        let after = try await log.read()
        XCTAssertEqual(after.count, 1)
    }

    func test_read_recoversFromEmptyFile() async throws {
        try Data().write(to: tmpURL)
        let log = FeedLog(url: tmpURL)
        let entries = try await log.read()
        XCTAssertTrue(entries.isEmpty)
    }

    // MARK: - Cooldown helpers

    func test_lastFeedTimestamp_returnsLatest() async throws {
        let log = FeedLog(url: tmpURL)
        let now = Date()
        try await log.append(.init(ts: now.addingTimeInterval(-100), tip: "old", exitCode: 0))
        try await log.append(.init(ts: now, tip: "new", exitCode: 0))
        let last = try await log.lastFeedTimestamp()
        XCTAssertEqual(last?.timeIntervalSince1970 ?? 0, now.timeIntervalSince1970, accuracy: 1.0)
    }

    func test_lastFeedTimestamp_returnsNil_whenEmpty() async throws {
        let log = FeedLog(url: tmpURL)
        let last = try await log.lastFeedTimestamp()
        XCTAssertNil(last)
    }

    func test_cooldownActive_trueWithin60s() async throws {
        let log = FeedLog(url: tmpURL)
        try await log.append(.init(ts: Date().addingTimeInterval(-30), tip: "recent", exitCode: 0))
        let active = try await log.cooldownActive(seconds: 60)
        XCTAssertTrue(active)
    }

    func test_cooldownActive_falseBeyondWindow() async throws {
        let log = FeedLog(url: tmpURL)
        try await log.append(.init(ts: Date().addingTimeInterval(-120), tip: "stale", exitCode: 0))
        let active = try await log.cooldownActive(seconds: 60)
        XCTAssertFalse(active)
    }

    func test_cooldownActive_falseWhenEmpty() async throws {
        let log = FeedLog(url: tmpURL)
        let active = try await log.cooldownActive(seconds: 60)
        XCTAssertFalse(active)
    }

    // MARK: - Concurrency safety

    func test_concurrentAppends_serializeCleanly() async throws {
        let log = FeedLog(url: tmpURL)
        // 20 parallel appends should not corrupt JSON
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<20 {
                group.addTask {
                    try? await log.append(.init(ts: Date(), tip: "p\(i)", exitCode: 0))
                }
            }
        }
        let entries = try await log.read()
        XCTAssertEqual(entries.count, 20, "All appends must persist; no lost writes")
    }

    // MARK: - Hungry detection

    func test_hungryAfter24h_trueWhenStale() async throws {
        let log = FeedLog(url: tmpURL)
        try await log.append(.init(
            ts: Date().addingTimeInterval(-25 * 3600),
            tip: "old",
            exitCode: 0
        ))
        let hungry = try await log.isHungry(after: 24 * 3600)
        XCTAssertTrue(hungry)
    }

    func test_hungryAfter24h_falseWhenRecent() async throws {
        let log = FeedLog(url: tmpURL)
        try await log.append(.init(ts: Date().addingTimeInterval(-3600), tip: "fresh", exitCode: 0))
        let hungry = try await log.isHungry(after: 24 * 3600)
        XCTAssertFalse(hungry)
    }

    func test_hungryAfter24h_falseWhenNeverFed() async throws {
        // Decision: never-fed cat is NOT yet hungry — onboarding handles first feed
        let log = FeedLog(url: tmpURL)
        let hungry = try await log.isHungry(after: 24 * 3600)
        XCTAssertFalse(hungry)
    }
}
