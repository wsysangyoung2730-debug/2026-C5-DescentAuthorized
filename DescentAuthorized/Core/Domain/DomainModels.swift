import Foundation

// MARK: - Glyph domain

struct NormalizedPoint: Codable, Hashable, Sendable {
    let x: Double
    let y: Double

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    func distance(to other: NormalizedPoint) -> Double {
        hypot(other.x - x, other.y - y)
    }
}

struct NormalizedRect: Codable, Hashable, Sendable {
    let minX: Double
    let minY: Double
    let maxX: Double
    let maxY: Double

    init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
        precondition(minX <= maxX && minY <= maxY)
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
    }

    func contains(_ point: NormalizedPoint) -> Bool {
        point.x >= minX && point.x <= maxX && point.y >= minY && point.y <= maxY
    }
}

enum DrawingInputMethod: String, Codable, Sendable {
    case pencil
    case finger
}

struct DrawnStroke: Codable, Equatable, Sendable {
    let points: [NormalizedPoint]
    let duration: TimeInterval?

    init(points: [NormalizedPoint], duration: TimeInterval? = nil) {
        self.points = points
        self.duration = duration
    }
}

struct ErasureZone: Codable, Hashable, Sendable {
    let id: String
    let bounds: NormalizedRect
    let manaMultiplier: Double

    init(id: String, bounds: NormalizedRect, manaMultiplier: Double = 1.75) {
        self.id = id
        self.bounds = bounds
        self.manaMultiplier = manaMultiplier
    }
}

enum GlyphDifficulty: String, Codable, Sendable {
    case easy
    case normal
    case hard
}

struct GlyphStrokeSpec: Codable, Equatable, Sendable {
    let start: NormalizedPoint
    let end: NormalizedPoint
    let requiredNodes: [NormalizedPoint]
    let optionalNodes: [NormalizedPoint]
    let referencePath: [NormalizedPoint]
    let nodeRadius: Double
    let pathRadius: Double
    let optionalNodeGradeCap: CastingGrade?

    init(
        start: NormalizedPoint,
        end: NormalizedPoint,
        requiredNodes: [NormalizedPoint],
        optionalNodes: [NormalizedPoint] = [],
        referencePath: [NormalizedPoint],
        nodeRadius: Double,
        pathRadius: Double,
        optionalNodeGradeCap: CastingGrade? = nil
    ) {
        precondition(referencePath.count >= 2)
        self.start = start
        self.end = end
        self.requiredNodes = requiredNodes
        self.optionalNodes = optionalNodes
        self.referencePath = referencePath
        self.nodeRadius = nodeRadius
        self.pathRadius = pathRadius
        self.optionalNodeGradeCap = optionalNodeGradeCap
    }
}

struct GlyphCrossingRequirement: Codable, Equatable, Sendable {
    let firstStrokeIndex: Int
    let secondStrokeIndex: Int
    let center: NormalizedPoint
    let radius: Double
}

struct GlyphDefinition: Codable, Equatable, Sendable {
    let difficulty: GlyphDifficulty
    let strokes: [GlyphStrokeSpec]
    let crossings: [GlyphCrossingRequirement]

    var requiredStrokeCount: Int { strokes.count }
}

enum CastingGrade: String, Codable, CaseIterable, Comparable, Sendable {
    case rejected
    case incomplete
    case approved
    case precise
    case perfect

    static func < (lhs: CastingGrade, rhs: CastingGrade) -> Bool {
        let order = Self.allCases
        return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
    }
}

enum CastingFailure: String, Codable, Equatable, Sendable {
    case noInput
    case wrongStrokeCount
    case invalidStart
    case missingRequiredNode
    case invalidEnd
    case missingCrossing
    case manaDepleted
    case incompleteGlyph
}

struct CastingScoreBreakdown: Codable, Equatable, Sendable {
    let nodes: Double
    let path: Double
    let structure: Double
    let manaEfficiency: Double
    let speed: Double
}

struct CastingEvaluation: Codable, Equatable, Sendable {
    let score: Double
    let grade: CastingGrade
    let failure: CastingFailure?
    let manaUsed: Double
    let manaUsedInErasureZones: Double
    let passedRequiredNodeCount: Int
    let requiredNodeCount: Int
    let breakdown: CastingScoreBreakdown
    let effectStrength: Double

    var succeeded: Bool { grade != .rejected }
}

// MARK: - Spell domain

