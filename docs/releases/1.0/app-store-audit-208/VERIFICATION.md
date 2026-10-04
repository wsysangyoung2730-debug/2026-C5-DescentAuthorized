# 실제 검증 기록

앱 코드 기준 `57d03f0`, 점검일 2026-10-02. #208에서는 앱 코드·리소스·프로젝트 설정을 변경하지 않았다. 아래 결과는 이 점검에서 새로 수행한 것이며 과거 DEBUG 프리뷰 결과를 Release 실행 결과로 대신하지 않는다.

## 빌드와 자동 검증

| 검사 | 결과 | 범위와 제한 |
| --- | --- | --- |
| Swift 코어 테스트 | 235개, 실패 0 | 전투·진행·저장 등 기존 코어 테스트. UI 또는 실제 GPU 성능 검사가 아님 |
| 기기용 Release 아카이브 | 성공 | Xcode 26.5 (17F42), iphoneos26.5, arm64. `CODE_SIGNING_ALLOWED=NO`: 배포 서명·프로비저닝·Apple 업로드 검증은 제외 |
| 시뮬레이터 Release 빌드 | 성공 | 실행 인자 없이 일반 홈으로 시작 |
| Reality 리소스 비교 | 2,972개 모두 해시 일치 | 누락/내용 차이/추가 파일 0개. 모든 모델의 실제 장면 렌더링을 뜻하지 않음 |
| 번들 개인정보 명세 | 포함됨, 내용 불충분 | UserDefaults CA92.1만 포함. 바이너리에도 `systemUptime` 선택자가 있어 SystemBootTime 사유 누락을 재확인 |
| 프리뷰 진입 검사 | 선택한 진단 인자 5개가 바이너리에 없음 | 앱 시작 소스의 DEBUG 조건과 교차 확인. 바이너리 전체 제어 흐름의 완전 분석은 아님 |
| 아이콘 | 1024×1024 RGB, alpha 없음 | 원본 PNG와 아카이브 아이콘 참조 확인 |
| SDK 최소 제출 요구 | 현재 충족 | 현재 공식 최소 Xcode 26 / iOS·iPadOS 26 SDK. 출시 시점에 다시 확인 |

