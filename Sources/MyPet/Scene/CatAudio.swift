import AppKit
import AVFoundation
import OSLog

private let log = Logger(subsystem: "ai.mypet", category: "Audio")

/// Optional cute sound effects bundled per state (matching APNG name).
/// `cat-idle.m4a`, `cat-eating.m4a`, etc. Plays once per state entry.
@MainActor
final class CatAudio {
    static let shared = CatAudio()

    private var player: AVAudioPlayer?
    private var lastPlayedState: String?

    /// Play the audio bundled for the given state's name (rawValue).
    /// No-op if no audio file ships for that state.
    /// Only plays on state *change* AND at most once per day per state — the
    /// ambient clips were firing on every transition and got annoying. The
    /// user-triggered click meow (`playMeow`) is exempt; this is only the
    /// passive per-state sound.
    func playIfChanged(stateKey: String) {
        guard lastPlayedState != stateKey else { return }
        lastPlayedState = stateKey
        guard !playedToday(stateKey) else {
            log.debug("ambient \(stateKey, privacy: .public) already played today — skip")
            return
        }
        markPlayedToday(stateKey)
        play(stateKey: stateKey)
    }

    /// Per-state once-per-day gate, persisted across launches.
    private func playedToday(_ stateKey: String) -> Bool {
        let last = UserDefaults.standard.string(forKey: "ambientDay.\(stateKey)")
        return last == Self.todayKey()
    }
    private func markPlayedToday(_ stateKey: String) {
        UserDefaults.standard.set(Self.todayKey(), forKey: "ambientDay.\(stateKey)")
    }
    private static func todayKey() -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    /// Dedicated player for the single-click "meow" so it doesn't stop/clash
    /// with the per-state ambient clip.
    private var clickPlayer: AVAudioPlayer?

    /// Play the cute click meow (single-click on the cat). No-op until a
    /// `cat-meow.m4a` (or .mp3) is dropped into Resources/sprites — so it
    /// stays silent rather than crashing while the asset is being chosen.
    func playMeow() {
        // Three little meows split from the source clip → pick one at random
        // each click for variety. Falls back to a single cat-meow, then no-op.
        let candidates = ["cat-meow-1", "cat-meow-2", "cat-meow-3"].shuffled() + ["cat-meow"]
        let url = candidates.lazy.compactMap {
            Bundle.module.url(forResource: $0, withExtension: "m4a")
                ?? Bundle.module.url(forResource: $0, withExtension: "mp3")
        }.first
        guard let url else { log.debug("no cat-meow asset yet"); return }
        clickPlayer?.stop()
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.volume = 1.0
            p.prepareToPlay()
            p.play()
            clickPlayer = p
        } catch {
            log.error("meow play failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Force play (e.g., on app launch).
    func play(stateKey: String) {
        let url = Bundle.module.url(forResource: "cat-\(stateKey)", withExtension: "m4a")
            ?? Bundle.module.url(forResource: "cat-\(stateKey)", withExtension: "mp3")
        guard let url else {
            log.debug("no asset for \(stateKey, privacy: .public)")
            return
        }
        // Stop the previous clip before starting a new one. Without this, a
        // quick state change (e.g. eating → excited → purring, or edge poses
        // while dragging) layers a second meow on top of the first — exactly
        // the attention-grabbing noise the pet is supposed to avoid.
        player?.stop()
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.volume = 0.2   // ambient = soft (20%); was 1.0 and too loud
            p.prepareToPlay()
            p.play()
            self.player = p
            log.debug("play \(url.lastPathComponent, privacy: .public)")
        } catch {
            log.error("init failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