enum SpellID: String, Codable, CaseIterable, Sendable {
    case afterglowErasure
    case riftSeverance
    case barrierPiercing
    case basicBarrier
    case sealRelease
}

enum SpellCategory: String, Codable, Sendable {
    case attack
    case defense
    case dispel
}

enum ScrollTier: String, Codable, Sendable {
    case worn
    case engraved
    case sealed
    case forbidden
}

enum SpellEffect: Codable, Equatable, Sendable {
    case damage(minimum: Int, maximum: Int, piercesNormalBarrier: Bool)
    case fixedBarrier(minimum: Int, maximum: Int, maxStack: Int)
    case dispelAbsoluteBarrier(minimumCharges: Int, maximumCharges: Int)

    var range: ClosedRange<Int> {
        switch self {
        case let .damage(minimum, maximum, _),
             let .fixedBarrier(minimum, maximum, _):
            minimum...maximum
        case let .dispelAbsoluteBarrier(minimumCharges, maximumCharges):
            minimumCharges...maximumCharges
        }
    }
}

struct SpellDefinition: Codable, Equatable, Sendable {
    let id: SpellID
    let name: String
    let category: SpellCategory
    let tier: ScrollTier
    let recommendedMana: Double
    let effect: SpellEffect
    let glyph: GlyphDefinition

    var requiredStrokes: Int { glyph.requiredStrokeCount }
}

enum DescentDoorGlyphID: String, Codable, CaseIterable, Sendable {
    case floor10
    case floor9
    case floor8
}

struct DescentDoorGlyphDefinition: Codable, Equatable, Sendable {
    let id: DescentDoorGlyphID
    let name: String
    let recommendedMana: Double
    let glyph: GlyphDefinition

    var requiredStrokes: Int { glyph.requiredStrokeCount }
}

// MARK: - Combat domain

enum CombatantID: Codable, Hashable, Sendable {
    case player
    case enemy(EnemyID)
}

struct CombatantState: Codable, Equatable, Sendable {
    let id: CombatantID
    let name: String
    let maxHP: Int
    var hp: Int
    var normalBarrier: Int
    var absoluteBarrierCharges: Int

    init(
        id: CombatantID,
        name: String,
        maxHP: Int,
        hp: Int? = nil,
        normalBarrier: Int = 0,
        absoluteBarrierCharges: Int = 0
    ) {
        precondition(maxHP > 0)
        self.id = id
        self.name = name
        self.maxHP = maxHP
        self.hp = min(max(hp ?? maxHP, 0), maxHP)
        self.normalBarrier = max(normalBarrier, 0)
        self.absoluteBarrierCharges = max(absoluteBarrierCharges, 0)
    }

    var isDefeated: Bool { hp <= 0 }
    var hpFraction: Double { Double(hp) / Double(maxHP) }
}

struct TurnResources: Codable, Equatable, Sendable {
    let maximumMana: Double
    let maximumStrokes: Int
    var remainingMana: Double
    var remainingStrokes: Int

    static let demoDefault = TurnResources(
        maximumMana: 100,
        maximumStrokes: 2,
        remainingMana: 100,
        remainingStrokes: 2
    )

    mutating func reset() {
        remainingMana = maximumMana
        remainingStrokes = maximumStrokes
    }
}

enum BattlePhase: String, Codable, Sendable {
    case preparing
    case playerTurn
    case resolvingPlayerSpell
    case resolvingEnemyAction
    case victory
    case defeat
}

enum EnemyID: String, Codable, CaseIterable, Sendable {
    case recordsAdministrator
    case observationResidual
    case observationAdministrator
}

enum EnemyAction: Codable, Equatable, Sendable {
    case attack(name: String, damage: Int, isStrong: Bool)
    case grantNormalBarrier(name: String, amount: Int)
    case grantAbsoluteBarrier(name: String, charges: Int)
    case telegraph(name: String, upcomingActionName: String)

    var name: String {
        switch self {
        case let .attack(name, _, _),
             let .grantNormalBarrier(name, _),
             let .grantAbsoluteBarrier(name, _),
             let .telegraph(name, _):
            name
        }
    }
}

enum EnemyThresholdEffect: Codable, Equatable, Sendable {
    case addErasureZone(ErasureZone)
    case grantAbsoluteBarrier(charges: Int)
}

struct EnemyThresholdRule: Codable, Equatable, Sendable {
    let id: String
    let hpFraction: Double
    let effect: EnemyThresholdEffect
}

