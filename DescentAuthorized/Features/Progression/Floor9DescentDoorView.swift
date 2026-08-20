import SwiftUI

struct Floor9DescentDoorView: View {
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var gameSession: GameSessionStore

    private let spell = SpellCatalog.barrierPiercing

    var body: some View {
        ZStack {
            Color(red: 0.018, green: 0.022, blue: 0.03)
                .ignoresSafeArea()

            HStack(spacing: 0) {
                learnedSpell
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(30)

                Divider()

                VStack(alignment: .leading, spacing: 14) {
                    Text("9-D / 제8층 하강문")
                        .font(.caption.monospaced().weight(.bold))
                        .foregroundStyle(.purple)
                    Text("기록 검수 완료")
                        .font(.title2.weight(.semibold))
                    Text("8층 관측실 접근 권한을 임시 승인하려면 기록 검수 문양을 제출해야 한다.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)

                    DoorGlyphPanel(
                        definition: DescentDoorGlyphCatalog.floor9,
                        inputPreference: appSettings.inputPreference,
                        onApproved: { _ in
                            gameSession.send(.approveDescentDoor)
                        }
                    )
                    .frame(maxWidth: 650)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(30)
            }
        }
    }

    private var learnedSpell: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("신규 주문 등록", systemImage: "checkmark.seal.fill")
                .font(.headline)
                .foregroundStyle(.cyan)
            Text(spell.name)
                .font(.system(size: 32, weight: .semibold))
            Text("일반 방벽을 무너뜨리고 피해를 관통시키는 2획 공격 주문")
                .foregroundStyle(.secondary)

            Canvas { context, size in
                for stroke in spell.glyph.strokes {
                    var path = Path()
                    guard let first = stroke.referencePath.first else { continue }
                    path.move(to: point(first, size: size))
                    for glyphPoint in stroke.referencePath.dropFirst() {
                        path.addLine(to: point(glyphPoint, size: size))
                    }
                    context.stroke(
                        path,
                        with: .color(.cyan.opacity(0.88)),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                    )
                }
            }
            .frame(maxHeight: 310)
            .background(Color.black.opacity(0.42))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.cyan.opacity(0.28), lineWidth: 1)
            }

            Label("필요 획 2 · 강한 주문일수록 문양이 복잡해진다", systemImage: "pencil.and.outline")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func point(_ point: NormalizedPoint, size: CGSize) -> CGPoint {
        CGPoint(
            x: size.width * point.x / 100,
            y: size.height * point.y / 100
        )
    }
}
