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

    /// Default mypet theme — six base states + sleep progression.
    static let `default` = CatTheme(
        schemaVersion: 1,
        name: "mypet",
        author: "mypet",
        states: [
            "idle": "cat-idle",
            "eating": "cat-eating",
            "excited": "cat-excited",
            "purring": "cat-purring",
            "sleepy": "cat-sleepy",
            "hungry": "cat-hungry",
            "yawning": "cat-yawning",
            "dozing": "cat-dozing",
            "sleeping": "cat-sleeping",
        ],
        transitions: [
            // Sleep sequence (borrowed concept): each step delays a bit
            // longer before deepening sleep. Wakes on any interaction.
            Transition(from: "idle", after: 30, to: "yawning"),
            Transition(from: "yawning", after: 8, to: "dozing"),
            Transition(from: "dozing", after: 15, to: "sleeping"),
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
