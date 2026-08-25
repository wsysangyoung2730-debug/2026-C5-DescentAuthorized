import SwiftUI

struct Floor8DescentDoorView: View {
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var gameSession: GameSessionStore
    @State private var descentState: RealityDescentPresentationState = .ready
    @State private var transitionTask: Task<Void, Never>?
    @StateObject private var sceneController = RealitySceneController()

    var body: some View {
        ZStack {
            RealityStageView(
                sceneID: gameSession.presentation.floorSceneID ?? .floor08AdministratorObservatory,
                cameraPreset: gameSession.presentation.cameraPreset,
                descentState: descentState,
                reducedMotion: appSettings.reducedMotion,
                controller: sceneController
            )

            Color.black.opacity(0.2)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            HStack {
                Spacer(minLength: 320)
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
                        onStateChanged: updateDescentState,
                        onApproved: { _ in
                            completeDescent()
                        }
                    )
                    .frame(width: 590, height: 410)
                }
                .padding(20)
                .background(DAColor.panel.opacity(0.92))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(DAColor.divider, lineWidth: 1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(26)
        }
        .onDisappear { transitionTask?.cancel() }
    }

    private func updateDescentState(_ state: DoorGlyphPresentationState) {
        switch state {
        case .ready: descentState = .ready
        case .drawing: descentState = .drawing
        case .failed: descentState = .failed
        case .approved: descentState = .approved
        }
    }

    private func completeDescent() {
        descentState = .approved
        transitionTask?.cancel()
        transitionTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(appSettings.reducedMotion ? 20 : 560))
            guard !Task.isCancelled else { return }
            descentState = .open
            try? await Task.sleep(for: .milliseconds(appSettings.reducedMotion ? 20 : 420))
            guard !Task.isCancelled else { return }
            gameSession.send(.approveDescentDoor)
        }
    }
}
