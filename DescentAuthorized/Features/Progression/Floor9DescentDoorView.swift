import SwiftUI

struct Floor9DescentDoorView: View {
    let sceneController: RealitySceneController

    var body: some View {
        DescentDoorSceneView(
            configuration: .floor9,
            sceneController: sceneController
        )
    }
}
