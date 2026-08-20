import SwiftUI

struct BattleView: View {
    @State private var playerHP = 100
    @State private var enemyHP = 120
    @State private var availableStrikes = 2
    @State private var statusMessage = "관리자 차례"
    @State private var isPlayerTurn = true

    private let spellCards = [
        ("잔광 말소", 1),
        ("균열 절단", 1)
    ]

    private var canCastAnySpell: Bool {
        isPlayerTurn && availableStrikes > 0 && !spellCards.isEmpty
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 20) {
                header

                Spacer()

                Text(statusMessage)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))

                Spacer()

                spellBar

                HStack {
                    Button("턴 종료") {
                        endPlayerTurn()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.gray)
                    .disabled(!isPlayerTurn)

                    Spacer()

                    Button("보스 턴 진행") {
                        enemyAction()
                    }
                    .buttonStyle(.bordered)
                    .disabled(isPlayerTurn)
                }
            }
            .padding()
        }
        .onChange(of: availableStrikes) { _, _ in
            autoEndTurnIfNeeded()
        }
        .onAppear {
            autoEndTurnIfNeeded()
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("플레이어 HP \(playerHP)")
                Text("남은 획수 \(availableStrikes)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing) {
                Text("적 HP \(enemyHP)")
                Text(isPlayerTurn ? "플레이어 턴" : "적 턴")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(.white)
    }

    private var spellBar: some View {
        VStack(spacing: 12) {
            if canCastAnySpell {
                HStack {
                    ForEach(spellCards, id: \.0) { spell in
                        Button(spell.0) {
                            castSpell(cost: spell.1)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            } else {
                Text("시전할 수 있는 주문이 없습니다")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func castSpell(cost: Int) {
        guard isPlayerTurn, availableStrikes >= cost else { return }

        availableStrikes -= cost
        enemyHP = max(0, enemyHP - 14)
        statusMessage = enemyHP == 0 ? "승리" : "주문 시전 완료"

        autoEndTurnIfNeeded()
    }

    private func endPlayerTurn() {
        guard isPlayerTurn else { return }
        isPlayerTurn = false
        statusMessage = "관리자 차례"
    }

    private func enemyAction() {
        guard !isPlayerTurn else { return }

        playerHP = max(0, playerHP - 12)
        availableStrikes = 2
        isPlayerTurn = true
        statusMessage = "플레이어 차례"
    }

    private func autoEndTurnIfNeeded() {
        guard isPlayerTurn else { return }
        guard availableStrikes == 0 || !canCastAnySpell else { return }
        endPlayerTurn()
    }
}
