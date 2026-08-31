import SwiftUI

struct Floor9DescentDoorView: View {
    let sceneController: RealitySceneController
    @Binding var retryLoadingPresentation: SceneRetryLoadingPresentation?

    var body: some View {
        DescentDoorSceneView(
            configuration: .floor9,
            sceneController: sceneController,
            retryLoadingPresentation: $retryLoadingPresentation
        )
    }
}
