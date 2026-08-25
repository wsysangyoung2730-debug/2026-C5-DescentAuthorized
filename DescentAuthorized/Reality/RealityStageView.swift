import RealityKit
import SwiftUI

struct RealityStageView: View {
    let sceneID: FloorSceneID
    var cameraPreset: RealityCameraPreset = .main
    var erasureZones: [ErasureZone] = []
    @ObservedObject var controller: RealitySceneController

    var body: some View {
        ZStack {
            RealityARView(controller: controller)
                .ignoresSafeArea()

            switch controller.loadState {
            case .idle, .loading:
                statusOverlay(icon: nil, title: "층 기록 불러오는 중", detail: nil)
            case let .failed(_, message):
                statusOverlay(
                    icon: "exclamationmark.triangle",
                    title: "장면 승인 반려",
                    detail: message
                )
            case .ready:
                EmptyView()
            }
        }
        .background(Color.black)
        .onAppear {
            controller.load(sceneID: sceneID, cameraPreset: cameraPreset)
            controller.setErasureZones(erasureZones)
        }
        .onChange(of: sceneID) { _, value in
            controller.load(sceneID: value, cameraPreset: cameraPreset)
        }
        .onChange(of: cameraPreset) { _, value in controller.applyCameraPreset(value) }
        .onChange(of: erasureZones) { _, value in controller.setErasureZones(value) }
    }

    private func statusOverlay(icon: String?, title: String, detail: String?) -> some View {
        ZStack {
            Color(red: 0.03, green: 0.04, blue: 0.06).opacity(0.92)
            VStack(spacing: 11) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(Color(red: 0.77, green: 0.27, blue: 0.25))
                } else {
                    ProgressView().tint(Color(red: 0.48, green: 0.36, blue: 0.83))
                }
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color(red: 0.85, green: 0.89, blue: 0.91))
                if let detail {
                    Text(detail)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color(red: 0.49, green: 0.55, blue: 0.61))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                }
            }
            .padding(24)
        }
        .allowsHitTesting(false)
    }
}

private struct RealityARView: UIViewRepresentable {
    let controller: RealitySceneController

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        view.environment.background = .color(.black)
        view.renderOptions.insert(.disableMotionBlur)
        controller.attach(to: view)
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        controller.attach(to: uiView)
    }
}
