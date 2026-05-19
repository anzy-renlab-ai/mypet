import Foundation

/// Theme manifest — describes which asset plays for which state.
/// Schema mirrors clawd-on-desk's theme.json (the *idea* of decoupling
/// assets from code is borrowed; struct + Swift implementation is ours).
///
/// Bundled at `Resources/sprites/theme.json`. When absent, the loader
/// falls back to direct name lookup (`cat-<state>.apng`/`.png`).
struct CatTheme: Codable {
    var schemaVersion: Int = 1
    var name: String = "mypet-default"
    var author: String = "mypet"
    /// State name → asset filename (without extension).
    /// The renderer tries `.apng` first, then `.png`.
    var states: [String: String]
    /// Optional idle progression: state → next state after `seconds` of
    /// no interaction. Drives the sleep sequence.
    var transitions: [Transition]?

    struct Transition: Codable {
        let from: String
        let after: TimeInterval
        let to: String
    }

    /// Default mypet theme — every visual state maps to its bundled APNG.
    /// peekLeft/peekRight share the peekRight asset (peekLeft is rendered
    /// by horizontally mirroring peekRight at render time, not by a
    /// separate generation).
    ///
    /// Placeholders: `excited` / `licking` / `washing` use `cat-idle` until
    /// real assets land — none of Kling's batch outputs matched these poses
    /// well enough to ship.
    static let `default` = CatTheme(
        schemaVersion: 1,
        name: "mypet",
        author: "mypet",
        states: [
            "idle":      "cat-idle",
            "eating":    "cat-eating",
            "excited":   "cat-idle",       // placeholder — no usable Kling take
            "purring":   "cat-purring",
            "hungry":    "cat-hungry",
            "sleepy":    "cat-sleepy",
            "dozing":    "cat-dozing",
            "sleeping":  "cat-sleeping",
            "clingTop":  "cat-clingTop",
            "peekRight": "cat-peekRight",
            "peekLeft":  "cat-peekRight",  // mirrored at render time
            "petting":   "cat-petting",
            "licking":   "cat-idle",       // placeholder
            "washing":   "cat-idle",       // placeholder
        ],
        transitions: [
            // Sleep progression. Each step waits the listed seconds *after
            // entering the previous state* before deepening. Cumulative
            // walltime from idle: 5min → 15min → 30min.
            Transition(from: "idle",   after: 5 * 60,  to: "sleepy"),
            Transition(from: "sleepy", after: 10 * 60, to: "dozing"),
            Transition(from: "dozing", after: 15 * 60, to: "sleeping"),
        ]
    )

    /// Try to load from Bundle.module/sprites/theme.json. Fallback: default.
    static func load() -> CatTheme {
        guard let url = Bundle.module.url(forResource: "theme", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let parsed = try? JSONDecoder().decode(CatTheme.self, from: data)
        else {
            return .default
        }
        return parsed
    }

    /// Resource name for a state, falling back to "cat-<state>" if the
    /// manifest doesn't list it.
    func resourceName(for stateKey: String) -> String {
        states[stateKey] ?? "cat-\(stateKey)"
    }
}
