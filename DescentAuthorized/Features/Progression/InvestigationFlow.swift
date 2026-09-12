import SwiftUI

/// Sequences the shared investigation experience into an optional post-investigation
/// scene and the floor-specific entrance presentation.
struct InvestigationFlow<EntranceContent: View>: View {
    @EnvironmentObject private var appSettings: AppSettings

    @ObservedObject var sceneController: RealitySceneController

    let configuration: InvestigationConfiguration
    let hasCompletedInvestigation: Bool
    let hasCompletedPostInvestigation: Bool
    let postInvestigationContent: ((@escaping () -> Void) -> AnyView)?
    let entranceContent: EntranceContent

    @State private var isEntrancePresented = false
    @State private var isInvestigationPresented = true
    @State private var isPostInvestigationPresented = false
    @State private var isBossRevealTransition = false
    @State private var isActive = false
    @State private var revealGeneration = 0
    @State private var entranceRevealTask: Task<Void, Never>?

    init(
        sceneController: RealitySceneController,
        configuration: InvestigationConfiguration,
        hasCompletedInvestigation: Bool,
        @ViewBuilder entranceContent: () -> EntranceContent
    ) {
        self.sceneController = sceneController
        self.configuration = configuration
        self.hasCompletedInvestigation = hasCompletedInvestigation
        hasCompletedPostInvestigation = true
        postInvestigationContent = nil
        self.entranceContent = entranceContent()
        _isEntrancePresented = State(initialValue: hasCompletedInvestigation)
        _isInvestigationPresented = State(initialValue: !hasCompletedInvestigation)
        _isPostInvestigationPresented = State(initialValue: false)
    }

    init<PostInvestigationContent: View>(
        sceneController: RealitySceneController,
        configuration: InvestigationConfiguration,
        hasCompletedInvestigation: Bool,
        hasCompletedPostInvestigation: Bool,
        @ViewBuilder postInvestigationContent: @escaping (@escaping () -> Void) -> PostInvestigationContent,
        @ViewBuilder entranceContent: () -> EntranceContent
    ) {
        self.sceneController = sceneController
        self.configuration = configuration
        self.hasCompletedInvestigation = hasCompletedInvestigation
        self.hasCompletedPostInvestigation = hasCompletedPostInvestigation
        self.postInvestigationContent = { completion in
            AnyView(postInvestigationContent(completion))
        }
        self.entranceContent = entranceContent()

        let shouldPresentPostInvestigation = hasCompletedInvestigation
            && !hasCompletedPostInvestigation
        _isEntrancePresented = State(
            initialValue: hasCompletedInvestigation && !shouldPresentPostInvestigation
        )
        _isInvestigationPresented = State(initialValue: !hasCompletedInvestigation)
        _isPostInvestigationPresented = State(initialValue: shouldPresentPostInvestigation)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if isEntrancePresented {
                    entranceContent
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                        .zIndex(2)
                } else if isPostInvestigationPresented,
                          let postInvestigationContent {
                    postInvestigationContent(completePostInvestigation)
                        .transition(.opacity)
                        .zIndex(2)
                } else if isInvestigationPresented {
                    InvestigationView(
                        sceneController: sceneController,
                        configuration: configuration,
                        onCompletion: completeInvestigation
                    )
                    .zIndex(1)
                }

                if isBossRevealTransition {
                    Color.black
                        .opacity(0.12)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .animation(
            appSettings.reducedMotion ? nil : .easeInOut(duration: 0.22),
            value: isBossRevealTransition
        )
        .onAppear {
            isActive = true
            revealGeneration += 1
            let shouldPresentPostInvestigation = hasCompletedInvestigation
                && !hasCompletedPostInvestigation
                && postInvestigationContent != nil
            isEntrancePresented = hasCompletedInvestigation && !shouldPresentPostInvestigation
            isInvestigationPresented = !hasCompletedInvestigation
            isPostInvestigationPresented = shouldPresentPostInvestigation
            sceneController.setEnemyPreviewVisible(isEntrancePresented)

            if isEntrancePresented {
                sceneController.centerAndLockEntranceCamera(
                    previewYaw: configuration.enemyPreviewCameraYaw,
                    reducedMotion: true,
                    completion: {}
                )
            }
        }
        .onDisappear {
            isActive = false
            revealGeneration += 1
            entranceRevealTask?.cancel()
            entranceRevealTask = nil
            sceneController.setEnemyPreviewVisible(true)
            sceneController.resetBattleCamera(animated: false)
        }
    }

    private func completeInvestigation() {
        guard isActive else { return }
        var immediateRemoval = Transaction(animation: nil)
        immediateRemoval.disablesAnimations = true
        withTransaction(immediateRemoval) {
            isInvestigationPresented = false
        }

        if !hasCompletedPostInvestigation,
           postInvestigationContent != nil {
            sceneController.setEnemyPreviewVisible(false)
            withAnimation(appSettings.reducedMotion ? nil : .easeInOut(duration: 0.3)) {
                isPostInvestigationPresented = true
            }
            return
        }

        presentEntrance()
    }

    private func completePostInvestigation() {
        guard isActive else { return }
        var immediateRemoval = Transaction(animation: nil)
        immediateRemoval.disablesAnimations = true
        withTransaction(immediateRemoval) {
            isPostInvestigationPresented = false
        }

        presentEntrance()
    }

    private func presentEntrance() {
        guard isActive else { return }
        let generation = revealGeneration
        sceneController.centerAndLockEntranceCamera(
            previewYaw: configuration.enemyPreviewCameraYaw,
            reducedMotion: appSettings.reducedMotion
        ) {
            guard isActive, revealGeneration == generation else { return }
            entranceRevealTask?.cancel()
            if appSettings.reducedMotion {
                isEntrancePresented = true
                sceneController.revealEnemyPreview(reducedMotion: true)
                return
            }

            entranceRevealTask = Task { @MainActor in
                withAnimation(.easeOut(duration: 0.16)) {
                    isBossRevealTransition = true
                }

                guard await waitForReveal(milliseconds: 120),
                      isActive, revealGeneration == generation else { return }
                sceneController.revealEnemyPreview(reducedMotion: false)

                guard await waitForReveal(milliseconds: 220),
                      isActive, revealGeneration == generation else { return }
                withAnimation(.easeOut(duration: 0.58)) {
                    isEntrancePresented = true
                }

                guard await waitForReveal(milliseconds: 160),
                      isActive, revealGeneration == generation else { return }
                withAnimation(.easeIn(duration: 0.38)) {
                    isBossRevealTransition = false
                }
            }
        }
    }

    private func waitForReveal(milliseconds: Int) async -> Bool {
        do {
            try await Task.sleep(for: .milliseconds(milliseconds))
            return !Task.isCancelled
        } catch {
            return false
        }
    }
}
