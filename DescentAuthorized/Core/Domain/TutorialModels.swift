import Foundation

enum TutorialSequenceID: String, Codable, CaseIterable, Hashable, Sendable {
    case floor10Intro
    case floor10Investigation
    case afterglowDiscovery
    case riftDiscovery
    case floor10DescentSeal
    case recordsBattleBasics

    // riftDiscovery는 기존 저장 데이터 복원을 위해 enum에는 남기되,
    // 새 튜토리얼 목록에서는 최초 두루마리 학습 안내로 통합한다.
    static let allCases: [TutorialSequenceID] = [
        .floor10Intro,
        .floor10Investigation,
        .afterglowDiscovery,
        .floor10DescentSeal,
        .recordsBattleBasics
    ]
}

enum TutorialStepID: String, Codable, CaseIterable, Hashable, Sendable {
    case terminalBoot
    case awaken
    case rise
    case surveyTarget
    case surveyDesk
    case surveyDamage
    case surveyDoor
    case explorationControls
    case investigationMarkers
    case afterglowInspect
    case afterglowTraining
    case riftInspect
    case riftTraining
    case descentRecord
    case descentInput
    case descentInformation
    case descentReset
    case battlePlayerHP
    case battleTurnAndEnemyHP
    case battleIntent
    case battleResourcesAndSpells
    case battleInput
    case battleLogAndEndTurn
}

enum TutorialMechanicID: String, Codable, CaseIterable, Hashable, Sendable {
    case afterglowDrawing
    case riftDrawing
    case descentSeal
    case recordsBattle
}

struct TutorialProgress: Codable, Equatable, Sendable {
    var completedSequences: Set<TutorialSequenceID>
    var skippedSequences: Set<TutorialSequenceID>
    var completedSteps: Set<TutorialStepID>
    var activeSequence: TutorialSequenceID?
    var activeStep: TutorialStepID?
    var failureCounts: [TutorialMechanicID: Int]
    var requestedReplay: TutorialSequenceID?

    static let empty = TutorialProgress()

    init(
        completedSequences: Set<TutorialSequenceID> = [],
        skippedSequences: Set<TutorialSequenceID> = [],
        completedSteps: Set<TutorialStepID> = [],
        activeSequence: TutorialSequenceID? = nil,
        activeStep: TutorialStepID? = nil,
        failureCounts: [TutorialMechanicID: Int] = [:],
        requestedReplay: TutorialSequenceID? = nil
    ) {
        self.completedSequences = completedSequences
        self.skippedSequences = skippedSequences
        self.completedSteps = completedSteps
        self.activeSequence = activeSequence
        self.activeStep = activeStep
        self.failureCounts = failureCounts
        self.requestedReplay = requestedReplay
    }

    func shouldPresent(_ sequence: TutorialSequenceID) -> Bool {
        requestedReplay == sequence
            || (!completedSequences.contains(sequence) && !skippedSequences.contains(sequence))
    }

    func failureCount(for mechanic: TutorialMechanicID) -> Int {
        failureCounts[mechanic, default: 0]
    }

    mutating func begin(_ sequence: TutorialSequenceID, at step: TutorialStepID) {
        activeSequence = sequence
        activeStep = step
    }

    mutating func completeStep(_ step: TutorialStepID, next: TutorialStepID? = nil) {
        completedSteps.insert(step)
        activeStep = next
    }

    mutating func complete(_ sequence: TutorialSequenceID) {
        completedSequences.insert(sequence)
        skippedSequences.remove(sequence)
        if activeSequence == sequence {
            activeSequence = nil
            activeStep = nil
        }
        if requestedReplay == sequence {
            requestedReplay = nil
        }
    }

    mutating func skip(_ sequence: TutorialSequenceID) {
        skippedSequences.insert(sequence)
        if activeSequence == sequence {
            activeSequence = nil
            activeStep = nil
        }
        if requestedReplay == sequence {
            requestedReplay = nil
        }
    }

    @discardableResult
    mutating func recordFailure(_ mechanic: TutorialMechanicID) -> Int {
        let count = failureCounts[mechanic, default: 0] + 1
        failureCounts[mechanic] = count
        return count
    }

    mutating func requestReplay(_ sequence: TutorialSequenceID) {
        requestedReplay = sequence
        activeSequence = nil
        activeStep = nil
    }

    mutating func reset() {
        self = .empty
    }

    static func migratedLegacy(
        floor: FloorID,
        scene: SceneID,
        checkpoint: CheckpointID,
        learnedSpells: Set<SpellID>,
        legacyFlags: Set<TutorialFlag>
    ) -> TutorialProgress {
        var migrated = TutorialProgress.empty

        if scene != .floor10MeetingRoom || floor != .floor10 {
            migrated.completedSequences.insert(.floor10Intro)
        }
        if learnedSpells.contains(.afterglowErasure) || floor != .floor10 {
            migrated.completedSequences.formUnion([.floor10Investigation, .afterglowDiscovery])
        }
        if learnedSpells.contains(.riftSeverance) || floor != .floor10 {
            migrated.completedSequences.insert(.riftDiscovery)
        }
        if floor != .floor10 {
            migrated.completedSequences.insert(.floor10DescentSeal)
        }
        if checkpoint != .floor10Start
            && legacyFlags.isSuperset(of: [.hp, .mana, .enemyIntent]) {
            migrated.completedSequences.insert(.recordsBattleBasics)
        }

        return migrated
    }
}
