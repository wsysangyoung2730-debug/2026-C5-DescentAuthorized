# #209 최종 하강 기록 크레딧

## 브랜치와 범위

- 브랜치: `feat/#209-ending-credits`
- 기준: `b072952` (`docs/#208-app-store-readiness`, #207까지의 게임 변경 포함)
- 이슈: https://github.com/wsysangyoung2730-debug/2026-C5-DescentAuthorized/issues/209
- 이번 작업은 엔딩 표시와 제어만 변경한다. 전투, 보상, 저장 구조, 완료 판정은 유지한다.

## 최종 흐름

1. 기존 1층 최종 승인 완료 및 신규 탑 인계 대화 5개를 유지한다.
2. 대화가 끝나면 `하강 기록`이 나타나고 10층부터 1층까지 위로 스크롤한다.
3. 인계 기록과 현재 동의에 관한 마지막 문장이 이어진다.
4. 최하단의 `Made by SangYoung Woo`와 `확인`에서 멈춘다.
5. 확인을 눌러야 타이틀로 돌아간다. 완료된 저장에서 계속하기를 선택하면 엔딩을 다시 볼 수 있다.

상단은 SwiftUI 기본 툴바의 일시정지·설정 버튼을 사용한다. 일시정지는 기존 일시정지 메뉴, 설정은 기존 설정 화면에 연결한다. 엔딩에서 기존 전투 HUD를 숨겨 겹치는 방식 대신 엔딩 전용 표시 경로를 사용한다.

## 스크롤과 접근성

- 기본 자동 스크롤은 전체 길이 기준 약 90초다. 손으로 위아래 스크롤할 수 있다.
- 일시정지·설정·앱 비활성 상태와 직접 스크롤/감속 중에는 자동 이동을 중단한다.
- 재개 시 지난 시간을 한 번에 적용하지 않는다. 지연된 프레임도 0.1초까지만 반영한다.
- 앱 또는 시스템의 동작 줄이기, VoiceOver 사용 중에는 자동 이동을 끄고 수동 읽기를 제공한다.
- 마지막 버튼은 중복 실행을 막으며 자동 타이틀 이동은 없다.

## 구현 및 검증

- `EndingCreditsCatalog.swift`: 승인된 층별 문구, 인계 기록, 제작자 표기.
- `EndingCreditsPlayback.swift`: 실제 스크롤 위치와 길이에 따른 정지·재개·종점 처리.
- `EndingCreditsView.swift`: 기본 스크롤 뷰, 제작자·확인 화면.
- `DemoFlowView.swift`: 실제 `.towerHandoff` 종료 경로와 기본 툴바 연결.
- 코어 테스트 **242개 통과**. 추가한 7개는 정지, 재개 시 시간 누적 방지, 종점 고정, 직접 스크롤, 레이아웃 변경, 잘못된 값의 방어를 검사한다.
- Xcode 26.5 / iOS Simulator 26.5 Debug 빌드 성공.

실제 화면 검증은 별도 iPad mini (A17 Pro) 시뮬레이터 `D3C05D26-D233-4384-9F45-0091D1FCE3A9`에서 수행했다. `--preview-floor 1 --preview-stage complete`는 기존 인메모리 프리뷰를 사용하며 실제 진행 저장과 Game Center 보고를 변경하지 않는다.

| 실제 화면 확인 | 결과 | 증거 |
| --- | --- | --- |
| 인계 대화 종료 → 층별 기록 자동 이동 | 통과 | [스크롤 중 화면](evidence/credits-rolling.png) |
| 상단 일시정지 → 기존 메뉴 → 같은 구간에서 재개 | 통과 | [일시정지 메뉴](evidence/credits-pause.png) |
| 상단 설정 → 기존 설정 화면 → 크레딧 복귀 | 통과 | [설정 화면](evidence/credits-settings.png) |
| 마지막 제작자 문구와 확인 버튼에서 멈춤 | 통과 | [최종 화면](evidence/credits-confirm.png) |
| 확인 → 타이틀, 계속하기 → 엔딩 재진입 | 통과 | [타이틀 복귀](evidence/credits-return-title.png) |

스크린샷은 실제 시뮬레이터 캡처이며 프레임버퍼 방향을 가로로 회전한 것 외에는 수정하지 않았다. 구현 커밋 `25ffd74`의 Debug 빌드를 설치해 확인했다. 독립 코드 검토에서도 확인된 결함은 없었다.

실기기, VoiceOver의 실제 낭독, 시스템 동작 줄이기, 백그라운드 왕복, 전 층 재플레이는 이번 화면 검증 범위에 포함하지 않는다. 완료 프리뷰를 사용했으므로 1층 문양 입력부터 이어지는 전체 플레이를 검증한 것은 아니다. 수동 스크롤은 코어 위치 동기화 테스트를 통과했으나 시뮬레이터 포인터 조작으로 되감기를 확인하지 못해 실제 터치 검증이 남아 있다. 시뮬레이터의 기존 세로 콜드 런치 호환 표시 문제(#208)는 가로 회전 후 검증했다.

## 세부 구현 커밋

- `3fc5a2e`: 층별 하강 기록과 제작자 문구.
- `22e860f`: 스크롤 정지·재개 로직과 7개 테스트.
- `b20bc5b`: 엔딩 화면, 실제 흐름, 기본 상단 버튼 연결.
- `25ffd74`: 엔딩을 전투 HUD 표시 경로에서 분리.

검증 문서와 화면 증거는 별도 커밋으로 남긴다. 이 브랜치는 로컬 커밋 상태이며 원격 푸시는 수행하지 않았다.

## 재검증

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --disable-sandbox
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project DescentAuthorized.xcodeproj -scheme DescentAuthorized \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/c5-ending-209/build CODE_SIGNING_ALLOWED=NO build
```
