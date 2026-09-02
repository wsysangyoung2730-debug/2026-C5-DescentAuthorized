import SwiftUI

struct Floor9EntranceView: View {
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var gameFeedback: GameFeedbackManager
    @EnvironmentObject private var gameSession: GameSessionStore

    let sceneController: RealitySceneController

    var body: some View {
        FloorEntranceInvestigationFlow(
            sceneController: sceneController,
            configuration: .floor9,
            hasCompletedInvestigation: isInvestigationComplete
        ) {
            GeometryReader { proxy in
                let panelWidth = min(max(proxy.size.width * 0.43, 520), 650)

                ZStack(alignment: .trailing) {
                    worldDimming(panelWidth: panelWidth)
                    recordsPanel(width: panelWidth)
                }
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .onAppear {
            sceneController.resetProgressionPresentation(reducedMotion: appSettings.reducedMotion)
        }
    }

    private func worldDimming(panelWidth: CGFloat) -> some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: DAColor.background.opacity(0.08), location: 0.42),
                .init(color: DAColor.background.opacity(0.76), location: 1)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .padding(.trailing, panelWidth)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func recordsPanel(width: CGFloat) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                header

                sectionDivider
                    .padding(.vertical, 19)

                zoneTraits

                sectionDivider
                    .padding(.vertical, 19)

                resourceStatus

                investigationSummary
                    .padding(.top, 18)

                entryWarning
                    .padding(.top, 16)

                enterButton
                    .padding(.top, 14)
            }
            .padding(.horizontal, 30)
            .padding(.top, 30)
            .padding(.bottom, 28)
        }
        .frame(width: width)
        .frame(maxHeight: .infinity)
        .background {
            LinearGradient(
                colors: [
                    Floor9EntrancePalette.panelTop.opacity(0.985),
                    DAColor.background.opacity(0.995)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            DAColor.magic.opacity(0.28),
                            DAColor.magicGlow.opacity(0.92),
                            Floor9EntrancePalette.brass.opacity(0.35)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 1)
                .shadow(color: DAColor.magic.opacity(0.45), radius: 6)
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Floor9EntrancePalette.brass.opacity(0.25))
                .frame(height: 1)
        }
        .clipped()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text("9-A / 중앙 기록실 입구")
                    .font(.caption.monospaced().weight(.bold))
                    .foregroundStyle(DAColor.magicGlow)

                Spacer(minLength: 12)

                statusBadge
            }

            Text("제9층 기록 보존 구역")
                .font(.system(size: 32, weight: .semibold, design: .serif))
                .foregroundStyle(Floor9EntrancePalette.title)

            Text("문서의 이름이 눈앞에서 지워진다.\n닫힌 중앙 기록실 너머로 도장을 찍는 소리가 일정한 간격으로 반복된다.")
                .font(.subheadline)
                .foregroundStyle(DAColor.secondary)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var statusBadge: some View {
        let isComplete = inspectedClueIDs.count == FloorEntranceInvestigationConfiguration.floor9.clues.count
        let color = isComplete ? Floor9EntrancePalette.success : Floor9EntrancePalette.brass

        return Text(
            isComplete
                ? "입구 조사 완료"
                : "조사 \(inspectedClueIDs.count) / \(FloorEntranceInvestigationConfiguration.floor9.clues.count)"
        )
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(color.opacity(0.1), in: Capsule())
            .overlay {
                Capsule().stroke(color.opacity(0.36), lineWidth: 1)
            }
    }

    private var zoneTraits: some View {
        VStack(alignment: .leading, spacing: 13) {
            sectionTitle("구역 특성", systemImage: "exclamationmark.triangle")

            Floor9TraitRow(
                icon: "text.badge.xmark",
                title: "기록 소실",
                description: "전투가 길어질수록 보유 주문의 정보가 흐려집니다.",
                color: DAColor.magicGlow
            )

            Floor9TraitRow(
                icon: "arrow.uturn.backward.circle",
                title: "반려 집행",
                description: "관리자는 문양 반려 시 즉시 반격합니다.",
                color: DAColor.attack
            )

            Floor9TraitRow(
                icon: "shield.lefthalf.filled",
                title: "문서 방벽",
                description: "전투 시작 시 절대 방벽 2를 획득합니다.",
                color: DAColor.defense
            )
        }
    }

    private var resourceStatus: some View {
        VStack(alignment: .leading, spacing: 13) {
            sectionTitle("사전 자원 확인", systemImage: "scribble.variable")

            VStack(spacing: 0) {
                Floor9ResourceRow(
                    icon: "pencil.line",
                    title: "현재 마나",
                    value: "100 / 100",
                    status: "충분",
                    color: DAColor.defense
                )

                Rectangle()
                    .fill(DAColor.divider.opacity(0.65))
                    .frame(height: 1)
                    .padding(.leading, 46)

                Floor9ResourceRow(
                    icon: "pencil.and.outline",
                    title: "턴당 최대 획",
                    value: "2",
                    status: "사용 가능",
                    color: DAColor.magicGlow
                )
            }
            .padding(.horizontal, 13)
            .background(DAColor.card.opacity(0.72), in: RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(DAColor.divider.opacity(0.72), lineWidth: 1)
            }

            Text("1획 주문 두 개 또는 2획 주문 하나를 시전할 수 있습니다.")
                .font(.caption)
                .foregroundStyle(DAColor.secondary)
        }
    }

    private var investigationSummary: some View {
        ZStack(alignment: .trailing) {
            Image("Floor9DocumentStamp")
                .resizable()
                .scaledToFill()
                .frame(width: 86, height: 86)
                .clipped()
                .opacity(isInvestigationComplete ? 0.34 : 0.18)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 8) {
                    Image(systemName: isInvestigationComplete ? "checkmark.seal.fill" : "doc.text.magnifyingglass")
                        .foregroundStyle(isInvestigationComplete ? Floor9EntrancePalette.success : DAColor.magicGlow)

                    Text(isInvestigationComplete ? "입구 조사 완료" : "조사 가능한 기록 2개")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isInvestigationComplete ? Floor9EntrancePalette.success : DAColor.magicGlow)
                }

                Text("입구 기록 2개를 모두 확인했습니다. 완료한 기록은 탐색 화면에서 다시 열 수 있습니다.")
                    .font(.caption)
                    .foregroundStyle(Floor9EntrancePalette.warmText)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.trailing, 62)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .background(
            LinearGradient(
                colors: [DAColor.magic.opacity(0.12), DAColor.card.opacity(0.68)],
                startPoint: .leading,
                endPoint: .trailing
            ),
            in: RoundedRectangle(cornerRadius: 7)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(DAColor.magic.opacity(0.52), lineWidth: 1)
        }
    }

    private var inspectedClueIDs: Set<String> {
        Set(FloorEntranceInvestigationConfiguration.floor9.clues.map(\.recordID))
            .intersection(gameSession.progress.readRecordIDs)
    }

    private var isInvestigationComplete: Bool {
        inspectedClueIDs.count == FloorEntranceInvestigationConfiguration.floor9.clues.count
    }

    private var entryWarning: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.system(size: 22, weight: .semibold))
                .accessibilityHidden(true)

            Text("진입하면 제9층 기록 관리자와의 전투가 시작됩니다.")
                .font(.caption)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var enterButton: some View {
        Button {
            gameFeedback.playInterface(.confirm, settings: appSettings.settings)
            gameSession.send(.enterRecordsBattle)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "door.left.hand.open")
                Text("중앙 기록실 진입")
                    .font(.headline)
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.subheadline.weight(.bold))
            }
            .foregroundStyle(Floor9EntrancePalette.title)
            .padding(.horizontal, 18)
            .frame(height: 52)
            .background {
                ZStack {
                    LinearGradient(
                        colors: [
                            DAColor.magic.opacity(0.82),
                            Color(red: 0.29, green: 0.17, blue: 0.45)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )

                    Image("Floor9EntryButtonPlate")
                        .resizable()
                        .scaledToFill()
                        .opacity(0.74)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Floor9EntrancePalette.brass.opacity(0.66), lineWidth: 1)
            }
            .shadow(color: DAColor.magic.opacity(0.24), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
    }

    private var sectionDivider: some View {
        Image("Floor9SectionDivider")
            .resizable()
            .scaledToFill()
            .frame(height: 12)
            .clipped()
            .opacity(0.74)
            .accessibilityHidden(true)
    }

    private func sectionTitle(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Floor9EntrancePalette.brass)
    }
}

private struct Floor9TraitRow: View {
    let icon: String
    let title: String
    let description: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Floor9EntrancePalette.warmText)

                Text(description)
                    .font(.caption)
                    .foregroundStyle(DAColor.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct Floor9ResourceRow: View {
    let icon: String
    let title: String
    let value: String
    let status: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 24)

            Text(title)
                .font(.caption)
                .foregroundStyle(DAColor.secondary)

            Spacer()

            Text(value)
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(Floor9EntrancePalette.warmText)

            Text(status)
                .font(.caption2.weight(.bold))
                .foregroundStyle(color)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(color.opacity(0.1), in: Capsule())
        }
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
    }
}

private enum Floor9EntrancePalette {
    static let panelTop = Color(red: 13 / 255, green: 18 / 255, blue: 25 / 255)
    static let brass = Color(red: 196 / 255, green: 151 / 255, blue: 82 / 255)
    static let title = Color(red: 239 / 255, green: 227 / 255, blue: 203 / 255)
    static let warmText = Color(red: 222 / 255, green: 215 / 255, blue: 202 / 255)
    static let success = Color(red: 105 / 255, green: 190 / 255, blue: 158 / 255)
}
