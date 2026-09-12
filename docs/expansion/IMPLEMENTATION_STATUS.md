# 7–5층 확장 구현 및 인수인계

최종 정리: 2026-09-12. 계획한 #97~#104 프로토타입 구현 완료. 현재 `feat/#104-expansion-integration`은 앞선 브랜치의 변경을 모두 포함한다. 마지막 실행 코드 커밋은 `ad8e982`, 이 문서는 그 다음 커밋이다.

## 브랜치별 완료 지점

기준은 `origin/fix/#96-three-floor-polish`의 `f1cec95`. 각 브랜치는 직전 번호의 완료 커밋을 이어받았다. 기준 브랜치를 병합하거나 덮어쓰지 않았다.

| 브랜치 | 완료 내용 | 커밋 |
|---|---|---|
| `feat/#97-floors75-foundation` | 저장 호환, 확장 진행, 6개 편성·보호 주문 | `9cbcb91` |
| `feat/#98-combat-effects` | 상태·예약 피해·대상 선택·모사·봉인 처리 | `0840ee7` |
| `feat/#99-spells-and-rewards` | 주문 20종·마법진·9~5층 선택 보상·기존 보상 이행 | `f80a518` |
| `feat/#100-loadout-and-battle-ui` | 출전 준비·6개 카드·재편성·상태 UI | `9d5c556` |
| `feat/#101-floor7-playable` | 교정 패턴 / 2단계 하강 저장 / 임시 무대 UI / 전체 흐름 | `a8f53a2`, `caabd4e`, `e89b9bc`, `a981537` |
| `feat/#102-floor6-causality` | 인과·예약 패턴 / 고정 학습·단계별 안내 | `eeb249c`, `cdb8597` |
| `feat/#103-floor5-memory` | 기록·모사·카드 봉인 / 규칙 안내 | `739437e`, `a99c2e6` |
| `feat/#104-expansion-integration` | 카탈로그·호환 검증 / 저장 분리 미리보기 / 일시정지 안내 / 인수인계 | `a1f33d7`, `46623a5`, `ad8e982`, 이후 문서 커밋 |

후속 작업도 같은 브랜치 안에서 기능 단위로 나누어 커밋한다. 현재 #97~#104는 로컬에 보존되어 있다. 원격 업로드는 자동 승인 검토에서 명시적 승인 부족으로 거부되어 수행되지 않았다. GitHub 업로드는 사용자의 해당 작업 승인 후 진행한다.

## 실제 동작하는 범위

- 기존 8층 하강 이후 7층 입구로 연결한다. 7·6·5층 모두 준비 → 잔류체 → 봉인 해제 → 보스 준비·전투 → 보상 선택·학습 → 2단계 하강 승인이 동작한다. 4층 입구 완료 화면에서 종료하며 4층 전투는 범위 밖이다.
- 공격·방어·해제·디버프 4개 카테고리와 봉인·낡은·각인·금서 등급을 반영한 주문 20종. 기존 5종과 신규 15종의 실제 마법진·효과를 연결했다.
- 9~5층 보스 보상은 층마다 주문 3개 중 1개 선택. 선택 전 시험 각인, 선택 후 실제 학습 성공으로 획득한다. 6층 출력 저하만 고정 추가 학습하며 7·5층 별도 드롭은 없다. 정상 진행 최종 보유 10종, 전체 카탈로그 20종.
- 턴당 2획·마나 100. 전투 전 출전 준비에서만 최대 6개 주문과 순서를 편성한다. 봉인 해제와 공격·방어 각 1개 필수. 보호 공격·방어·봉인 해제는 5층 카드 봉인에서 제외한다.
- 최초 6개 편성·보유 주문 초과 안내, 6층 증폭·예약·대응·결과 안내, 5층 기록·봉인 안내를 저장 플래그와 연결했다.
- 재도전은 HP 100으로 출전 준비에 복귀한다. 전투 중 종료 후 재접속도 준비 단계에서 재개한다.

## 층별 패턴

| 층 | 잔류체 | 관리자 |
|---|---|---|
| 7 | HP 160. 기본 공격·교정 방벽 18·강타 28(방벽 파괴 시 10)·빈틈 | HP 380. 방벽 30·강타 40(파괴 시 16). 2페이즈 방벽 40·강타 48(파괴 시 20), 첫 주기 절대 방어 1회 |
| 6 | HP 180. 증폭 150%·기본값 24 예약·약공격 10·예약 실행 | HP 420. 증폭·기본값 32 예약·약공격 12. 2페이즈 기본값 34와 16을 다른 턴에 예약, 약공격 14 |
| 5 | HP 180. 성공 주문 기록·재사용 반응(12+추가 12)·다음 턴 피해 36 예약 | HP 450. 카테고리 반응(14+추가 12)·비보호 주문 1개 봉인·피해 40 예약. 2페이즈 18+추가 16·봉인 2개·예약 48 |

6·5층 적은 별도 기본·절대 방어막을 쓰지 않는다. 증폭·예약·모사·봉인은 상태로 표시한다. 체력 절반 이하의 다음 주기에서 2페이즈로 전환한다.

예약은 등록 시 증폭을 확정하고 실행 시 감소 효과·방벽을 적용한다. 같은 예약은 한 번만 지연할 수 있다. 대기 행동에서 예약 피해를 중복 적용하지 않는다. 모사 추가 반응은 주기 내 1회이고 피해를 지연해도 카드 봉인 해제 시점은 늘어나지 않는다.

