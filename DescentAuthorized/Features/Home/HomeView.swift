import SwiftUI

struct HomeView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 12) {
                Text("하강 승인")
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(.white)

                Text("제0균열")
                    .font(.title2)
                    .foregroundStyle(.purple)

                Text("DESCENT AUTHORIZED: Rift Zero")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .preferredColorScheme(.dark)
    }
}
