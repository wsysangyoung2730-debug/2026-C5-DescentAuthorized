import SwiftUI

extension InvestigationConfiguration {
    static func expansion(floor: Int) -> Self {
        let accent: Color = floor == 7 ? .cyan : floor == 6 ? .orange : .purple
        return Self(
            areaTitle: "제\(floor)층 · 잔류체 구역 조사",
            instruction: "화면을 드래그해 주변을 살피고 두루마리 기록을 모두 확인하세요.",
            recordTitle: "제\(floor)층 조사 기록",
            headerAccent: accent, statusAccent: accent,
            enemyPreviewCameraYaw: 0,
            cameraInteraction: .investigation(maximumYawDegrees: 65),
            clues: ExpansionInvestigationCatalog.records(for: floor).enumerated().map { index, record in
                InvestigationClue(
                    id: record.id, recordID: record.id,
                    markerTitle: record.title, title: record.title,
                    detectionText: record.detection, body: record.body,
                    icon: "scroll", accent: accent,
                    distanceScale: 0.9,
                    panelHorizontalDirection: index == 0 ? 1 : -1,
                    panelVerticalOffset: index == 0 ? -24 : 24,
                    presentation: .sideUnfold,
                    recordTag: record.tag, recordTagIcon: "doc.text.magnifyingglass"
                )
            },
            completionAction: nil, tutorial: nil
        )
    }
}