struct EnemyDefinition: Codable, Equatable, Sendable {
    let id: EnemyID
    let name: String
    let maxHP: Int
    let startingAbsoluteBarrierCharges: Int
    let pattern: [EnemyAction]
    let thresholdRules: [EnemyThresholdRule]
}

enum BattleEvent: Equatable, Sendable {
    case battleStarted(enemy: EnemyID)
    case turnStarted(number: Int, intent: EnemyAction)
    case spellResolved(spell: SpellID, grade: CastingGrade)
    case spellRejected(spell: SpellID, reason: CastingFailure)
    case resourcesChanged(mana: Double, strokes: Int)
    case damageApplied(target: CombatantID, amount: Int, remainingHP: Int)
    case normalBarrierChanged(target: CombatantID, amount: Int)
    case absoluteBarrierChanged(target: CombatantID, charges: Int)
    case attackNegatedByAbsoluteBarrier(target: CombatantID)
    case erasureZoneAdded(ErasureZone)
    case enemyActionStarted(EnemyAction)
    case enemyActionCancelled
    case victory(EnemyID)
    case defeat
}

// MARK: - Progression domain

enum FloorID: Int, Codable, CaseIterable, Sendable {
    case floor10 = 10
    case floor9 = 9
    case floor8 = 8
    case floor7 = 7
}

enum SceneID: String, Codable, Sendable {
    case floor10MeetingRoom
    case floor10Office
    case floor10GlyphArchive
    case floor10TrainingWall
    case floor10DescentDoor
    case floor9Entrance
    case floor9RecordsEncounter
    case floor9RecordsBattle
    case floor9RecordsDefeated
    case floor9RewardVault
    case floor9DescentDoor
    case floor8Antechamber
    case floor8ProtectionRoom
    case floor8ResidualEncounter
    case floor8ResidualBattle
    case floor8ResidualDefeated
    case floor8SealedDoor
    case floor8AdministratorEncounter
    case floor8AdministratorBattle
    case floor8AdministratorDefeated
    case floor8Reward
    case floor8DescentDoor
    case demoComplete
}

enum CheckpointID: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case floor10Start
    case floor10Complete
    case recordsBattle
    case recordsDefeated
    case floor8Start
    case residualBattle
    case residualDefeated
    case observationBattle
    case observationDefeated
    case demoComplete

    var progressionIndex: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }
}

enum TutorialFlag: String, Codable, Hashable, Sendable {
    case cardSelection
    case drawing
    case mana
    case strokeCount
    case enemyIntent
    case hp
    case normalBarrier
    case erasureZone
    case rewardSelection
    case defense
    case strongAttack
    case absoluteBarrier
    case dispel
}

struct RewardCandidate: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let obscuredName: String
    let category: SpellCategory
    let tier: ScrollTier
    let resolvedSpell: SpellID?
}

struct SpellMastery: Codable, Equatable, Sendable {
    var bestGrade: CastingGrade
    var successfulCasts: Int
}

struct GameProgress: Codable, Equatable, Sendable {
    static let currentSaveVersion = 3

    var saveVersion: Int
    var currentFloor: FloorID
    var currentScene: SceneID
    var checkpoint: CheckpointID
    var furthestCheckpoint: CheckpointID
    var playerHP: Int
    var learnedSpells: Set<SpellID>
    var defeatedEnemies: Set<EnemyID>
    var readRecordIDs: Set<String>
    var tutorials: Set<TutorialFlag>
    var tutorialProgress: TutorialProgress
    var spellMastery: [SpellID: SpellMastery]
    var completedTrainingSpells: Set<SpellID>
    var selectedRewardIDs: [String]
    var isDemoComplete: Bool

    init(
        saveVersion: Int,
        currentFloor: FloorID,
        currentScene: SceneID,
        checkpoint: CheckpointID,
        furthestCheckpoint: CheckpointID? = nil,
        playerHP: Int,
        learnedSpells: Set<SpellID>,
        defeatedEnemies: Set<EnemyID>,
        readRecordIDs: Set<String>,
        tutorials: Set<TutorialFlag>,
        tutorialProgress: TutorialProgress = .empty,
        spellMastery: [SpellID: SpellMastery],
        completedTrainingSpells: Set<SpellID>,
        selectedRewardIDs: [String],
        isDemoComplete: Bool
    ) {
        self.saveVersion = saveVersion
        self.currentFloor = currentFloor
        self.currentScene = currentScene
        self.checkpoint = checkpoint
        self.furthestCheckpoint = furthestCheckpoint ?? checkpoint
        self.playerHP = playerHP
        self.learnedSpells = learnedSpells
        self.defeatedEnemies = defeatedEnemies
        self.readRecordIDs = readRecordIDs
        self.tutorials = tutorials
        self.tutorialProgress = tutorialProgress
        self.spellMastery = spellMastery
        self.completedTrainingSpells = completedTrainingSpells
        self.selectedRewardIDs = selectedRewardIDs
        self.isDemoComplete = isDemoComplete
    }

