import AVFAudio
import UIKit

@MainActor
final class GameFeedbackManager: ObservableObject {
    private let mapper = GameFeedbackMapper()
    private var effectPlayers: [String: AVAudioPlayer] = [:]
    private var missingResources: Set<String> = []
    private var musicPlayer: AVAudioPlayer?
    private var isAudioSessionConfigured = false

    func apply(settings: GameSettings) {
        if settings.musicEnabled {
            startMusicIfAvailable()
        } else {
            musicPlayer?.stop()
        }
    }

    func consume(_ events: [DemoSessionEvent], settings: GameSettings) {
        let cues = mapper.cues(for: events)
        guard !cues.isEmpty else { return }

        for cue in cues {
            if settings.soundEffectsEnabled {
                playEffect(for: cue)
            }
            if settings.hapticsEnabled {
                playHaptic(for: cue)
            }
        }
    }

    func triggerHaptic(for cue: GameFeedbackCue, settings: GameSettings) {
        guard settings.hapticsEnabled else { return }
        playHaptic(for: cue)
    }

    private func playEffect(for cue: GameFeedbackCue) {
        let resourceName = soundResourceName(for: cue)
        guard !missingResources.contains(resourceName) else { return }

        if let player = effectPlayers[resourceName] {
            player.currentTime = 0
            player.play()
            return
        }

        guard let url = Bundle.main.url(
            forResource: resourceName,
            withExtension: "m4a",
            subdirectory: "Audio"
        ) else {
            missingResources.insert(resourceName)
            return
        }

        configureAudioSessionIfNeeded()
        guard let player = try? AVAudioPlayer(contentsOf: url) else {
            missingResources.insert(resourceName)
            return
        }
        player.prepareToPlay()
        effectPlayers[resourceName] = player
        player.play()
    }

    private func startMusicIfAvailable() {
        if let musicPlayer {
            guard !musicPlayer.isPlaying else { return }
            musicPlayer.play()
            return
        }

        guard let url = Bundle.main.url(
            forResource: "tower-ambience",
            withExtension: "m4a",
            subdirectory: "Audio"
        ) else { return }

        configureAudioSessionIfNeeded()
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return }
        player.numberOfLoops = -1
        player.volume = 0.45
        player.prepareToPlay()
        musicPlayer = player
        player.play()
    }

    private func configureAudioSessionIfNeeded() {
        guard !isAudioSessionConfigured else { return }
        isAudioSessionConfigured = true
        try? AVAudioSession.sharedInstance().setCategory(
            .ambient,
            mode: .default,
            options: [.mixWithOthers]
        )
    }

    private func playHaptic(for cue: GameFeedbackCue) {
        switch cue {
        case let .spellAccepted(perfect):
            if perfect {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } else {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        case .spellRejected, .defeat:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        case .enemyDamaged:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.75)
        case let .playerDamaged(strong):
            UIImpactFeedbackGenerator(style: strong ? .heavy : .rigid)
                .impactOccurred(intensity: strong ? 1 : 0.75)
        case let .playerGuarded(strong):
            UIImpactFeedbackGenerator(style: strong ? .rigid : .soft)
                .impactOccurred(intensity: strong ? 0.9 : 0.65)
        case .barrierApplied:
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.7)
        case .absoluteBarrierNegated, .barrierDispelled:
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 1)
        case .victory, .rewardSelected, .descentApproved:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case let .descentSealRejected(exhausted):
            UINotificationFeedbackGenerator()
                .notificationOccurred(exhausted ? .error : .warning)
        case let .descentSealStageCompleted(final):
            if final {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } else {
                UISelectionFeedbackGenerator().selectionChanged()
            }
        }
    }

    private func soundResourceName(for cue: GameFeedbackCue) -> String {
        switch cue {
        case let .spellAccepted(perfect): perfect ? "cast-perfect" : "cast-success"
        case .spellRejected: "cast-rejected"
        case .enemyDamaged: "enemy-hit"
        case let .playerDamaged(strong): strong ? "player-hit-strong" : "player-hit"
        case let .playerGuarded(strong): strong ? "barrier-hit-strong" : "barrier-hit"
        case .barrierApplied: "barrier-applied"
        case .absoluteBarrierNegated: "absolute-negated"
        case .barrierDispelled: "barrier-dispelled"
        case .victory: "battle-victory"
        case .defeat: "battle-defeat"
        case .rewardSelected: "scroll-selected"
        case .descentApproved: "descent-approved"
        case let .descentSealRejected(exhausted):
            exhausted ? "descent-seal-failed" : "descent-seal-rejected"
        case let .descentSealStageCompleted(final):
            final ? "descent-seal-approved" : "descent-seal-stage-complete"
        }
    }
}