[Apple SDK 요구](https://developer.apple.com/news/upcoming-requirements/) 기준으로 26.5 도구는 현재 최소 제출 조건에 맞는다. [제출 안내](https://developer.apple.com/app-store/submitting/)의 **2027년 4월 이후 SDK 27 요구**와 현재 최소 조건을 혼동하지 않는다. 최신 iPadOS 27 실행 검증은 이번 환경에서 하지 않았다.

### 아카이브 크기

- `.app` 파일 논리 크기 합: **1,598,904,526바이트** = 약 **1.60GB / 1.49GiB**.
- 실행 파일 전체: **4,549,016바이트**. 이는 __TEXT 구역만이 아닌 실행 파일 전체 크기다.
- 큰 구성: Reality 1,313,412,456바이트, Assets.car 271,857,080바이트, Audio 8,950,782바이트.
- [Apple 한도](https://developer.apple.com/help/app-store-connect/reference/app-uploads/maximum-build-file-sizes/)의 압축 해제 앱 4GB와 실행 코드 한도에 비추어 현재 산출물에서 크기 초과는 발견하지 않았다.
- IPA 압축 크기·App Store 기기별 thinning 크기·사용자 다운로드 크기를 측정한 것은 아니다. 다운로드 부담과 실기기 메모리 사용량은 별개다.

번들에는 README 등 개발 문서도 일부 포함된다. [인벤토리](evidence/device-release-inventory.json)의 `bundledDocumentation`에서 확인할 수 있다. 용량 최적화·배포 정리 후보이며, 이 자체를 즉시 심사 차단으로 판단하지 않는다.

### 빌드 경고

현재 빌드에는 RealityKit의 deprecated 로딩/텍스처 API와 사용되지 않는 변수 경고가 있다. 사용 중인 것은 공개 API이며 deprecated라는 이유만으로 사설 API 위반이나 즉시 제출 차단으로 판정하지 않는다. 향후 SDK 업데이트 전 교체 검증을 권장한다. AppIntents 미사용으로 인한 메타데이터 추출 생략도 오류가 아니다. 경고 목록은 [검증 요약](evidence/verification-summary.json)에 남겼다.

## 실제 Release 화면 검증

별도 신규 시뮬레이터 `C5 App Store Audit 208`을 생성했다. 모델은 iPad mini (A17 Pro), 런타임 iOS 26.5이며 기존 사용자 시뮬레이터의 플레이 저장을 수정하지 않았다. Apple 계정 로그인이나 App Store 제출은 하지 않았다.

| 순서 | 조작·관측 | 판정 |
| --- | --- | --- |
| 1 | 새 설치 → 인자 없이 Release 실행 | 홈과 설정·시작 버튼 표시 |
| 2 | 기기 세로 상태의 첫 실행 | 홈이 세로 화면 중앙의 작은 가로 영역으로 표시됨. 아래 관측 사항 참조 |
| 3 | Simulator의 기기 회전으로 가로 전환 | 가로 홈이 화면에 맞게 커짐 |
| 4 | 설정 → 입력 및 조작 | 5개 설정 분류 표시. 개인정보·지원 분류가 없음 |
| 5 | 설정 → Game Center | 미인증으로 ‘사용할 수 없음’과 재연결 버튼 표시. 인증 성공/실제 업적 서버 설정은 미검증 |
| 6 | 설정 닫기 → 하강 절차 시작 → 인트로 | 계정 인증 불가 상태여도 첫 방 로딩 후 ‘몸 일으키기’/인트로 건너뛰기 가능 |
| 7 | 인트로 건너뛰기 | 제10층의 ‘주변 둘러보기’ 튜토리얼 표시 |
| 8 | Simulator 홈 버튼 → 앱 종료 → 다시 실행 | ‘하강 절차 계속’과 ‘처음부터’ 표시. 첫 저장 존재를 복원 |
| 9 | 하강 절차 계속 | 제10층 ‘주변 둘러보기’ 튜토리얼로 복원됨 |

이 검증에서 **네트워크를 끄지 않았다**. Game Center 미인증 상태의 시작을 관측했을 뿐 전체 오프라인 플레이나 로그인 취소 흐름을 모두 검증했다는 뜻은 아니다. 모든 층 실제 플레이, Pencil, VoiceOver, 소리 청취, 장시간 메모리·발열, Game Center 실계정 보고는 남은 검증이다.

### 새로 관측한 화면 이슈: 세로 첫 실행

[실제 화면](evidence/release-mini-cold-launch-portrait.png)에서 홈이 세로 화면에 가로 비율로 작게 표시되며 큰 검정 여백이 생긴다. 가로 회전 후에는 정상 크기로 표시됐다. 코드의 `LandscapeOrientationController.requestLandscape()` (`DescentAuthorized/App/DescentAuthorizedApp.swift:13–34`)와 가로 전용 Info.plist만으로 첫 실행의 기대 방향을 보장했다고 판단할 수 없다.

이 관측만으로 iPadOS의 호환 표시와 앱의 방향 요청 문제 중 원인을 확정하지 않는다. **출시 전 재현·보완 권장(P2)**: 실물 iPad에서 세로/가로 첫 설치, 콜드 런치, 잠금 후 복귀, iPadOS 26·27의 창 모드를 검사하고 가로 전용 정책에 맞는 표시 또는 명확한 회전 안내를 제공한다.

[Apple TN3192](https://developer.apple.com/documentation/technotes/tn3192-migrating-your-app-from-the-deprecated-uirequiresfullscreen-key)는 `UIRequiresFullScreen` 호환 모드가 iPadOS 26부터 deprecated임을 안내한다. 가로 전용 자체를 심사 위반으로 단정하지 않으며 창 크기 변화에서 사용 불가능한 UI가 생기는지 확인해야 한다.

## 증거 파일

- [Release 번들 인벤토리](evidence/device-release-inventory.json): Info.plist, 용량, 링크 라이브러리, manifest, 아이콘, 진단 인자 확인.
- [Reality 원본/번들 비교](evidence/reality-bundle-comparison.json): 2,972개 파일 비교.
- [빌드·테스트 요약](evidence/verification-summary.json): 현재 빌드 결과와 실제 경고.
- [세로 첫 실행](evidence/release-mini-cold-launch-portrait.png)
- [설정](evidence/release-mini-settings.png)
- [Game Center 미인증](evidence/release-mini-game-center-unavailable.png)
- [미인증 상태의 10층 진입](evidence/release-mini-tutorial-no-account.png)
- [재실행의 이어하기 메뉴](evidence/release-mini-resume-menu.png)
- [이어하기 후 10층 복원](evidence/release-mini-resumed-tutorial.png)

화면은 검사 중 실제 캡처다. 최종 App Store 스크린샷으로 선정하거나 제출한 자료가 아니다.

## 재검사 방법

Xcode가 여러 개면 동일한 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`를 지정한다. 생성 산출물은 저장소 밖에 둔다.

```sh
swift test
xcodebuild -project DescentAuthorized.xcodeproj -scheme DescentAuthorized \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/c5-store-audit/device-build \
  -archivePath /tmp/c5-store-audit/DescentAuthorized.xcarchive \
  CODE_SIGNING_ALLOWED=NO archive
python3 docs/releases/1.0/app-store-audit-208/inspect_release.py \
  /tmp/c5-store-audit/DescentAuthorized.xcarchive/Products/Applications/DescentAuthorized.app \
  --source-revision 57d03f0 --output /tmp/c5-store-audit/reinspection.json
python3 docs/reality-assets/verify_bundled_reality.py \
  /tmp/c5-store-audit/DescentAuthorized.xcarchive/Products/Applications/DescentAuthorized.app
```

다른 소스로 빌드하면 `--source-revision`도 실제 해당 커밋으로 바꾼다. 인벤토리 도구의 종료 코드 0은 검사 완료를 뜻하며 출시 가능 판정이 아니다. 현재 상태에서는 manifest와 언어 관련 REVIEW 경고가 나오는 것이 맞다.
