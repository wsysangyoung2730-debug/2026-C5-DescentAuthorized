import SwiftUI

struct Floor8DescentDoorView: View {
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var gameSession: GameSessionStore

    var body: some View {
        ZStack {
            Color(red: 0.012, green: 0.018, blue: 0.024)
                .ignoresSafeArea()

            HStack(spacing: 0) {
                descentPreview
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                VStack(alignment: .leading, spacing: 14) {
                    Text("8-F / 제7층 하강문")
                        .font(.caption.monospaced().weight(.bold))
                        .foregroundStyle(.cyan)
                    Text("잔여 절차: 미완료")
                        .font(.title2.weight(.semibold))
                    Text("관측 관리자는 무력화됐지만 봉인 시스템은 더 아래로 이어진다. 두 획의 승인 문양을 겹쳐 제7층 통로를 확인한다.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)

                    DoorGlyphPanel(
                        definition: DescentDoorGlyphCatalog.floor8,
                        inputPreference: appSettings.inputPreference,
                        onApproved: { _ in
                            gameSession.send(.approveDescentDoor)
                        }
                    )
                    .frame(maxWidth: 680)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(30)
            }
        }
    }

    private var descentPreview: some View {
        ZStack {
            Canvas { context, size in
                let door = CGRect(
                    x: size.width * 0.25,
                    y: size.height * 0.12,
                    width: size.width * 0.5,
                    height: size.height * 0.78
                )
                context.fill(Path(door), with: .color(.black.opacity(0.72)))
                context.stroke(Path(door), with: .color(.cyan.opacity(0.28)), lineWidth: 3)

                var center = Path()
                center.move(to: CGPoint(x: door.midX, y: door.minY))
                center.addLine(to: CGPoint(x: door.midX, y: door.maxY))
                context.stroke(center, with: .color(.white.opacity(0.1)), lineWidth: 1)
            }

            VStack(spacing: 16) {
                Image(systemName: "arrow.down.to.line.compact")
                    .font(.system(size: 88, weight: .ultraLight))
                    .foregroundStyle(.cyan.opacity(0.82))
                    .shadow(color: .cyan.opacity(0.55), radius: 20)
                Text("하부 공간에서 복수의 비상 신호 감지")
                    .font(.caption.monospaced())
                    .foregroundStyle(.red.opacity(0.7))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("아래층의 여러 비상 신호가 감지되는 닫힌 제7층 하강문")
    }
}