## 저장·파일 구조

최종 저장 버전은 **5**. 편성·보호 주문·안내·확장 필드의 기본값과 정규화, 기존 보상 ID 이행을 지원한다. 아직 학습하지 않은 선택 보상은 자동 학습시키지 않는다. 1차 하강 승인 후 재접속해도 승인을 유지한다.

기존 체크포인트 `.demoComplete`를 기준으로 별도 `ExpansionProgress`에 실제 층·단계·승인을 저장한다. 화면은 `displayedFloorNumber`를 사용한다. 저장 복원 실패 시 원본을 덮어쓰지 않고 메모리 저장으로 복구하며 명시적 새 게임 전까지 원본을 보호한다.

주요 파일(저장소 기준):

- 기획: 이 폴더의 `Floors_7_5_Gameplay_Design_v3.md`, `Spell_Catalog_20_Proposal_v2.md`, `Floors_7_5_Implementation_Plan.md`.
- 진행·편성: `DescentAuthorized/Core/Progression/ExpansionProgress.swift`, `GameProgressionController.swift`.
- 전투: `DescentAuthorized/Core/Content/ExpansionEnemyCatalog.swift`, `Core/CombatEngine/ExpansionCombatModels.swift`, `CombatEngine.swift`.
- 주문·보상: `DescentAuthorized/Core/Content/SpellCatalog.swift`, `RewardCatalog.swift`.
- 화면: `DescentAuthorized/Features/Progression/ExpansionFlowView.swift`, `LoadoutPreparationView.swift`, `ExpansionBackdropView.swift`.
- 공통 전투 화면: `DescentAuthorized/Features/Battle/BattleView.swift`, `ExpansionCombatStatusView.swift`, `ExpansionCombatGuideView.swift`.
- Debug 미리보기: `DescentAuthorized/App/ExpansionPreviewSupport.swift`.

## 검증 결과

- Swift 코어 및 iPad 시뮬레이터 앱 빌드 성공. 최종 앱 빌드는 `46623a5`에서 확인했다. 이후 `ad8e982`는 일시정지 위치명·안내만 변경했다.
- 확장 핵심 7개 테스트 통과: 20종 마법진·카탈로그·저장 이행·편성·예약·지연·모사·봉인·7→6→5→4 진행 및 승인 저장.
- 영향받은 기존 테스트 포함 45개를 선택 실행했다. 예전 임시 보상·즉시 재시작을 가정한 테스트 기대값을 수정하고 영향받은 24개를 재실행하여 모두 통과했다. 나머지 21개는 앞선 실행에서 통과했다. 무관한 전체 테스트는 반복하지 않았다.
- iPad Pro 13인치 시뮬레이터에서 6층 출전 준비(8종 보유·6종 편성·보호 선택)와 실제 전투 진입을 확인했다. HUD·6개 카드·마법진 입력판·적 이미지가 표시된다.
- 모든 층의 수동 연속 클리어와 장시간 밸런스 플레이까지 완료한 것은 아니다.

임시 로그: `/tmp/c5-app-build104.log`, `/tmp/c5-expansion-tests.log`, `/tmp/c5-compatibility-recheck.log`. 임시 파일의 보존은 보장하지 않는다.

### 재실행

저장소 루트에서 Xcode 경로를 명시한다.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer CLANG_MODULE_CACHE_PATH=/tmp/c5-module-cache swift build --scratch-path /tmp/c5-expansion-build --disable-sandbox

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer CLANG_MODULE_CACHE_PATH=/tmp/c5-module-cache swift test --scratch-path /tmp/c5-expansion-build --disable-sandbox --filter 'ExpansionIntegrationTests|ExpansionProgressTests'

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project DescentAuthorized.xcodeproj -scheme DescentAuthorized -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/c5-expansion-derived CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES ARCHS=arm64 build
```

Xcode Debug 실행 인수 `--preview-floor 6`으로 출전 준비를 바로 연다(5·6·7 지원). `--preview-boss`는 관리자 준비, `--preview-battle`은 즉시 전투 진입이다. 메모리 저장만 사용해 실제 저장·업적을 변경하지 않는다. 인수를 제거하면 정상 진행으로 돌아간다. Release에는 이 도우미가 없다.

## 남겨둔 범위와 다음 작업

1. 3D 모델·방 배경·전용 애니메이션·음악은 후순위다. 승인된 컨셉 이미지 6장을 사용하며 UI·입력·수치·진행은 실제 동작한다.
2. 다음 단계는 새 게임·기존 8층 완료 저장으로 전체 플레이를 진행하며 피해량·전투 길이·주문 유용성을 조정하는 일이다. 카테고리·규칙을 임의로 늘리지 않는다.
3. 3D 교체는 `ExpansionBackdropView` 및 전투 무대를 중심으로 진행하고 전투·저장 규칙을 유지한다.
4. 후속 변경은 #104 완료 커밋을 이어받고 세부 커밋을 유지한다. 새 번호는 다음 요청에 따른다.

기존 미추적 `docs/RUNE_TOWER_PRD.md`는 수정·커밋하지 않았다. 상위 프로젝트의 `sources/`는 읽기 전용이다.
