import AVFAudio
import UIKit

enum GameInterfaceSound {
    case select
    case confirm
    case back
    case error
}

private enum GameMusicTrack: Equatable {
    case floor10
    case floor9
    case floor8

    init?(floor: FloorID) {
        switch floor {
        case .floor10: self = .floor10
        case .floor9: self = .floor9
        case .floor8: self = .floor8
        case .floor7: return nil
        }
    }

    var asset: GameAudioAsset {
        switch self {
        case .floor10: .floor10BGM
        case .floor9: .floor9BGM
        case .floor8: .floor8BGM
        }
    }
}

private enum GameAudioAsset: CaseIterable, Hashable {
    case floor10BGM
    case floor9BGM
    case floor8BGM
    case battleDefeat
    case battleVictory
    case managerAttack
    case managerHit
    case playerHit
    case playerSpellCast
    case uiBack
    case uiConfirm
    case uiError
    case uiSelect
    case barrierActivate
    case barrierBreak
    case barrierBroken
    case floorTransition
    case recordOpen

    var resourceName: String {
        switch self {
        case .floor10BGM: "bgm-floor10-fractured-coordinates"
        case .floor9BGM: "bgm-floor9-archival-mechanism"
        case .floor8BGM: "bgm-floor8-void-pulse"
        case .battleDefeat: "sfx-battle-defeat"
        case .battleVictory: "sfx-battle-victory"
        case .managerAttack: "sfx-manager-attack"
        case .managerHit: "sfx-manager-hit"
        case .playerHit: "sfx-player-hit"
        case .playerSpellCast: "sfx-player-spell-cast"
        case .uiBack: "sfx-ui-back"
        case .uiConfirm: "sfx-ui-confirm"
        case .uiError: "sfx-ui-error"
        case .uiSelect: "sfx-ui-select"
        case .barrierActivate: "sfx-barrier-activate"
        case .barrierBreak: "sfx-barrier-break"
        case .barrierBroken: "sfx-barrier-broken"
        case .floorTransition: "sfx-floor-transition"
        case .recordOpen: "sfx-record-open"
        }
    }

    var fileExtension: String {
        switch self {
        case .uiBack, .uiConfirm, .uiError, .uiSelect: "wav"
        default: "mp3"
        }
    }

    var shouldPreload: Bool {
        switch self {
        case .floor10BGM, .floor9BGM, .floor8BGM, .battleDefeat, .battleVictory:
            false
        default:
            true
        }
    }
}

private struct EffectPlayback {
    let asset: GameAudioAsset
    var volume: Float = 1
    var rate: Float = 1
}

@MainActor
final class GameFeedbackManager: ObservableObject {
    private let mapper = GameFeedbackMapper()
    private var effectPlayers: [GameAudioAsset: [AVAudioPlayer]] = [:]
    private var missingResources: Set<GameAudioAsset> = []
    private var musicPlayer: AVAudioPlayer?
    private var currentMusicTrack: GameMusicTrack?
    private var requestedMusicTrack: GameMusicTrack?
    private var outcomePlayer: AVAudioPlayer?
    private var outcomeAsset: GameAudioAsset?
    private var outcomeCompletionTask: Task<Void, Never>?
    private var musicFadeTask: Task<Void, Never>?
    private var currentSettings = GameSettings.defaults
    private var isAudioSessionConfigured = false

    private let floorMusicVolume: Float = 0.42
    private let duckedFloorMusicVolume: Float = 0.08
    private let musicTransitionDuration = 1.8
    private let effectPoolLimit = 4

    init() {
        preloadEffects()
    }

    func apply(settings: GameSettings) {
        currentSettings = settings

        if settings.musicEnabled {
            resumeRequestedMusicIfNeeded()
        } else {
            musicFadeTask?.cancel()
            musicPlayer?.stop()
            outcomePlayer?.stop()
        }

        if !settings.soundEffectsEnabled {
            effectPlayers.values.flatMap { $0 }.forEach { $0.stop() }
        }
    }

    func synchronizeFloorMusic(
        floor: FloorID,
        isPresentationReady: Bool,
        keepsOutcomeMusic: Bool,
        settings: GameSettings
    ) {
        currentSettings = settings
        requestedMusicTrack = GameMusicTrack(floor: floor)

        guard settings.musicEnabled else {
            musicPlayer?.stop()
            outcomePlayer?.stop()
            return
        }

        guard isPresentationReady else {
            fadeOutFloorMusic(duration: 0.35)
            return
        }

        if !keepsOutcomeMusic {
            stopOutcomeMusic(restoreFloorMusic: false)
        }
        guard outcomePlayer?.isPlaying != true else { return }
        resumeRequestedMusicIfNeeded()
    }

    func suspendMusicForLoading() {
        fadeOutFloorMusic(duration: 0.25)
    }

