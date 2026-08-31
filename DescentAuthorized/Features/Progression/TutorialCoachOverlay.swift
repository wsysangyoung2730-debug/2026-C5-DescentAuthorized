import SwiftUI

struct TutorialTargetID: Hashable, ExpressibleByStringLiteral {
    let rawValue: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    init(stringLiteral value: StringLiteralType) {
        rawValue = value
    }
}

struct TutorialCoachStep: Identifiable, Equatable {
    enum Placement: Equatable {
        case top
        case center
        case bottom
    }

    let id: TutorialStepID
    let title: String
    let message: String
    let targetIDs: [TutorialTargetID]
    var placement: Placement = .bottom
    var advancesOnTargetTap = false
    var showsSkip = true
}

private struct TutorialTargetPreferenceKey: PreferenceKey {
    static var defaultValue: [TutorialTargetID: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [TutorialTargetID: Anchor<CGRect>],
        nextValue: () -> [TutorialTargetID: Anchor<CGRect>]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension View {
    func tutorialTarget(_ id: TutorialTargetID) -> some View {
        anchorPreference(key: TutorialTargetPreferenceKey.self, value: .bounds) {
            [id: $0]
        }
    }

    func tutorialCoach(
        step: TutorialCoachStep?,
        nextTitle: String = "다음",
        onNext: @escaping () -> Void,
        onSkip: @escaping () -> Void
    ) -> some View {
        overlayPreferenceValue(TutorialTargetPreferenceKey.self) { anchors in
            GeometryReader { proxy in
                if let step {
                    TutorialCoachOverlay(
                        step: step,
                        highlightFrames: step.targetIDs.compactMap { id in
                            anchors[id].map { proxy[$0].insetBy(dx: -8, dy: -8) }
                        },
                        nextTitle: nextTitle,
                        onNext: onNext,
                        onSkip: onSkip
                    )
                }
            }
        }
    }
}

struct TutorialCoachOverlay: View {
    let step: TutorialCoachStep
    let highlightFrames: [CGRect]
    let nextTitle: String
    let onNext: () -> Void
    let onSkip: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                spotlightMask(size: proxy.size)

                if step.advancesOnTargetTap {
                    ForEach(Array(highlightFrames.enumerated()), id: \.offset) { _, frame in
                        Button(action: onNext) {
                            Color.clear
                                .contentShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                        .accessibilityLabel(step.title)
                        .accessibilityHint("두 번 탭하여 다음 안내로 이동")
                    }
                }

                coachPanel
                    .frame(maxWidth: min(proxy.size.width * 0.62, 720))
                    .padding(.horizontal, 28)
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: alignment(for: step.placement)
                    )
                    .padding(.vertical, 30)
            }
            .opacity(isVisible ? 1 : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: isVisible)
            .onAppear { isVisible = true }
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private func spotlightMask(size: CGSize) -> some View {
        Canvas { context, _ in
            var path = Path(CGRect(origin: .zero, size: size))
            for frame in highlightFrames {
                path.addRoundedRect(
                    in: frame,
                    cornerSize: CGSize(width: 12, height: 12)
                )
            }
            context.fill(
                path,
                with: .color(Color.black.opacity(0.88)),
                style: FillStyle(eoFill: true)
            )

            for frame in highlightFrames {
                context.stroke(
                    Path(roundedRect: frame, cornerRadius: 12),
                    with: .color(DAColor.magicGlow.opacity(0.9)),
                    lineWidth: 2
                )
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { }
        .accessibilityHidden(true)
    }

    private var coachPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(step.title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(DAColor.gold)

            Text(step.message)
                .font(.body)
                .foregroundStyle(DAColor.body)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                if step.showsSkip {
                    Button("건너뛰기", action: onSkip)
                        .buttonStyle(TutorialCoachSecondaryButtonStyle())
                }

                Spacer(minLength: 12)

                if !step.advancesOnTargetTap {
                    Button(nextTitle, action: onNext)
                        .buttonStyle(TutorialCoachPrimaryButtonStyle())
                } else {
                    Text("강조된 항목을 눌러 계속")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(DAColor.magicGlow)
                }
            }
        }
        .padding(22)
        .background(
            LinearGradient(
                colors: [DAColor.panel.opacity(0.98), DAColor.background.opacity(0.99)],
                startPoint: .top,
                endPoint: .bottom
            ),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(DAColor.gold.opacity(0.62), lineWidth: 1)
        }
        .shadow(color: DAColor.magic.opacity(0.4), radius: 18)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("튜토리얼. \(step.title). \(step.message)")
    }

    private func alignment(for placement: TutorialCoachStep.Placement) -> Alignment {
        switch placement {
        case .top: .top
        case .center: .center
        case .bottom: .bottom
        }
    }
}

private struct TutorialCoachPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(DAColor.body)
            .padding(.horizontal, 24)
            .frame(minHeight: 46)
            .background(
                DAColor.magic.opacity(configuration.isPressed ? 0.38 : 0.24),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(DAColor.magicGlow.opacity(0.8), lineWidth: 1)
            }
    }
}

private struct TutorialCoachSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .foregroundStyle(DAColor.secondary)
            .padding(.horizontal, 18)
            .frame(minHeight: 44)
            .background(DAColor.card.opacity(0.82), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(DAColor.divider, lineWidth: 1)
            }
    }
}
