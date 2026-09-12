import SwiftUI

/// Practice has its own input budget and never sends commands to the game session.
struct SpellPracticeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appSettings: AppSettings
    let spell: SpellDefinition
    @State private var attempt = 0
    @State private var result = "획순을 확인하고 자유롭게 연습하세요."

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(spell.name) · 시험 각인").font(.title2.weight(.semibold))
                    Text(SpellCatalog.metadata(for: spell.id).effectSummary).font(.subheadline)
                }
                Spacer()
                Button("닫기") { dismiss() }.buttonStyle(.bordered)
            }
            Text("이 연습에서는 체력·획득·전투 기록이 바뀌지 않습니다.")
                .font(.caption).foregroundStyle(DAColor.secondary)
            GlyphCastingPanel(spell: spell, inputPreference: appSettings.inputPreference,
                availableMana: 100, availableStrokes: 2, erasureZones: [],
                onCast: { submission in
                    result = submission.evaluation.succeeded ? "각인 성공 · 다시 시도할 수 있습니다." : "각인 실패 · 표시된 경로와 획순을 다시 확인하세요."
                    attempt += 1
                })
                .id(attempt)
            Text(result).font(.callout).foregroundStyle(DAColor.gold)
            Text(SpellCatalog.metadata(for: spell.id).usageNote).font(.caption)
        }
        .padding(28).background(DAColor.background).preferredColorScheme(.dark)
    }
}