    func stopAllAudio() {
        requestedMusicTrack = nil
        currentMusicTrack = nil
        musicFadeTask?.cancel()
        outcomeCompletionTask?.cancel()
        musicPlayer?.stop()
        outcomePlayer?.stop()
        musicPlayer = nil
        outcomePlayer = nil
        outcomeAsset = nil
        effectPlayers.values.flatMap { $0 }.forEach { $0.stop() }
    }

    func consume(_ events: [DemoSessionEvent], settings: GameSettings) {
        currentSettings = settings
        let cues = mapper.cues(for: events)
        guard !cues.isEmpty else { return }

        if events.contains(where: isBattleRestartEvent) {
            stopOutcomeMusic(restoreFloorMusic: false)
        }

        for cue in cues {
            trigger(cue, settings: settings)
        }
    }

    func trigger(
        _ cue: GameFeedbackCue,
        settings: GameSettings,
        includesHaptic: Bool = true
    ) {
        currentSettings = settings

        if settings.soundEffectsEnabled {
            if cue == .victory {
                playOutcome(.battleVictory)
            } else if cue == .defeat {
                playOutcome(.battleDefeat)
            } else {
                playSequence(effectSequence(for: cue))
            }
        }

        if includesHaptic, settings.hapticsEnabled {
            playHaptic(for: cue)
        }
    }

    func playInterface(_ sound: GameInterfaceSound, settings: GameSettings) {
        currentSettings = settings
        guard settings.soundEffectsEnabled else { return }

        let asset: GameAudioAsset = switch sound {
        case .select: .uiSelect
        case .confirm: .uiConfirm
        case .back: .uiBack
        case .error: .uiError
        }
        playEffect(EffectPlayback(asset: asset))
    }

    private func effectSequence(for cue: GameFeedbackCue) -> [EffectPlayback] {
        switch cue {
        case .spellAccepted:
            [EffectPlayback(asset: .playerSpellCast)]
        case .spellRejected, .descentSealRejected:
            [EffectPlayback(asset: .uiError)]
        case .enemyAttack:
            [EffectPlayback(asset: .managerAttack)]
        case .enemyDamaged:
            [EffectPlayback(asset: .managerHit)]
        case .playerDamaged:
            [EffectPlayback(asset: .playerHit)]
        case .barrierDamaged, .absoluteBarrierNegated:
            [EffectPlayback(asset: .barrierBreak)]
        case .barrierBroken, .barrierDispelled:
            [EffectPlayback(asset: .barrierBroken)]
        case let .barrierApplied(isAbsolute):
            [EffectPlayback(
                asset: .barrierActivate,
                volume: isAbsolute ? 1 : 0.9,
                rate: isAbsolute ? 1.08 : 1
            )]
        case .recordOpened:
            [EffectPlayback(asset: .recordOpen)]
        case .rewardSelected, .descentSealStageCompleted:
            [EffectPlayback(asset: .uiConfirm)]
        case .floorTransition:
            [EffectPlayback(asset: .floorTransition)]
        case .victory, .defeat:
            []
        }
    }

    private func playSequence(_ sequence: [EffectPlayback]) {
        guard !sequence.isEmpty else { return }

        Task { @MainActor [weak self] in
            for (index, playback) in sequence.enumerated() {
                guard let self else { return }
                if index > 0 {
                    try? await Task.sleep(for: .milliseconds(90))
                }
                playEffect(playback)
            }
        }
    }

    private func playEffect(_ playback: EffectPlayback) {
        guard !missingResources.contains(playback.asset) else { return }
        configureAudioSessionIfNeeded()

        var pool = effectPlayers[playback.asset] ?? []
        let player: AVAudioPlayer

        if let available = pool.first(where: { !$0.isPlaying }) {
            player = available
        } else if pool.count < effectPoolLimit,
                  let created = makePlayer(for: playback.asset) {
            pool.append(created)
            effectPlayers[playback.asset] = pool
            player = created
        } else if let reusable = pool.min(by: { $0.currentTime < $1.currentTime }) {
            player = reusable
        } else {
            return
        }

        player.enableRate = true
        player.rate = playback.rate
        player.volume = playback.volume
        player.currentTime = 0
        player.play()
    }

    private func playOutcome(_ asset: GameAudioAsset) {
        guard currentSettings.soundEffectsEnabled else { return }
        if outcomeAsset == asset, outcomePlayer?.isPlaying == true { return }

        stopOutcomeMusic(restoreFloorMusic: false)
        fadeMusicPlayer(to: duckedFloorMusicVolume, duration: 0.35)

        guard let player = makePlayer(for: asset) else { return }
        player.volume = 0.82
        player.prepareToPlay()
        outcomeAsset = asset
        outcomePlayer = player
        player.play()

        let duration = max(player.duration, 0.1)
        outcomeCompletionTask = Task { @MainActor [weak self, weak player] in
            try? await Task.sleep(for: .seconds(duration))
            guard let self, let player, outcomePlayer === player else { return }
            outcomePlayer = nil
            outcomeAsset = nil
            resumeRequestedMusicIfNeeded()
        }
    }

