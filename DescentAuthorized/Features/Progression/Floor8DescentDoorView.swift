import SwiftUI

struct Floor8DescentDoorView: View {
    let sceneController: RealitySceneController

    var body: some View {
        DescentDoorSceneView(
            configuration: .floor8,
            sceneController: sceneController
        )
    }
}
