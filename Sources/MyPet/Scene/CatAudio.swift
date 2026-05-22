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
    /// Only plays on state *change* so it doesn't loop while idle.
    func playIfChanged(stateKey: String) {
        guard lastPlayedState != stateKey else { return }
        lastPlayedState = stateKey
        play(stateKey: stateKey)
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
            p.volume = 1.0
            p.prepareToPlay()
            p.play()
            self.player = p
            log.debug("play \(url.lastPathComponent, privacy: .public)")
        } catch {
            log.error("init failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