    private func stopOutcomeMusic(restoreFloorMusic: Bool) {
        outcomeCompletionTask?.cancel()
        outcomeCompletionTask = nil
        outcomePlayer?.stop()
        outcomePlayer = nil
        outcomeAsset = nil

        if restoreFloorMusic {
            resumeRequestedMusicIfNeeded()
        }
    }

    private func resumeRequestedMusicIfNeeded() {
        guard currentSettings.musicEnabled,
              outcomePlayer?.isPlaying != true,
              let requestedMusicTrack else { return }

        if currentMusicTrack == requestedMusicTrack,
           let musicPlayer {
            if !musicPlayer.isPlaying {
                musicPlayer.play()
            }
            fadeMusicPlayer(to: floorMusicVolume, duration: 0.45)
            return
        }

        transitionFloorMusic(to: requestedMusicTrack)
    }

    private func transitionFloorMusic(to track: GameMusicTrack) {
        guard let nextPlayer = makePlayer(for: track.asset) else { return }
        nextPlayer.numberOfLoops = -1
        nextPlayer.volume = 0
        nextPlayer.prepareToPlay()
        nextPlayer.play()

        let previousPlayer = musicPlayer
        musicPlayer = nextPlayer
        currentMusicTrack = track

        musicFadeTask?.cancel()
        musicFadeTask = Task { @MainActor [weak self, weak previousPlayer, weak nextPlayer] in
            guard let self, let nextPlayer else { return }
            let steps = 36
            for step in 1...steps {
                guard !Task.isCancelled else { return }
                let progress = Float(step) / Float(steps)
                nextPlayer.volume = floorMusicVolume * progress
                previousPlayer?.volume = floorMusicVolume * (1 - progress)
                try? await Task.sleep(for: .milliseconds(50))
            }
            previousPlayer?.stop()
        }
    }

    private func fadeOutFloorMusic(duration: TimeInterval) {
        guard let musicPlayer, musicPlayer.isPlaying else { return }
        fadeMusicPlayer(to: 0, duration: duration, stopsAtZero: true)
    }

    private func fadeMusicPlayer(
        to targetVolume: Float,
        duration: TimeInterval,
        stopsAtZero: Bool = false
    ) {
        guard let musicPlayer else { return }
        let startVolume = musicPlayer.volume
        let steps = max(Int(duration / 0.05), 1)

        musicFadeTask?.cancel()
        musicFadeTask = Task { @MainActor [weak musicPlayer] in
            guard let musicPlayer else { return }
            for step in 1...steps {
                guard !Task.isCancelled else { return }
                let progress = Float(step) / Float(steps)
                musicPlayer.volume = startVolume + ((targetVolume - startVolume) * progress)
                try? await Task.sleep(for: .milliseconds(50))
            }
            if stopsAtZero, targetVolume == 0 {
                musicPlayer.stop()
            }
        }
    }

    private func preloadEffects() {
        for asset in GameAudioAsset.allCases where asset.shouldPreload {
            guard let player = makePlayer(for: asset) else { continue }
            player.prepareToPlay()
            effectPlayers[asset] = [player]
        }
    }

    private func makePlayer(for asset: GameAudioAsset) -> AVAudioPlayer? {
        guard !missingResources.contains(asset) else { return nil }
        guard let url = Bundle.main.url(
            forResource: asset.resourceName,
            withExtension: asset.fileExtension,
            subdirectory: "Audio"
        ) else {
            missingResources.insert(asset)
            return nil
        }

        configureAudioSessionIfNeeded()
        guard let player = try? AVAudioPlayer(contentsOf: url) else {
            missingResources.insert(asset)
            return nil
        }
        return player
    }

    private func configureAudioSessionIfNeeded() {
        guard !isAudioSessionConfigured else { return }
        isAudioSessionConfigured = true
        try? AVAudioSession.sharedInstance().setCategory(
            .ambient,
            mode: .default,
            options: [.mixWithOthers]
        )
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private func isBattleRestartEvent(_ event: DemoSessionEvent) -> Bool {
        switch event {
        case .encounterStarted:
            true
        default:
            false
        }
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
        case .enemyAttack, .recordOpened, .floorTransition:
            break
        case .enemyDamaged:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.75)
        case let .playerDamaged(strong):
            UIImpactFeedbackGenerator(style: strong ? .heavy : .rigid)
                .impactOccurred(intensity: strong ? 1 : 0.75)
        case let .barrierDamaged(strong), let .barrierBroken(strong):
            UIImpactFeedbackGenerator(style: strong ? .rigid : .soft)
                .impactOccurred(intensity: strong ? 0.9 : 0.65)
        case .barrierApplied:
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.7)
        case .absoluteBarrierNegated, .barrierDispelled:
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 1)
        case .victory, .rewardSelected:
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
}
