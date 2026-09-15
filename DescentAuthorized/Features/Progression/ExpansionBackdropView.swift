import SwiftUI

/// A presentation-only stage while the expansion's RealityKit scenes are being built.
/// Combat and progression must never wait for this view to finish loading or animating.
struct ExpansionBackdropView: View {
    let floorNumber: Int
    var isBoss: Bool = false

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let controlAreaHeight = min(size.height * 0.29, 242)
            let stageHeight = max(size.height - controlAreaHeight, 1)

            ZStack {
                Color.black

                RadialGradient(
                    colors: [accent.opacity(0.22), Color.black],
                    center: UnitPoint(x: 0.5, y: 0.38),
                    startRadius: 0,
                    endRadius: max(size.width, size.height) * 0.62
                )

                if let assetName {
                    Image(assetName)
                        .resizable()
                        .scaledToFit()
                        .frame(
                            width: size.width * (isBoss ? 0.64 : 0.55),
                            height: stageHeight * (isBoss ? 0.98 : 0.86)
                        )
                        .mask {
                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0),
                                    .init(color: .black, location: 0.035),
                                    .init(color: .black, location: 0.88),
                                    .init(color: .clear, location: 1)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        }
                        .position(x: size.width * 0.5, y: stageHeight * 0.53)
                }

                // Keep the enemy legible while giving the HUD and bottom spell row contrast.
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.76), location: 0),
                        .init(color: .clear, location: 0.19),
                        .init(color: .clear, location: 0.56),
                        .init(color: .black.opacity(0.72), location: 0.82),
                        .init(color: .black, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                LinearGradient(
                    colors: [.black.opacity(0.45), .clear, .black.opacity(0.45)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
            .frame(width: size.width, height: size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var assetName: String? {
        guard (5...7).contains(floorNumber) else { return nil }
        return "ExpansionFloor\(floorNumber)\(isBoss ? "Boss" : "Residual")"
    }

    private var accent: Color {
        switch floorNumber {
        case 7: Color(red: 0.25, green: 0.67, blue: 0.72)
        case 6: Color(red: 0.68, green: 0.39, blue: 0.16)
        case 5: Color(red: 0.48, green: 0.31, blue: 0.62)
        default: Color(red: 0.18, green: 0.17, blue: 0.24)
        }
    }
}
