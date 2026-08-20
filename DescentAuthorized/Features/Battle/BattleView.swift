import SwiftUI

struct BattleView: View {
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var gameSession: GameSessionStore

    @State private var selectedSpellID: SpellID?
    @State private var enemyHitFlash = false
    @State private var playerHitFlash = false
    @State private var strongAttackFlash = false
    @State private var feedbackText: String?
    @State private var feedbackColor = Color.white
    @State private var showsFirstTurnBriefing = false
    @State private var didExperienceAbsoluteBarrier = false
    @State private var enemyPulseTask: Task<Void, Never>?
    @State private var playerPulseTask: Task<Void, Never>?
    @State private var feedbackTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            battleBackground

            if let battle = gameSession.battleState {
                battleContent(battle)
            } else {
                encounterStandby
            }

            Color.red
                .opacity(playerHitFlash ? (appSettings.reducedFlashes ? 0.08 : 0.24) : 0)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            if strongAttackFlash && !appSettings.reducedFlashes {
                Rectangle()
                    .stroke(Color.red.opacity(0.85), lineWidth: 8)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            if let feedbackText {
                castFeedback(text: feedbackText, color: feedbackColor)
                    .transition(.scale.combined(with: .opacity))
                    .allowsHitTesting(false)
            }

            if showsFirstTurnBriefing {
                battleBriefing
                    .transition(.opacity)
            }

            if gameSession.battleState?.phase == .defeat {
                defeatOverlay
            }
        }
        .task(id: gameSession.progress.currentScene) {
            startEncounterIfNeeded()
            selectAvailableSpell()
            if shouldShowFirstTurnBriefing,
               gameSession.battleState?.turnNumber == 1 {
                showsFirstTurnBriefing = true
            }
        }
        .onChange(of: gameSession.eventSequence) { _, _ in
            present(gameSession.latestEvents)
            selectAvailableSpell()
            autoFinishPlayerTurnIfNeeded()
        }
        .onDisappear {
            enemyPulseTask?.cancel()
            playerPulseTask?.cancel()
            feedbackTask?.cancel()
        }
        .preferredColorScheme(.dark)
    }

    private func battleContent(_ battle: BattleState) -> some View {
        GeometryReader { proxy in
            VStack(spacing: 10) {
                combatHeader(battle)
                    .frame(height: 54)

                enemyStage(battle)
                    .frame(height: max(150, proxy.size.height * 0.24))

                if let spell = selectedSpell(in: battle) {
                    GlyphCastingPanel(
                        spell: spell,
                        inputPreference: appSettings.inputPreference,
                        availableMana: battle.resources.remainingMana,
                        availableStrokes: battle.resources.remainingStrokes,
                        erasureZones: battle.activeErasureZones,
                        onCast: { submission in
                            gameSession.send(.castSpell(
                                spell: spell.id,
                                strokes: submission.strokes,
                                inputMethod: submission.inputMethod
                            ))
                        }
                    )
                    .frame(maxWidth: 760, maxHeight: 380)
                    .padding(.horizontal, 20)
                } else {
                    Text("시전할 수 있는 주문이 없습니다")
                        .foregroundStyle(.secondary)
                        .frame(maxHeight: .infinity)
                }

                spellBar(battle)
                    .frame(height: 76)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
        }
    }

    private func combatHeader(_ battle: BattleState) -> some View {
        HStack(spacing: 20) {
            vitalityBlock(
                name: battle.player.name,
                combatant: battle.player,
                accent: .cyan,
                alignment: .leading
            )

            Spacer()

            VStack(spacing: 3) {
                Text("TURN \(battle.turnNumber)")
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(.secondary)
                Text(phaseTitle(battle.phase))
                    .font(.subheadline.weight(.semibold))
            }

            Spacer()

            vitalityBlock(
                name: battle.enemy.name,
                combatant: battle.enemy,
                accent: .red,
                alignment: .trailing
            )
        }
    }

    private func vitalityBlock(
        name: String,
        combatant: CombatantState,
        accent: Color,
        alignment: HorizontalAlignment
    ) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            HStack(spacing: 8) {
                if alignment == .trailing { barrierBadges(combatant) }
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if alignment == .leading { barrierBadges(combatant) }
            }
            ProgressView(value: Double(combatant.hp), total: Double(combatant.maxHP))
                .tint(accent)
                .frame(width: 260)
            Text("\(combatant.hp) / \(combatant.maxHP)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func barrierBadges(_ combatant: CombatantState) -> some View {
        if combatant.normalBarrier > 0 {
            Label("\(combatant.normalBarrier)", systemImage: "shield.fill")
                .font(.caption2.monospacedDigit().weight(.bold))
                .foregroundStyle(.cyan)
        }
        if combatant.absoluteBarrierCharges > 0 {
            Label("\(combatant.absoluteBarrierCharges)", systemImage: "shield.checkered")
                .font(.caption2.monospacedDigit().weight(.bold))
                .foregroundStyle(.yellow)
        }
    }

    private func enemyStage(_ battle: BattleState) -> some View {
        ZStack {
            stageGrid

            VStack(spacing: 8) {
                ZStack {
                    Image(systemName: enemySymbol)
                        .font(.system(size: 104, weight: .thin))
                        .foregroundStyle(Color.purple.opacity(0.18))
                        .offset(x: -7, y: 4)
                    Image(systemName: enemySymbol)
                        .font(.system(size: 104, weight: .thin))
                        .foregroundStyle(.white.opacity(0.82))
                        .shadow(color: .purple.opacity(0.85), radius: enemyHitFlash ? 28 : 12)
                        .scaleEffect(enemyHitFlash ? 1.08 : 1)
                }

                if let intent = battle.currentEnemyIntent {
                    intentLabel(intent)
                }
            }
        }
        .overlay(alignment: .topLeading) {
            Text(floorLabel)
                .font(.caption.monospaced().weight(.bold))
                .foregroundStyle(.secondary)
                .padding(10)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        }
    }

    private func intentLabel(_ intent: EnemyAction) -> some View {
        HStack(spacing: 7) {
            Image(systemName: intentSymbol(intent))
            VStack(alignment: .leading, spacing: 1) {
                Text(intent.name)
                    .font(.caption.weight(.bold))
                Text(intentDetail(intent))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.black.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .foregroundStyle(intentColor(intent))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("적 의도 \(intent.name), \(intentDetail(intent))")
    }

    private func spellBar(_ battle: BattleState) -> some View {
        HStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(availableSpells(in: battle), id: \.id) { spell in
                        spellCard(spell, battle: battle)
                    }
                }
            }

            Divider()
                .frame(height: 48)

            Button {
                gameSession.send(.finishTurn)
            } label: {
                Label("턴 종료", systemImage: "forward.end.fill")
                    .frame(minWidth: 88)
            }
            .buttonStyle(.borderedProminent)
            .tint(.gray.opacity(0.7))
            .disabled(battle.phase != .playerTurn)
        }
    }

    private func spellCard(_ spell: SpellDefinition, battle: BattleState) -> some View {
        let isSelected = selectedSpellID == spell.id
        let isAffordable = spell.requiredStrokes <= battle.resources.remainingStrokes
        let isPermitted = isSpellPermitted(spell, battle: battle)

        return Button {
            selectedSpellID = spell.id
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Image(systemName: spellSymbol(spell.category))
                    Spacer()
                    Text("\(spell.requiredStrokes)획")
                        .font(.caption2.monospacedDigit())
                }
                Text(spell.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(categoryTitle(spell.category))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            .frame(width: 126, height: 64, alignment: .leading)
            .background(isSelected ? spellColor(spell.category).opacity(0.22) : Color.white.opacity(0.05))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(
                        isSelected ? spellColor(spell.category) : Color.white.opacity(0.1),
                        lineWidth: isSelected ? 2 : 1
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .disabled(!isAffordable || !isPermitted || battle.phase != .playerTurn)
        .opacity(isAffordable && isPermitted ? 1 : 0.4)
        .accessibilityLabel("\(spell.name), \(categoryTitle(spell.category)), \(spell.requiredStrokes)획")
    }

    private var encounterStandby: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text("층 관리자 전투 절차를 준비 중입니다")
                .font(.headline)
            Button("전투 시작") {
                startEncounterIfNeeded()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var battleBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.025, green: 0.03, blue: 0.04),
                Color(red: 0.07, green: 0.035, blue: 0.075),
                Color.black
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var stageGrid: some View {
        Canvas { context, size in
            var path = Path()
            for column in 0...12 {
                let x = size.width * CGFloat(column) / 12
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
            for row in 0...5 {
                let y = size.height * CGFloat(row) / 5
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(path, with: .color(.white.opacity(0.035)), lineWidth: 1)
        }
        .background(Color.black.opacity(0.28))
    }

    private func castFeedback(text: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "seal.fill")
                .font(.title)
            Text(text)
                .font(.title3.weight(.bold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(.black.opacity(0.84))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func startEncounterIfNeeded() {
        guard gameSession.battleState == nil, isBattleScene else { return }
        gameSession.send(.startEncounter)
    }

    private func selectAvailableSpell() {
        guard let battle = gameSession.battleState else {
            selectedSpellID = nil
            return
        }
        if let selectedSpellID,
           battle.learnedSpells.contains(selectedSpellID),
           SpellCatalog.spell(selectedSpellID).requiredStrokes <= battle.resources.remainingStrokes,
           isSpellPermitted(SpellCatalog.spell(selectedSpellID), battle: battle) {
            return
        }
        selectedSpellID = availableSpells(in: battle).first(where: {
            $0.requiredStrokes <= battle.resources.remainingStrokes
                && isSpellPermitted($0, battle: battle)
        })?.id
    }

    private func autoFinishPlayerTurnIfNeeded() {
        guard let battle = gameSession.battleState else { return }
        guard battle.phase == .playerTurn else { return }
        guard availableSpells(in: battle).contains(where: {
            $0.requiredStrokes <= battle.resources.remainingStrokes
                && isSpellPermitted($0, battle: battle)
        }) == false else { return }
        gameSession.send(.finishTurn)
    }

    private func selectedSpell(in battle: BattleState) -> SpellDefinition? {
        guard let selectedSpellID, battle.learnedSpells.contains(selectedSpellID) else {
            return nil
        }
        return SpellCatalog.spell(selectedSpellID)
    }

    private func availableSpells(in battle: BattleState) -> [SpellDefinition] {
        SpellID.allCases
            .filter(battle.learnedSpells.contains)
            .map(SpellCatalog.spell)
    }

    private func present(_ events: [DemoSessionEvent]) {
        var enemyWasHit = false
        var playerWasHit = false
        var strongAttack = false
        var banner: (String, Color)?

        for event in events {
            guard case let .combat(battleEvent) = event else { continue }
            switch battleEvent {
            case let .damageApplied(target, amount, _):
                switch target {
                case .player:
                    playerWasHit = amount > 0
                case .enemy:
                    enemyWasHit = amount > 0
                }
            case let .spellResolved(_, grade):
                banner = (gradeTitle(grade), gradeColor(grade))
            case let .spellRejected(_, reason):
                banner = (failureTitle(reason), .red)
            case .attackNegatedByAbsoluteBarrier:
                banner = ("절대 방벽으로 무효화", .yellow)
                didExperienceAbsoluteBarrier = true
            case let .normalBarrierChanged(target, amount):
                if case .enemy = target, amount > 0 {
                    banner = ("문서 방벽 전개", .cyan)
                }
            case .erasureZoneAdded:
                banner = ("말소 구역 발생", .red)
            case let .enemyActionStarted(action):
                if case let .attack(_, _, isStrong) = action {
                    strongAttack = isStrong
                }
            default:
                break
            }
        }

        if enemyWasHit { pulseEnemy() }
        if playerWasHit { pulsePlayer(strong: strongAttack) }
        if let banner { showFeedback(banner.0, color: banner.1) }
    }

    private func pulseEnemy() {
        enemyPulseTask?.cancel()
        animate(.easeOut(duration: 0.12)) { enemyHitFlash = true }
        enemyPulseTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(260))
            guard !Task.isCancelled else { return }
            animate(.easeIn(duration: 0.2)) { enemyHitFlash = false }
        }
    }

    private func pulsePlayer(strong: Bool) {
        playerPulseTask?.cancel()
        animate(.easeOut(duration: 0.08)) {
            playerHitFlash = true
            strongAttackFlash = strong
        }
        playerPulseTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(strong ? 420 : 260))
            guard !Task.isCancelled else { return }
            animate(.easeIn(duration: 0.2)) {
                playerHitFlash = false
                strongAttackFlash = false
            }
        }
    }

    private func showFeedback(_ text: String, color: Color) {
        feedbackTask?.cancel()
        animate(.spring(response: 0.24)) {
            feedbackText = text
            feedbackColor = color
        }
        feedbackTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            animate(.easeOut(duration: 0.2)) { feedbackText = nil }
        }
    }

    private func animate(
        _ animation: Animation,
        changes: () -> Void
    ) {
        if appSettings.reducedMotion {
            changes()
        } else {
            withAnimation(animation, changes)
        }
    }

    private var isBattleScene: Bool {
        switch gameSession.progress.currentScene {
        case .floor9RecordsBattle, .floor8ResidualBattle, .floor8AdministratorBattle:
            true
        default:
            false
        }
    }

    private var isRecordsBattle: Bool {
        gameSession.progress.currentScene == .floor9RecordsBattle
    }

    private var isResidualBattle: Bool {
        gameSession.progress.currentScene == .floor8ResidualBattle
    }

    private var isObservationBattle: Bool {
        gameSession.progress.currentScene == .floor8AdministratorBattle
    }

    private var shouldShowFirstTurnBriefing: Bool {
        isRecordsBattle || isResidualBattle || isObservationBattle
    }

    @ViewBuilder
    private var battleBriefing: some View {
        if isResidualBattle {
            residualBriefing
        } else if isObservationBattle {
            observationBriefing
        } else {
            firstTurnBriefing
        }
    }

    private var firstTurnBriefing: some View {
        ZStack {
            Color.black.opacity(0.72)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                Label("9층 전투 절차", systemImage: "exclamationmark.shield.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.purple)

                briefingRow(
                    icon: "eye.fill",
                    title: "관리자의 다음 행동을 먼저 확인",
                    detail: "공격이 예고되면 피해를 감수할지, 턴을 어떻게 사용할지 결정한다."
                )
                briefingRow(
                    icon: "scribble.variable",
                    title: "마나는 남은 선의 길이",
                    detail: "문양을 그리는 동안 실시간으로 줄며, 우회하거나 길게 그릴수록 더 소모된다."
                )
                briefingRow(
                    icon: "pencil.and.outline",
                    title: "이번 턴은 2획",
                    detail: "현재의 1획 공격 주문은 한 턴에 두 번까지 조합할 수 있다."
                )

                Button("전투 시작") {
                    withAnimation(.easeOut(duration: 0.2)) {
                        showsFirstTurnBriefing = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .frame(maxWidth: .infinity)
            }
            .padding(24)
            .frame(maxWidth: 520)
            .background(Color(red: 0.035, green: 0.04, blue: 0.055))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.purple.opacity(0.35), lineWidth: 1)
            }
        }
    }

    private func briefingRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .frame(width: 28)
                .foregroundStyle(.cyan)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var defeatOverlay: some View {
        ZStack {
            Color.black.opacity(0.76)
                .ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "exclamationmark.octagon.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.red)
                Text("하강 봉인 절차 중단")
                    .font(.title2.weight(.semibold))
                Text("전투 진입 직전 상태에서 다시 시작합니다.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("전투 재시작") {
                    gameSession.send(.restartEncounter)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
    }

    private var residualBriefing: some View {
        briefingOverlay(
            title: "관측 잔류체 대응",
            accent: .cyan,
            rows: [
                ("shield.fill", "훈련 방벽 20 유지", "보호 절차실에서 만든 방벽이 이번 전투의 첫 피해를 먼저 막는다."),
                ("scope", "강공격은 한 턴 전에 예고", "초점 고정이 보이면 다음 집속 파편에 대비할 수 있다."),
                ("pencil.and.outline", "공격과 방어를 같은 턴에 조합", "1획 공격과 1획 방어를 선택해 2획 안에서 대응한다.")
            ]
        )
    }

    private var observationBriefing: some View {
        briefingOverlay(
            title: "관측 관리자 절대 차폐",
            accent: .yellow,
            rows: [
                ("shield.checkered", "절대 방벽 1회", "방벽이 유지되는 동안 공격과 부가 효과가 전부 무효화된다."),
                ("sparkles", "먼저 공격 효과를 확인", "공격 주문을 한 번 시전해 절대 방벽의 차단 규칙을 직접 확인한다."),
                ("lock.open.fill", "체험 후 봉인 해제", "차단을 확인하면 봉인 해제 카드가 활성화된다.")
            ]
        )
    }

    private func briefingOverlay(
        title: String,
        accent: Color,
        rows: [(String, String, String)]
    ) -> some View {
        ZStack {
            Color.black.opacity(0.72)
                .ignoresSafeArea()
            VStack(alignment: .leading, spacing: 18) {
                Label(title, systemImage: "exclamationmark.shield.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(accent)
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    briefingRow(icon: row.0, title: row.1, detail: row.2)
                }
                Button("전투 시작") {
                    withAnimation(.easeOut(duration: 0.2)) {
                        showsFirstTurnBriefing = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .frame(maxWidth: .infinity)
            }
            .padding(24)
            .frame(maxWidth: 520)
            .background(Color(red: 0.035, green: 0.04, blue: 0.055))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(accent.opacity(0.35), lineWidth: 1)
            }
        }
    }

    private func isSpellPermitted(_ spell: SpellDefinition, battle: BattleState) -> Bool {
        if isObservationBattle, spell.id == .sealRelease {
            return battle.enemy.absoluteBarrierCharges > 0
                && didExperienceAbsoluteBarrier
        }
        return true
    }

    private var floorLabel: String {
        "B\(gameSession.progress.currentFloor.rawValue) · 하강 봉인 절차"
    }

    private var enemySymbol: String {
        switch gameSession.progress.currentScene {
        case .floor8ResidualBattle: "eye.trianglebadge.exclamationmark"
        case .floor8AdministratorBattle: "eye.circle.fill"
        default: "person.text.rectangle.fill"
        }
    }

    private func phaseTitle(_ phase: BattlePhase) -> String {
        switch phase {
        case .preparing: "절차 준비"
        case .playerTurn: "봉인관 차례"
        case .resolvingPlayerSpell: "주문 해석"
        case .resolvingEnemyAction: "관리자 차례"
        case .victory: "관리자 무력화"
        case .defeat: "절차 중단"
        }
    }

    private func intentSymbol(_ action: EnemyAction) -> String {
        switch action {
        case .attack(_, _, true): "exclamationmark.triangle.fill"
        case .attack: "burst.fill"
        case .grantNormalBarrier: "shield.fill"
        case .grantAbsoluteBarrier: "shield.checkered"
        case .telegraph: "scope"
        }
    }

    private func intentDetail(_ action: EnemyAction) -> String {
        switch action {
        case let .attack(_, damage, isStrong): isStrong ? "강공격 · 피해 \(damage)" : "공격 · 피해 \(damage)"
        case let .grantNormalBarrier(_, amount): "일반 방벽 \(amount)"
        case let .grantAbsoluteBarrier(_, charges): "절대 방벽 \(charges)회"
        case let .telegraph(_, upcoming): "다음 행동: \(upcoming)"
        }
    }

    private func intentColor(_ action: EnemyAction) -> Color {
        switch action {
        case .attack(_, _, true): .red
        case .attack: .orange
        case .grantNormalBarrier: .cyan
        case .grantAbsoluteBarrier: .yellow
        case .telegraph: .purple
        }
    }

    private func spellSymbol(_ category: SpellCategory) -> String {
        switch category {
        case .attack: "sparkles"
        case .defense: "shield.fill"
        case .dispel: "lock.open.fill"
        }
    }

    private func spellColor(_ category: SpellCategory) -> Color {
        switch category {
        case .attack: Color(red: 0.86, green: 0.2, blue: 0.38)
        case .defense: Color(red: 0.2, green: 0.72, blue: 0.92)
        case .dispel: Color(red: 0.94, green: 0.68, blue: 0.18)
        }
    }

    private func categoryTitle(_ category: SpellCategory) -> String {
        switch category {
        case .attack: "공격"
        case .defense: "방어"
        case .dispel: "해제"
        }
    }

    private func gradeTitle(_ grade: CastingGrade) -> String {
        switch grade {
        case .perfect: "완전 시전"
        case .precise: "정밀 시전"
        case .approved: "승인 시전"
        case .incomplete: "불완전 시전"
        case .rejected: "시전 거부"
        }
    }

    private func gradeColor(_ grade: CastingGrade) -> Color {
        switch grade {
        case .perfect: .white
        case .precise: .purple
        case .approved: .cyan
        case .incomplete: .orange
        case .rejected: .red
        }
    }

    private func failureTitle(_ failure: CastingFailure) -> String {
        switch failure {
        case .noInput: "문양 없음"
        case .wrongStrokeCount: "획 불일치"
        case .invalidStart: "시작점 오류"
        case .missingRequiredNode: "필수 지점 누락"
        case .invalidEnd: "종료점 오류"
        case .missingCrossing: "교차점 누락"
        case .manaDepleted: "마나 고갈"
        case .incompleteGlyph: "문양 불완전"
        }

    }
}
