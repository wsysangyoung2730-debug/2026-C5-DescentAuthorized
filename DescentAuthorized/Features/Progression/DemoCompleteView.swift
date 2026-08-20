import SwiftUI

struct DemoCompleteView: View {
    @EnvironmentObject private var gameSession: GameSessionStore

    let onReturnToTitle: () -> Void

    @State private var revealsMessage = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            halfOpenedDoor

            VStack(spacing: 14) {
                Spacer()

                Text("하강 권한 일부 승인")
                    .font(.caption.monospaced().weight(.bold))
                    .foregroundStyle(.cyan)

                Text("제7층")
                    .font(.system(size: 54, weight: .semibold))

                Text(revealsMessage ? "아직, 아래층이 남아 있다." : " ")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.86))
                    .frame(height: 36)

                Text("잔여 절차: 미완료")
                    .font(.caption.monospaced())
                    .foregroundStyle(.red.opacity(0.72))

                Spacer()

                HStack(spacing: 12) {
                    Button("타이틀로") {
                        onReturnToTitle()
                    }
                    .buttonStyle(.bordered)

                    Button("처음부터 다시") {
                        gameSession.startNewGame()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                }
                .padding(.bottom, 38)
            }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(550))
            withAnimation(.easeIn(duration: 0.8)) {
                revealsMessage = true
            }
        }
    }

    private var halfOpenedDoor: some View {
        GeometryReader { proxy in
            ZStack {
                Rectangle()
                    .fill(Color(red: 0.03, green: 0.08, blue: 0.11))
                    .frame(width: proxy.size.width * 0.2)
                    .blur(radius: 18)

                HStack(spacing: proxy.size.width * 0.12) {
                    doorLeaf
                    doorLeaf
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var doorLeaf: some View {
        Rectangle()
            .fill(Color(red: 0.045, green: 0.05, blue: 0.065))
            .overlay {
                Rectangle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 2)
            }
            .frame(maxWidth: 280, maxHeight: .infinity)
    }
}
