# 4~1층 구현 현황 · 2026-09-23

상태: 로컬 코드 구현 및 제한된 검사 완료. 전체 앱 실행·실기기 화면 검수·밸런스·출시 승인은 미완료.

- 실제 저장소: `/Users/sangyoung/Desktop/2026-C5-DescentAuthorized`
- 통합 브랜치: `feat/#147-floors-4-1-integration`
- 설계 원문: [FLOORS_4_1_GAMEPLAY_DESIGN.md](FLOORS_4_1_GAMEPLAY_DESIGN.md)
- 작업 계획: [FLOORS_4_1_IMPLEMENTATION_PLAN.md](FLOORS_4_1_IMPLEMENTATION_PLAN.md)
- Blender/GLB/USDZ 제작·수정 제외. 원격 푸시하지 않음.
- 번호 정리: 기존 로컬 #139·#140 다음으로 기획·구현 7개 브랜치에 #141~#147을 지정했다. GitHub 이슈는 생성하지 않았으며 이슈 등록 시 실제 번호와 동기화해야 한다. 이미 원격에 있는 과거 무번호 통합 브랜치는 변경하지 않았다.

## 1. 구현 범위

### 진행·저장

- 5층 하강 후 4층 입구에서 시작하여 1층 최종 인계까지 연결.
- 층마다 잔류체 A → 조사 → 잔류체 B → 중간문 → 관리자. A/B는 별도 적·HP·전투이며, B 재도전 시 A를 반복하지 않음.
- 4·3층 기록 보상과 4·3·2층 관리자 보상, 총 5지점. 후보는 첫 진입 시 저장하고 선택·학습 완료 후 지급.
- 이미 배운 주문의 중복 제안을 피하고 미선택 신규 주문을 후속 후보에서 재제안.
- 하강 승인 문양은 층별 3개, 총 12개. 성공마다 저장하며 재진입·실패 시 이전 성공 유지.
- 보상 선택 중·학습 중·승인 중 재개, 하위 층 체크포인트, 구간 이동 시 이전 보상에 맞춘 학습 상태 복원.
- 저장 버전 7. 이전 4층 `complete` 저장은 4층 입구로 복원.
- 1층 최종 기록 후 세 승인과 출구를 거쳐 다른 탑의 10층으로 인계. 새 탑 전체 플레이는 이번 범위가 아님.

### 주문·편성

- 신규 금서 4종: 혈인 관통, 한계 방벽, 집행 무효, 직격 금지.
- 신규 2획 봉인 주문 4종: 책임 절단, 격리 방벽, 축압 방출, 인계 방벽.
- 전체 주문 28종. 신규 문양은 판정·입력·시연·미리보기에서 같은 경로를 사용.
- 출전 최대 6종 안에서 금서 최대 2종. 세 번째 금서는 학습 보관되며 기존 장착 금서를 자동 교체하지 않음. 봉인 주문은 금서 수에서 제외.
- HP 대가는 성공 시에만 적용. 절대 방벽에 차단된 축압 방출은 자기 방벽을 소비하지 않음.
- 신규 2획의 두 경로 완성, 예약 묶음 취소, 예약 1건 보호, 반격 완화, 첫 피해 후 방벽 재생을 실제 전투 효과에 연결.

### 전투

| 층 | 잔류체 A / B HP | 관리자 HP | 중심 규칙 |
|---|---:|---:|---|
| 4 | 190 / 220 | 600 | 기록·모사·조건부 반격 |
| 3 | 210 / 240 | 660 | 봉인할 주문 선택·격리 예약 |
| 2 | 230 / 260 | 720 | 고정 증폭·예약·방벽 조건·반격 |
| 1 | 250 / 280 | 800 | 기록·봉인·예약·다단 직접 공격, 3단계 전환 |

- 4~1층은 매 턴 3획·마나 150. 마나는 시험값이며 기존 5층 이상 2획·100은 변경하지 않음.
- 관리자 단계는 HP 임계치 아래에서 다음 패턴 주기에 전환. 최종 관리자는 70%·35%에서 2·3단계로 전환하며 HP를 초기화하지 않음.
- 예약 피해가 남으면 새 주기 시작 전에 처리. 피해는 직접 → 도착 예약 → 모사·반격 → 상태 만료 순서.
- 봉인 대상 선택이 필요한 동안 시전·턴 넘기기를 막고 기본 대응 주문을 보호.

## 2. UI 연결

- 승인된 `Floors_4_1_Enemies_v1`의 원본 12이미지를 앱 에셋으로 등록. 여성 v2는 사용하지 않음.
- 기존 조사 앵커, 금색 패널, 버튼판, 입력판, 두루마리 해독·습득 완료 에셋과 화면 재사용.
- 조사·준비·편성·조우·전투·패배 재도전·처치·기록/관리자 보상·중간문·하강·최종 기록·결말을 실제 진행 상태에 연결.
- 후반 화면은 명시적 2D 경로. 5층 Reality 장면으로 잘못 매핑하거나 존재하지 않는 적/보상 3D 준비를 기다리지 않음.
- 전투에 단계·피해 종류·예약 순서·반격·봉인 선택·보호 지속 시간·특수 방벽 상태 표시.
- 편성 금서 `현재/2`와 제한 사유 표시. 후반 보상 선택에서 선택 주문의 시험 각인 가능.
- 연습·하강 입력은 기존 획순 시연과 포인트 피드백을 재사용. 승인별 입력 상태를 새로 시작.
- 전체 방의 3D 배치·카메라 이동·신규 적 3D 모션은 구현 완료 범위가 아님.

