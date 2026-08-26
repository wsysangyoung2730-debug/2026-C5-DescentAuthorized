import RealityKit
import SwiftUI

enum LoadingScreenContext: Equatable {
    case startup
    case floor10
    case floor9
    case floor8

    init(sceneID: FloorSceneID) {
        switch sceneID {
        case .floor10ClosedOffice:
            self = .floor10
        case .floor09ArchiveRedesign:
            self = .floor9
        case .floor08ResidueIsolation, .floor08AdministratorObservatory:
            self = .floor8
        }
    }

    var backgroundImageName: String {
        switch self {
        case .startup: "LoadingMain"
        case .floor10: "LoadingFloor10"
        case .floor9: "LoadingFloor09"
        case .floor8: "LoadingFloor08"
        }
    }
}

enum LoadingTipCatalog {
    private static let general = [
        "문양은 정확하게 그릴수록 주문 효과가 강해집니다.",
        "정해진 획 수를 지켜야 주문이 정상적으로 완성됩니다.",
        "남은 마나와 행동 횟수를 확인한 뒤 주문을 선택하십시오.",
        "적의 다음 행동은 화면 상단의 의도 표시에서 확인할 수 있습니다."
    ]

    private static let floor9 = [
        "일반 방벽은 체력보다 먼저 피해를 흡수합니다.",
        "방벽 관통 주문은 적의 일반 방벽을 무너뜨리는 데 효과적입니다.",
        "강력한 주문은 여러 획과 행동 횟수를 요구할 수 있습니다.",
        "적의 강한 공격이 예고되면 방어 주문을 준비하십시오.",
        "말소 구역을 통과한 획은 추가 마나를 요구합니다.",
        "전투가 길어질수록 마나 관리가 중요해집니다.",
        "선택하지 않은 주문 기록은 복원 절차가 끝나면 말소됩니다.",
        "두루마리의 등급과 주문 유형을 확인한 뒤 선택하십시오.",
        "복원한 주문은 이후 전투와 하강 절차에 영향을 줄 수 있습니다.",
        "하강문은 승인 문양이 정확히 완성되어야 열립니다.",
        "하강 승인 문양은 층이 내려갈수록 복잡해집니다.",
        "문이 열리는 동안에는 하강 절차가 완료될 때까지 기다리십시오."
    ]

    private static let floor8 = [
        "절대 방벽이 유지되는 동안에는 공격 피해가 차단됩니다.",
        "봉인 해제는 절대 방벽의 충전을 제거할 수 있습니다."
    ]

    static func randomTip(for context: LoadingScreenContext) -> String {
        let candidates: [String]
        switch context {
        case .startup, .floor10:
            candidates = general
        case .floor9:
            candidates = general + floor9
        case .floor8:
            candidates = general + floor9 + floor8
        }
        return candidates.randomElement() ?? general[0]
    }
}

struct LoadingScreenView: View {
    let context: LoadingScreenContext
    let progress: Double
    let tip: String

    private var normalizedProgress: Double {
        min(max(progress, 0), 1)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.45)) { timeline in
            GeometryReader { proxy in
                ZStack {
                    Image(context.backgroundImageName)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()

                    LinearGradient(
                        colors: [.clear, .black.opacity(0.76)],
                        startPoint: .center,
                        endPoint: .bottom
                    )

                    VStack(spacing: 14) {
                        Spacer()

                        HStack(alignment: .lastTextBaseline, spacing: 24) {
                            Text("Tip : \(tip)")
                                .font(.system(size: 18, weight: .medium))
                                .lineLimit(2)

                            Spacer(minLength: 24)

                            Text(loadingText(at: timeline.date))
                                .font(.system(size: 34, weight: .regular))
                                .monospacedDigit()
                        }

                        GeometryReader { progressProxy in
                            ZStack(alignment: .leading) {
                                Rectangle()
                                    .fill(.white.opacity(0.28))
                                Rectangle()
                                    .fill(.white)
                                    .frame(
                                        width: progressProxy.size.width * normalizedProgress
                                    )
                            }
                        }
                        .frame(height: 10)
                        .animation(.linear(duration: 0.22), value: normalizedProgress)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 34)
                    .padding(.bottom, 30)
                }
            }
        }
        .background(Color.black)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("로딩 중. \(tip)")
        .accessibilityValue("\(Int(normalizedProgress * 100))퍼센트")
    }

    private func loadingText(at date: Date) -> String {
        let dotCount = Int(date.timeIntervalSinceReferenceDate / 0.45) % 3 + 1
        return "Loading" + String(repeating: ".", count: dotCount)
    }
}

struct RealityStageView: View {
    let sceneID: FloorSceneID
    var cameraPreset: RealityCameraPreset = .main
    var erasureZones: [ErasureZone] = []
    @ObservedObject var controller: RealitySceneController
    @State private var loadingTip: String

    init(
        sceneID: FloorSceneID,
        cameraPreset: RealityCameraPreset = .main,
        erasureZones: [ErasureZone] = [],
        controller: RealitySceneController
    ) {
        self.sceneID = sceneID
        self.cameraPreset = cameraPreset
        self.erasureZones = erasureZones
        self.controller = controller
        let context = LoadingScreenContext(sceneID: sceneID)
        _loadingTip = State(initialValue: LoadingTipCatalog.randomTip(for: context))
    }

    var body: some View {
        ZStack {
            RealityARView(
                sceneID: sceneID,
                cameraPreset: cameraPreset,
                erasureZones: erasureZones,
                controller: controller
            )
                .ignoresSafeArea()

            switch controller.loadState {
            case let .ready(readySceneID) where readySceneID == sceneID:
                EmptyView()
            case let .failed(failedSceneID, message) where failedSceneID == sceneID:
                statusOverlay(
                    icon: "exclamationmark.triangle",
                    title: "장면 승인 반려",
                    detail: message
                )
            default:
                LoadingScreenView(
                    context: loadingContext,
                    progress: displayedLoadingProgress,
                    tip: loadingTip
                )
            }
        }
        .background(Color.black)
        .onChange(of: sceneID) { _, newSceneID in
            let context = LoadingScreenContext(sceneID: newSceneID)
            loadingTip = LoadingTipCatalog.randomTip(for: context)
        }
    }

    private var loadingContext: LoadingScreenContext {
        LoadingScreenContext(sceneID: sceneID)
    }

    private var displayedLoadingProgress: Double {
        guard controller.loadState == .loading(sceneID) else { return 0 }
        return controller.loadingProgress
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
    let sceneID: FloorSceneID
    let cameraPreset: RealityCameraPreset
    let erasureZones: [ErasureZone]
    let controller: RealitySceneController

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        view.environment.background = .color(.black)
        view.renderOptions.insert(.disableMotionBlur)
        controller.attach(to: view)
        synchronizePresentation()
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        controller.attach(to: uiView)
        synchronizePresentation()
    }

    private func synchronizePresentation() {
        controller.load(sceneID: sceneID, cameraPreset: cameraPreset)
        controller.setErasureZones(erasureZones)
    }
}
