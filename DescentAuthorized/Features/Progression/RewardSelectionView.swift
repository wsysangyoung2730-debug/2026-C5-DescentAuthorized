import SwiftUI

struct RewardSelectionView: View {
    @EnvironmentObject private var gameSession: GameSessionStore

    let floor: FloorID

    @State private var selectedCandidateID: String?
    @State private var isResolving = false

    private var candidates: [RewardCandidate] {
        RewardCatalog.candidates(for: floor)
    }

    var body: some View {
        ZStack {
            rewardBackground

            VStack(spacing: 22) {
                VStack(spacing: 6) {
                    Text("보존 금고 / 미복원 주문 기록")
                        .font(.caption.monospaced().weight(.bold))
                        .foregroundStyle(.secondary)
                    Text("복원할 주문서 하나를 선택하십시오")
                        .font(.title2.weight(.semibold))
                    Text("선택되지 않은 기록은 즉시 말소됩니다")
                        .font(.subheadline)
                        .foregroundStyle(.red.opacity(0.72))
                }

                HStack(spacing: 26) {
                    ForEach(candidates) { candidate in
                        rewardScroll(candidate)
                    }
                }
                .frame(maxHeight: 390)

                if isResolving {
                    Label("선택 기록 복원 중", systemImage: "text.viewfinder")
                        .font(.headline)
                        .foregroundStyle(.purple)
                } else {
                    Button {
                        confirmSelection()
                    } label: {
                        Label("선택 주문서 복원", systemImage: "seal.fill")
                            .frame(minWidth: 220)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .disabled(selectedCandidateID == nil)
                }
            }
            .padding(32)
        }
    }

    private func rewardScroll(_ candidate: RewardCandidate) -> some View {
        let isSelected = selectedCandidateID == candidate.id
        let isDiscarded = isResolving && !isSelected

        return Button {
            guard !isResolving else { return }
            withAnimation(.spring(response: 0.28)) {
                selectedCandidateID = candidate.id
            }
        } label: {
            VStack(spacing: 16) {
                HStack {
                    Image(systemName: tierSymbol(candidate.tier))
                    Spacer()
                    Text(categoryTitle(candidate.category))
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(tierColor(candidate.tier))

                Spacer()

                Image(systemName: "scroll.fill")
                    .font(.system(size: 70, weight: .thin))
                    .foregroundStyle(tierColor(candidate.tier))
                    .shadow(color: tierColor(candidate.tier).opacity(0.72), radius: 16)

                Text(candidate.obscuredName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)

                Text(tierTitle(candidate.tier))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Label(
                    isSelected ? "선택됨" : "미복원",
                    systemImage: isSelected ? "checkmark.circle.fill" : "questionmark.diamond"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? tierColor(candidate.tier) : .secondary)
            }
            .padding(18)
            .frame(width: 210, height: 330)
            .background(Color.black.opacity(0.48))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(
                        isSelected ? tierColor(candidate.tier) : Color.white.opacity(0.12),
                        lineWidth: isSelected ? 2 : 1
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .offset(y: isSelected ? -12 : 0)
        .scaleEffect(isDiscarded ? 0.82 : 1)
        .opacity(isDiscarded ? 0 : 1)
        .disabled(isResolving)
        .accessibilityLabel(
            "\(candidate.obscuredName), \(categoryTitle(candidate.category)), \(tierTitle(candidate.tier))"
        )
    }

    private func confirmSelection() {
        guard let selectedCandidateID, !isResolving else { return }
        withAnimation(.easeInOut(duration: 0.45)) {
            isResolving = true
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(850))
            gameSession.send(.selectReward(selectedCandidateID))
        }
    }

    private var rewardBackground: some View {
        ZStack {
            Color(red: 0.015, green: 0.02, blue: 0.03)
            Canvas { context, size in
                var path = Path()
                for column in 0...10 {
                    let x = size.width * CGFloat(column) / 10
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                }
                context.stroke(path, with: .color(.white.opacity(0.025)), lineWidth: 1)
            }
        }
        .ignoresSafeArea()
    }

    private func tierColor(_ tier: ScrollTier) -> Color {
        switch tier {
        case .worn: Color(red: 0.25, green: 0.62, blue: 0.96)
        case .engraved: Color(red: 0.66, green: 0.32, blue: 0.94)
        case .sealed: Color(red: 0.94, green: 0.72, blue: 0.22)
        case .forbidden: Color(red: 0.72, green: 0.12, blue: 0.3)
        }
    }

    private func tierSymbol(_ tier: ScrollTier) -> String {
        switch tier {
        case .worn: "drop.fill"
        case .engraved: "diamond.inset.filled"
        case .sealed: "lock.fill"
        case .forbidden: "exclamationmark.triangle.fill"
        }
    }

    private func tierTitle(_ tier: ScrollTier) -> String {
        switch tier {
        case .worn: "낡은 주문서"
        case .engraved: "각인 주문서"
        case .sealed: "봉인 주문서"
        case .forbidden: "금서"
        }
    }

    private func categoryTitle(_ category: SpellCategory) -> String {
        switch category {
        case .attack: "공격"
        case .defense: "방어"
        case .dispel: "해제"
        }
    }
}