주요 코드: `Core/Content/LowerFloor*`, `Core/Progression/LowerFloorProgress.swift`, `GameProgressionController.swift`, `Core/CombatEngine/`, `Features/Progression/LowerFloorFlowView.swift`, `RewardSelectionView.swift`, `Features/Battle/`, `App/ExpansionPreviewSupport.swift`.

## 3. 브랜치·세부 커밋

앞선 작업을 이어받는 순차 브랜치로 구성하고 마지막 통합 브랜치에 모았다. 개별 브랜치와 커밋은 보존되어 있다.

| 브랜치 | 커밋 | 내용 |
|---|---|---|
| `docs/#141-floors-4-1-combat-plan` | `ab33c2e` | 구현 이전 상세 기획 |
| `feat/#142-floors-4-1-foundation` | `36d828f`, `47da203` | 계획, 공통 ID·저장 계약 |
| `feat/#143-floors-4-1-spells` | `ffbaab3`, `39d2411` | 8주문, 결정적 보상 후보, 하강 12문양 |
| `feat/#144-floors-4-1-combat` | `5fafd8d` | 12적·관리자 단계·피해 종류·신규 효과 |
| `feat/#145-floors-4-1-progression` | `664a0b5` | A/B·보상·저장·3승인·인계·편성 제한 |
| `feat/#146-floors-4-1-ui` | `26b1a59` | 원본 이미지, 후반 2D 화면·전투 선택·미리보기 |
| `feat/#147-floors-4-1-integration` | `58b8b66` | Xcode 파일 등록, 구간 재생 정리, 시험 각인·표시 수정 |
| `feat/#147-floors-4-1-integration` | `8617ed2` | 후반 규칙·저장·구간 이동 검사 |

이 문서를 포함한 별도 문서 커밋으로 최종 인계 상태를 기록한다.

## 4. 실행한 제한적 확인

- Xcode 도구 체인을 사용한 코어 Swift 패키지 컴파일: 성공.
- iOS 18 simulator arm64 대상 전체 앱 Swift 소스 타입 검사: 성공. 앱 번들 빌드·설치·실행은 아님.
- Xcode 프로젝트 파일 형식 검사: 성공.
- 선택한 5개 검사 묶음 **36개 성공, 실패 0**:
  - `LowerFloorTests` 17개: 신규 문양 기준 경로, 3획·자원, 금서 제한, HP 대가, 예약·반격·피해 순서, 방벽, 관리자 단계, 전체 하위 층 전이, 보상/승인 저장, B 재도전.
  - `ExpansionIntegrationTests` 4개: 기존 확장 층과 4층 연결.
  - `ExpansionProgressTests` 5개: 편성·저장 호환.
  - `CheckpointReplayTests` 6개: 모든 체크포인트 복원·보상 변경·구간 재생.
  - `ExpansionSceneRouteTests` 4개: 상층 장면 유지 및 하층 3D 오진입 방지.
- 사용한 테스트 필터: `LowerFloorTests|ExpansionIntegrationTests|ExpansionProgressTests|CheckpointReplayTests|ExpansionSceneRouteTests`.
- 기존 RealityKit API 폐기 예정·격리 관련 경고가 남아 있다. 이번 변경으로 전체 경고 해소를 주장하지 않음.

전체 테스트·전체 앱 빌드·시뮬레이터/실기기 UI 검수는 사용자 요청에 따라 진행하지 않았다. 위 전이 검사는 승리·승인 명령을 직접 제출하는 코어 검사이며 실제 손 입력 완주·밸런스 검증을 대신하지 않는다.

## 5. 다음 UI 확인 경로 (아직 미실행)

DEBUG 실행 인수는 메모리 저장소를 사용하며 실제 사용자 저장을 읽거나 덮어쓰지 않는다. 아래는 실행 가능한 확인용 진입 설정이지 검수 완료 기록이 아니다.

| 확인 화면 | 실행 인수 예 |
|---|---|
| 4층 입구 조사 | `--preview-floor 4 --preview-stage entrance` |
| 4층 B 준비 | `--preview-floor 4 --preview-residual 1` |
| 관리자 조우 진입 | `--preview-floor 3 --preview-boss --preview-battle` |
| 기록 보상/시험 각인 | `--preview-floor 4 --preview-stage recordReward` |
| 관리자 보상 | `--preview-floor 2 --preview-stage reward` |
| 금서 2종 제한·전체 주문 편성 | `--preview-floor 4 --preview-all-spells` |
| 승인 2개 후 재진입 | `--preview-floor 2 --preview-stage descent --preview-approvals 2` |
| 최종 기록 | `--preview-floor 1 --preview-stage finalRecord` |
| 인계 결말 | `--preview-floor 1 --preview-stage complete` |

수동 검수 시 가로 iPad의 조사 패널·카드·설명 넘침, Pencil/손가락 2획 시작점, 입력 시연·포인트음, HUD·일시정지, 봉인 선택, 예약 대상 선택, 보상 학습 도중 재개, 승인 3개 저장, 패배 후 A/B 구분, 동작 줄이기를 확인한다. 다음 단계에 앱 실행 검수와 난이도 조정을 분리해서 진행한다.