    static let newGame = GameProgress(
        saveVersion: currentSaveVersion,
        currentFloor: .floor10,
        currentScene: .floor10MeetingRoom,
        checkpoint: .floor10Start,
        playerHP: 100,
        learnedSpells: [],
        defeatedEnemies: [],
        readRecordIDs: [],
        tutorials: [],
        tutorialProgress: .empty,
        spellMastery: [:],
        completedTrainingSpells: [],
        selectedRewardIDs: [],
        isDemoComplete: false
    )

    private enum CodingKeys: String, CodingKey {
        case saveVersion
        case currentFloor
        case currentScene
        case checkpoint
        case furthestCheckpoint
        case playerHP
        case learnedSpells
        case defeatedEnemies
        case readRecordIDs
        case tutorials
        case tutorialProgress
        case spellMastery
        case completedTrainingSpells
        case selectedRewardIDs
        case isDemoComplete
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedVersion = try container.decodeIfPresent(Int.self, forKey: .saveVersion) ?? 1
        currentFloor = try container.decode(FloorID.self, forKey: .currentFloor)
        currentScene = try container.decode(SceneID.self, forKey: .currentScene)
        checkpoint = try container.decode(CheckpointID.self, forKey: .checkpoint)
        furthestCheckpoint = try container.decodeIfPresent(
            CheckpointID.self,
            forKey: .furthestCheckpoint
        ) ?? checkpoint
        playerHP = try container.decode(Int.self, forKey: .playerHP)
        learnedSpells = try container.decodeIfPresent(Set<SpellID>.self, forKey: .learnedSpells) ?? []
        defeatedEnemies = try container.decodeIfPresent(Set<EnemyID>.self, forKey: .defeatedEnemies) ?? []
        readRecordIDs = try container.decodeIfPresent(Set<String>.self, forKey: .readRecordIDs) ?? []
        tutorials = try container.decodeIfPresent(Set<TutorialFlag>.self, forKey: .tutorials) ?? []
        spellMastery = try container.decodeIfPresent(
            [SpellID: SpellMastery].self,
            forKey: .spellMastery
        ) ?? [:]
        completedTrainingSpells = try container.decodeIfPresent(
            Set<SpellID>.self,
            forKey: .completedTrainingSpells
        ) ?? []
        selectedRewardIDs = try container.decodeIfPresent([String].self, forKey: .selectedRewardIDs) ?? []
        isDemoComplete = try container.decodeIfPresent(Bool.self, forKey: .isDemoComplete) ?? false

        if let decodedProgress = try container.decodeIfPresent(
            TutorialProgress.self,
            forKey: .tutorialProgress
        ) {
            tutorialProgress = decodedProgress
        } else {
            tutorialProgress = .migratedLegacy(
                floor: currentFloor,
                scene: currentScene,
                checkpoint: checkpoint,
                learnedSpells: learnedSpells,
                legacyFlags: tutorials
            )
        }
        saveVersion = max(decodedVersion, Self.currentSaveVersion)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentSaveVersion, forKey: .saveVersion)
        try container.encode(currentFloor, forKey: .currentFloor)
        try container.encode(currentScene, forKey: .currentScene)
        try container.encode(checkpoint, forKey: .checkpoint)
        try container.encode(furthestCheckpoint, forKey: .furthestCheckpoint)
        try container.encode(playerHP, forKey: .playerHP)
        try container.encode(learnedSpells, forKey: .learnedSpells)
        try container.encode(defeatedEnemies, forKey: .defeatedEnemies)
        try container.encode(readRecordIDs, forKey: .readRecordIDs)
        try container.encode(tutorials, forKey: .tutorials)
        try container.encode(tutorialProgress, forKey: .tutorialProgress)
        try container.encode(spellMastery, forKey: .spellMastery)
        try container.encode(completedTrainingSpells, forKey: .completedTrainingSpells)
        try container.encode(selectedRewardIDs, forKey: .selectedRewardIDs)
        try container.encode(isDemoComplete, forKey: .isDemoComplete)
    }
}
