import SwiftUI

enum ArcaneNavigationSymbol: Equatable {
    case forward
    case inputBoard

    var assetName: String {
        switch self {
        case .forward: "ArcaneNavigationForwardIcon"
        case .inputBoard: "ArcaneNavigationInputGesture"
        }
    }

    var size: CGSize {
        switch self {
        case .forward: CGSize(width: 38, height: 30)
        case .inputBoard: CGSize(width: 28, height: 38)
        }
    }
}

struct ArcaneNavigationButton: View {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @EnvironmentObject private var appSettings: AppSettings

    let title: String
    let symbol: ArcaneNavigationSymbol
    var width: CGFloat = 390
    var showsWaypoint = false
    let action: () -> Void

    @State private var isPulseActive = false

    var body: some View {
        VStack(spacing: -1) {
            if showsWaypoint {
                waypointGuide
            }

            Button(action: action) {
                ZStack {
                    Image("ArcaneNavigationGlow")
                        .resizable()
                        .scaledToFit()
                        .frame(width: width * 1.12, height: 54)
                        .opacity(isPulseActive ? 0.66 : 0.42)
                        .scaleEffect(x: isPulseActive ? 1.025 : 0.98, y: 1)
                        .offset(y: 14)
                        .blendMode(.screen)
                        .allowsHitTesting(false)

                    Image("ArcaneNavigationButtonPlate")
                        .resizable()
                        .frame(width: width, height: 72)
                        .shadow(color: .black.opacity(0.7), radius: 9, y: 5)
                        .shadow(color: Color.purple.opacity(isPulseActive ? 0.22 : 0.12), radius: 10)

                    HStack(spacing: 14) {
                        Image(symbol.assetName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: symbol.size.width, height: symbol.size.height)
                            .offset(
                                x: symbol == .forward && isPulseActive ? 2 : 0,
                                y: symbol == .inputBoard && isPulseActive ? -1.5 : 0
                            )
                            .shadow(color: Color.cyan.opacity(0.2), radius: 3)

                        Text(title)
                            .font(.system(size: 18, weight: .semibold, design: .serif))
                            .foregroundStyle(Color(red: 0.94, green: 0.9, blue: 0.82))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }
                    .padding(.horizontal, 38)
                }
                .frame(width: width, height: 72)
                .contentShape(Rectangle())
            }
            .buttonStyle(ArcaneNavigationPressStyle(reducesMotion: reducesMotion))
        }
        .onAppear {
            guard !reducesMotion else {
                isPulseActive = true
                return
            }
            withAnimation(.easeInOut(duration: 1.35).repeatForever(autoreverses: true)) {
                isPulseActive = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
    }

    private var waypointGuide: some View {
        VStack(spacing: -2) {
            Image("ArcaneNavigationWaypoint")
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
                .opacity(isPulseActive ? 0.92 : 0.68)
                .shadow(color: Color.purple.opacity(0.3), radius: 5)

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.purple.opacity(0.62), Color.purple.opacity(0.12)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 1, height: 26)
        }
        .frame(height: 44)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var reducesMotion: Bool {
        systemReduceMotion || appSettings.reducedMotion
    }
}

private struct ArcaneNavigationPressStyle: ButtonStyle {
    let reducesMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .brightness(configuration.isPressed ? 0.08 : 0)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(
                reducesMotion ? nil : .easeOut(duration: 0.12),
                value: configuration.isPressed
            )
    }
}
