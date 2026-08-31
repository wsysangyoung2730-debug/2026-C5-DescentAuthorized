import SwiftUI

struct Floor8DescentDoorView: View {
    let sceneController: RealitySceneController
    @Binding var retryLoadingPresentation: SceneRetryLoadingPresentation?

    var body: some View {
        DescentDoorSceneView(
            configuration: .floor8,
            sceneController: sceneController,
            retryLoadingPresentation: $retryLoadingPresentation
        )
    }
}
