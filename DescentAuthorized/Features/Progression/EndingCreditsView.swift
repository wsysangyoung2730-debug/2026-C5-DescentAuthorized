import SwiftUI
import UIKit

/// The last page stays on screen until the player explicitly confirms.
struct EndingCreditsView: View {
    @Environment(\.isGlyphInputSuspended) private var isSuspended
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var gameFeedback: GameFeedbackManager

    let onConfirm: () -> Void

    @State private var scrollPosition = ScrollPosition(edge: .top)
    @State private var playback = EndingCreditsPlayback()
    @State private var isManuallyScrolling = false
    @State private var isVoiceOverRunning = UIAccessibility.isVoiceOverRunning
    @State private var hasConfirmed = false

    private var shouldAutoScroll: Bool {
        !isSuspended && !isManuallyScrolling && !isVoiceOverRunning
            && !systemReduceMotion && !appSettings.reducedMotion && !hasConfirmed
            && playback.maximumOffset > 0 && !playback.isAtEnd
    }

    var body: some View {
        GeometryReader { viewport in
            ScrollView(.vertical) {
                VStack(spacing: 100) {
                    Text(EndingCreditsCatalog.title)
                        .font(.system(size: 38, weight: .light, design: .serif))
                        .foregroundStyle(DAColor.gold)
                        .padding(.top, 70)
                        .padding(.bottom, 30)
                        .accessibilityAddTraits(.isHeader)

                    ForEach(EndingCreditsCatalog.entries) { entry in
                        VStack(spacing: 22) {
                            Text("\(entry.title) · \(entry.subtitle)")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(DAColor.gold)
                                .accessibilityAddTraits(.isHeader)

                            Text(entry.text)
                                .font(.system(size: 24, weight: .regular, design: .serif))
                                .lineSpacing(12)
                                .foregroundStyle(DAColor.body)
                        }
                        .accessibilityElement(children: .combine)
                    }

                    VStack(spacing: 28) {
                        Text("인계 기록")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(DAColor.gold)
                            .accessibilityAddTraits(.isHeader)
                        Text(EndingCreditsCatalog.handoffBody)
                            .font(.system(size: 22, design: .serif))
                            .foregroundStyle(DAColor.body)
                            .lineSpacing(12)
                        Text("“\(EndingCreditsCatalog.finalQuote)”")
                            .font(.system(size: 22, design: .serif))
                            .foregroundStyle(DAColor.gold.opacity(0.9))
                            .lineSpacing(12)
                            .padding(.top, 20)
                    }

                    closingCredit
                        .frame(minHeight: max(280, viewport.size.height))
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: 760)
                .padding(.horizontal, 32)
                .frame(maxWidth: .infinity)
            }
            .scrollPosition($scrollPosition)
            .scrollIndicators(.hidden)
            .onScrollGeometryChange(for: CreditsScrollGeometry.self) { geometry in
                CreditsScrollGeometry(
                    offset: geometry.contentOffset.y + geometry.contentInsets.top,
                    maximumOffset: max(0, geometry.contentSize.height + geometry.contentInsets.top
                        + geometry.contentInsets.bottom - geometry.containerSize.height)
                )
            } action: { _, geometry in
                playback.updateLayout(offset: geometry.offset, maximumOffset: geometry.maximumOffset)
            }
            .onScrollPhaseChange { _, phase in
                isManuallyScrolling = phase == .tracking || phase == .interacting || phase == .decelerating
            }
            .scrollDisabled(isSuspended)
            .accessibilityIdentifier("ending.credits.scroll")
        }
        .background(Color(red: 0.022, green: 0.025, blue: 0.03))
        .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.voiceOverStatusDidChangeNotification)) { _ in
            isVoiceOverRunning = UIAccessibility.isVoiceOverRunning
        }
        .task(id: shouldAutoScroll) {
            guard shouldAutoScroll else { return }
            let clock = ContinuousClock()
            var previous = clock.now
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(33)) }
                catch { return }
                guard shouldAutoScroll else { return }
                let now = clock.now
                let delta = previous.duration(to: now).components
                previous = now
                let elapsed = Double(delta.seconds) + Double(delta.attoseconds) / 1e18
                if let target = playback.advance(elapsed: elapsed, isSuspended: isSuspended) {
                    scrollPosition.scrollTo(y: target)
                }
            }
        }
    }

    private var closingCredit: some View {
        VStack(spacing: 36) {
            Rectangle()
                .fill(DAColor.gold.opacity(0.4))
                .frame(width: 64, height: 1)
                .accessibilityHidden(true)
            Text(EndingCreditsCatalog.creatorCredit)
                .font(.system(size: 26, weight: .regular, design: .serif))
                .foregroundStyle(DAColor.body)
                .accessibilityIdentifier("ending.creator")
            Button("확인") {
                guard !hasConfirmed, !isSuspended else { return }
                hasConfirmed = true
                gameFeedback.playInterface(.confirm, settings: appSettings.settings)
                onConfirm()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(DAColor.gold.opacity(0.85))
            .foregroundStyle(.black)
            .disabled(hasConfirmed || isSuspended)
            .accessibilityHint("하강 기록을 닫고 타이틀로 돌아갑니다")
            .accessibilityIdentifier("ending.confirm")
        }
    }
}

private struct CreditsScrollGeometry: Equatable {
    let offset: Double
    let maximumOffset: Double
}
