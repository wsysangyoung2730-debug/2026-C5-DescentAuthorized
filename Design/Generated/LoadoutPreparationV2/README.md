# 전투 준비 UI 추가 이미지 에셋

`feat/#114-loadout-ui-redesign`의 전투 준비 화면을 실제 게임 UI로 마감할 때 필요한 신규 장식 에셋 모음입니다. 모든 PNG는 투명 배경이며, 문자와 주문 문양은 SwiftUI에서 올리는 전제로 제작했습니다.

## 신규 에셋

| 파일 | 용도 | 권장 처리 |
| --- | --- | --- |
| `loadout-main-panel-frame.png` | 전투 편성·보유 주문 영역의 대형 프레임 | 9-slice 또는 resizable cap inset |
| `loadout-inspector-panel-frame.png` | 우측 선택 주문·봉인 보호·전투 시작 영역 | 9-slice 또는 resizable cap inset |
| `loadout-progress-badge.png` | 우측 상단 `5 / 6` 편성 수 배지 | 중앙 숫자는 SwiftUI 텍스트 |
| `loadout-equipped-slot-default.png` | 편성 슬롯 기본 상태 | 주문 문양·순번·자물쇠는 별도 레이어 |
| `loadout-equipped-slot-selected.png` | 편성 슬롯 선택 상태 | 선택 시 금빛·보랏빛 강조 상태 |
| `loadout-equipped-slot-empty.png` | 비어 있는 편성 슬롯 | `+`와 빈 자리 문구는 SwiftUI 텍스트 |
| `loadout-spell-card-default.png` | 보유 주문 가로 카드 기본 상태 | 카드 내용은 SwiftUI 레이어 |
| `loadout-spell-card-selected.png` | 보유 주문 가로 카드 선택 상태 | 선택 표시와 문양은 별도 레이어 |
| `loadout-protection-selector.png` | 공격·방어 주문 보호 선택 행 | 아이콘·주문명·선택 화살표는 별도 레이어 |
| `loadout-back-button.png` | 상단 또는 하단의 돌아가기 버튼 | 화살표·문구는 SwiftUI 레이어 |
| `loadout-battle-start-enabled.png` | 필수 편성 조건을 충족한 전투 시작 버튼 | 흰색 문구와 화살표 사용 |
| `loadout-battle-start-disabled.png` | 주문/보호 주문 등 필수 요소가 빠진 상태 | 탭 차단, 회색 문구와 잠금 안내 사용 |

## 기존 에셋 재사용

- 상단 HUD 프레임: `SharedTopHUDRail`
- 중지·설정 버튼 플레이트: `SharedHUDIconPlate`
- 주문 문양과 주문별 색상
- 기존 전투 카드의 흑요석 질감과 금속 테두리 표현

## 버튼 상태 규칙

- `loadout-battle-start-enabled.png`: 전투 시작에 필요한 편성 및 보호 주문 조건을 모두 만족할 때 사용합니다.
- `loadout-battle-start-disabled.png`: 필수 주문 슬롯이나 보호 주문 지정이 빠졌을 때 사용합니다. 버튼 동작을 막고, 가까운 위치에 누락 이유를 한 줄로 표시합니다.

## 생성 프롬프트 세트

- 공통 스타일: 하강 승인 세계관의 검은 흑요석·그을린 철·낡은 황동, 절제된 보랏빛 마력, 정면 직교 시점, 고해상도 게임 UI, 투명 배경, 텍스트와 로고 제외.
- 프레임: 넓은 주 편성 패널과 세로형 우측 정보 패널을 각각 독립된 테두리 플레이트로 생성.
- 슬롯·카드: 기본, 선택, 빈 상태가 한눈에 구분되도록 테두리 밝기와 보랏빛 활성광을 차등 적용.
- 버튼: 활성 상태는 선명한 황동 테두리와 보랏빛 코너광, 비활성 상태는 채도와 발광을 낮춘 건메탈 표현으로 생성.

생성 방식: OpenAI 내장 이미지 생성.
