import Foundation
import AVFoundation

/// Default audio player wired through AVFoundation. Plays whatever audio file
/// (mp3 / m4a / wav) the pack ships and offers an `AVSpeechSynthesizer` based
/// fallback when a vocabulary item has no recording — host apps can opt into
/// the synthesised voice on a per-call basis.
///
/// Hosts that prefer their own audio stack can ignore this type entirely and
/// supply a `(URL) -> Void` closure directly to `LessonRunnerView`.
///
/// Concurrency: the underlying AV objects aren't `Sendable`, but they're
/// confined to this class and protected by `lock`. We mark the class as
/// `@unchecked Sendable` so the SDK can pass instances across actor
/// boundaries (e.g. from a SwiftUI view to a background `Task`).
public final class PaktlyAudioPlayer: @unchecked Sendable {
    private let lock = NSLock()
    private var player: AVAudioPlayer?
    private let synthesizer = AVSpeechSynthesizer()

    public init() {}

    /// Play a local audio file. Stops any in-flight playback first so
    /// rapid taps on different items don't stack overlapping audio.
    public func play(_ url: URL) {
        lock.lock(); defer { lock.unlock() }
        player?.stop()
        guard let next = try? AVAudioPlayer(contentsOf: url) else {
            // Silent failure on purpose — UI shouldn't blow up if a single
            // pack ships a corrupt audio file. Host can layer diagnostics
            // by supplying its own `(URL) -> Void` closure instead.
            return
        }
        next.prepareToPlay()
        next.play()
        player = next
    }

    /// Speak `text` via the system TTS. Used when the creator hasn't
    /// recorded audio for a vocabulary item — Phase 5 will warn creators
    /// about missing audio if they want featured placement.
    public func speak(_ text: String, languageCode: String? = nil) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        if let languageCode {
            utterance.voice = AVSpeechSynthesisVoice(language: languageCode)
        }
        synthesizer.speak(utterance)
    }

    public func stop() {
        lock.lock(); defer { lock.unlock() }
        player?.stop()
        synthesizer.stopSpeaking(at: .immediate)
    }

    /// Convenience adapter that fits `LessonRunnerView`'s `onAudioRequest`
    /// closure parameter. Holds the player weakly so callers can let the
    /// instance go out of scope without orphaning audio.
    public var asAudioRequestHandler: @Sendable (URL) -> Void {
        { [weak self] url in self?.play(url) }
    }
}
