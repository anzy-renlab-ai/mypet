import Foundation
import OSLog

/// Severity, ordered. `off` silences everything.
enum LogLevel: Int, Comparable, CaseIterable {
    case debug = 0, info, warn, error, off

    static func < (a: LogLevel, b: LogLevel) -> Bool { a.rawValue < b.rawValue }

    var label: String {
        switch self {
        case .debug: return "DEBUG"
        case .info:  return "INFO"
        case .warn:  return "WARN"
        case .error: return "ERROR"
        case .off:   return "OFF"
        }
    }

    init(_ raw: String) {
        switch raw.lowercased() {
        case "debug", "verbose", "trace": self = .debug
        case "info":                      self = .info
        case "warn", "warning":           self = .warn
        case "error":                     self = .error
        case "off", "none", "silent":     self = .off
        default:                          self = .info
        }
    }
}

/// App-wide leveled logger. Every logic step calls one of `L.debug/info/warn/error`
/// with a category. Output goes to BOTH:
///   • a rotating file under Application Support — so a user reporting an issue
///     can attach it (menubar → "在 Finder 中显示日志"), and
///   • OSLog — so it shows in Console.app / `log stream` during development.
///
/// The runtime threshold (`Log.shared.level`) defaults to `.info` and can be
/// raised/lowered without recompiling:
///   • at launch via `MYPET_LOG_LEVEL=debug|info|warn|error|off`, or
///   • live via the menubar "日志等级" submenu (AppDelegate).
///
/// Disk is bounded: the active file rotates at ~1MB, we keep a few rotations,
/// and anything older than `maxAgeDays` (or beyond the total cap) is purged on
/// launch — so logs never grow unbounded on a user's machine.
final class Log {
    static let shared = Log()

    /// Messages below this level are dropped (cheaply — the message closure is
    /// never evaluated). Mutable so the menubar / settings can change it live.
    var level: LogLevel

    enum Category: String, CaseIterable {
        case app, feed, state, window, mouse, subprocess, storage, audio, onboarding
    }

    // MARK: Config
    private let maxBytes: Int = 1_000_000      // rotate the active file at ~1MB
    private let keepRotations = 3              // current + 3 = ~4MB worst case
    private let maxAgeDays = 7

    // MARK: State
    private let dir: URL
    private let fileURL: URL
    private let queue = DispatchQueue(label: "ai.mypet.log", qos: .utility)
    private var handle: FileHandle?
    private var bytesWritten: Int = 0
    private let osLoggers: [Category: Logger]
    private let iso: ISO8601DateFormatter

    private init() {
        level = LogLevel(ProcessInfo.processInfo.environment["MYPET_LOG_LEVEL"] ?? "info")

        var loggers: [Category: Logger] = [:]
        for c in Category.allCases { loggers[c] = Logger(subsystem: "ai.mypet", category: c.rawValue) }
        osLoggers = loggers

        iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        dir = base.appendingPathComponent("mypet/logs", isDirectory: true)
        fileURL = dir.appendingPathComponent("mypet.log")

        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        purgeOldLogs()
        openHandle()
    }

    /// Directory holding the logs — surfaced by the menubar "reveal" action.
    var directoryURL: URL { dir }

    // MARK: - Public API

    func debug(_ c: Category, _ msg: @autoclosure () -> String) { write(.debug, c, msg) }
    func info(_ c: Category, _ msg: @autoclosure () -> String)  { write(.info, c, msg) }
    func warn(_ c: Category, _ msg: @autoclosure () -> String)  { write(.warn, c, msg) }
    func error(_ c: Category, _ msg: @autoclosure () -> String) { write(.error, c, msg) }

    // MARK: - Core

    private func write(_ lvl: LogLevel, _ c: Category, _ msg: () -> String) {
        guard level != .off, lvl >= level else { return }   // cheap gate, msg() not evaluated
        let text = msg()

        // OSLog mirror (development / Console).
        let lg = osLoggers[c]!
        switch lvl {
        case .debug: lg.debug("\(text, privacy: .public)")
        case .info:  lg.info("\(text, privacy: .public)")
        case .warn:  lg.warning("\(text, privacy: .public)")
        case .error: lg.error("\(text, privacy: .public)")
        case .off:   break
        }

        // File (rotating). Off the calling thread; serialized.
        let line = "\(iso.string(from: Date())) [\(lvl.label)] [\(c.rawValue)] \(text)\n"
        queue.async { [weak self] in self?.append(line) }
    }

    private func append(_ line: String) {
        guard let data = line.data(using: .utf8) else { return }
        if handle == nil { openHandle() }
        handle?.write(data)
        bytesWritten += data.count
        if bytesWritten >= maxBytes { rotate() }
    }

    private func openHandle() {
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
        handle = try? FileHandle(forWritingTo: fileURL)
        handle?.seekToEndOfFile()
        bytesWritten = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int ?? 0) ?? 0
    }

    /// mypet.log → mypet.log.1 → … → drop beyond `keepRotations`.
    private func rotate() {
        try? handle?.close()
        handle = nil
        let fm = FileManager.default
        // shift older rotations up
        var i = keepRotations
        while i >= 1 {
            let src = i == 1 ? fileURL : dir.appendingPathComponent("mypet.log.\(i - 1)")
            let dst = dir.appendingPathComponent("mypet.log.\(i)")
            if fm.fileExists(atPath: src.path) {
                try? fm.removeItem(at: dst)
                try? fm.moveItem(at: src, to: dst)
            }
            i -= 1
        }
        bytesWritten = 0
        openHandle()
    }

    /// Delete rotations beyond the keep count and anything older than maxAgeDays.
    private func purgeOldLogs() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: []
        ) else { return }
        let cutoff = Date().addingTimeInterval(-Double(maxAgeDays) * 86_400)
        for f in files where f.lastPathComponent.hasPrefix("mypet.log") {
            // numeric suffix beyond keepRotations → drop
            let suffix = f.lastPathComponent.replacingOccurrences(of: "mypet.log", with: "")
            if let n = Int(suffix.drop(while: { $0 == "." })), n > keepRotations {
                try? fm.removeItem(at: f); continue
            }
            let mod = (try? f.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let mod, mod < cutoff { try? fm.removeItem(at: f) }
        }
    }
}
