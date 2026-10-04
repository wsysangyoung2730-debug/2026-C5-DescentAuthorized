# 개인정보·권한·데이터 흐름 감사

- 확인일: 2026-10-02
- 앱 소스 기준: `57d03f0` 및 이를 변경 없이 포함하는 `docs/#208-app-store-readiness`
- 범위: 앱 Swift 소스, Swift Package, Xcode 프로젝트, 개인정보 매니페스트, entitlement의 정적 분석 및 Apple 공식 문서 대조
- 이 문서는 분석 결과다. 앱 설정이나 코드를 수정하지 않았으며, App Store Connect 개인정보 응답·서명·업적 설정·실기기 통신을 검증한 결과가 아니다.

## 판정

출시 전에 해결해야 할 확정 미비점은 **필수 사유 API 선언 누락**과 **앱 내 개인정보·지원 안내 경로 부재**다. Game Center의 실제 서비스 설정과 개인정보 라벨은 별도 외부 확인 항목으로 남긴다. 현재 코드에서 자체 서버, 광고, 분석 SDK 또는 추적 경로는 발견되지 않았다.

| 우선순위 | 구분 | 확인 결과 | 조치 |
| --- | --- | --- | --- |
| 제출 전 필수 | 확정 | Release에서 `systemUptime`을 사용하지만 개인정보 매니페스트에 해당 API 범주가 없다. | `NSPrivacyAccessedAPICategorySystemBootTime` / `35F9.1`을 실제 용도에 맞게 추가하고 배포 아카이브에서 재확인한다. |
| 제출 전 필수 | 확정 | 앱 내 개인정보 처리방침 링크와 지원·문의 경로가 없다. | 운영자가 확정한 공개 개인정보·지원 URL을 앱에서 쉽게 접근하도록 연결하고 App Store Connect에도 입력한다. |
| 제출 전 확인 | 미검증 | App Store Connect 개인정보 라벨, 개인정보 URL, Game Center 업적 등록·서비스 동작 | 배포 후보와 실제 계정 설정을 대조한다. 코드만으로 제출 상태를 판정하지 않는다. |
| 제품 정책 확인 | 미검증 | 같은 기기에서 Game Center 계정을 바꿀 때 로컬 업적을 새 계정에 보고하는 동작 | 단일 로컬 세이브와 계정별 업적 정책을 확정하고 계정 전환을 실제 기기에서 시험한다. |

## 1. 필수 사유 API 선언 누락

`DescentAuthorized/Resources/PrivacyInfo.xcprivacy:5`의 선언 배열에는 `UserDefaults`의 `CA92.1`만 들어 있다. 이 파일은 Xcode 프로젝트의 리소스 빌드 단계에 포함된다(`DescentAuthorized.xcodeproj/project.pbxproj:581`). 파일이 없어서 생긴 문제가 아니라 실제 사용 API와 선언 범위가 맞지 않는 문제다.

Release 경로에서 다음 호출을 확인했다.

| 소스 | 실제 사용 |
| --- | --- |
| `DescentAuthorized/Reality/ObservatoryAmbientMotion.swift:68`, `:74` | 장식 동작의 프레임 간 경과 시간 계산 |
| `DescentAuthorized/Reality/RealityProgressionPresentation.swift:453`, `:457` | 문 열림 애니메이션의 진행률 계산 |
| `DescentAuthorized/Reality/RealityCombatPresentation.swift:767`, `:771` | 전투 연출 시간 계산 |
| 같은 파일 `:1072`, `:1075`, `:1707`, `:1710` | 추가 전투 동작의 시간 계산 |

Apple의 [필수 사유 API 범주·사유 목록](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)은 `systemUptime`을 `NSPrivacyAccessedAPICategorySystemBootTime`으로 분류한다. 앱 내부 이벤트의 경과 시간과 타이머 계산에 해당하는 승인 사유는 `35F9.1`이다. 확인된 사용 방식은 이 사유에 맞는다. 시스템 부팅 시간 자체를 서버로 보내는 경로는 발견되지 않았다.

Apple은 [필수 사유 API 선언 안내](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)에서 해당 선언이 누락된 앱을 App Store Connect에서 접수하지 않는다고 설명한다. 따라서 단순 권장 사항으로 미루면 안 된다. 문법 검사만 통과한다고 이 누락이 해결되는 것도 아니다.

수정 시에는 기존 `CA92.1`을 유지하면서 필요한 범주만 추가한다. 사용하지 않는 API 사유를 일괄 추가하지 않는다. 저장 파일 접근과 파일 열거가 있다는 사실만으로 파일 타임스탬프·디스크 공간 범주를 추가할 근거는 확인하지 못했다. 현재 prefetch는 파일 열거와 바이트 읽기이며(`RealitySceneController.swift:2380`, `:2395`), 메모리 압력 확인은 `os_proc_available_memory()`다(`:146`).

## 2. 개인정보 처리방침과 지원 경로

앱의 설정 분류는 입력·소리·화면·튜토리얼·Game Center뿐이다(`DescentAuthorized/Features/Settings/SettingsView.swift:740`). 앱 Swift 소스에서 `Link`, `openURL`, `UIApplication.shared.open`, 개인정보·지원용 HTTP URL 및 문의 연락 경로를 찾지 못했다. 개인정보 매니페스트는 이용자가 읽는 개인정보 처리방침을 대신하지 않는다.

[App Review Guidelines 5.1.1(i)](https://developer.apple.com/app-store/review/guidelines/#data-collection-and-storage)는 개인정보 처리방침을 App Store Connect 메타데이터와 앱 내부에서 쉽게 접근할 수 있게 제공하도록 요구한다. [Apple의 심사 준비 안내](https://developer.apple.com/app-store/review/)도 연락 가능한 지원 링크와 개인정보 링크를 요구한다.

다음 조치가 필요하다.

- 실제 운영자, 문의 수단, 시행일, 데이터 이용·보존·삭제 방식을 확정한다.
- 누구나 접근 가능한 개인정보 처리방침과 지원 페이지를 공개한다. 확인하지 않은 URL이나 연락처를 넣지 않는다.
- 설정 또는 홈의 쉽게 찾을 수 있는 위치에서 두 페이지에 접근하게 한다.
- App Store Connect에 같은 정책 URL과 지원 URL을 입력하고 링크가 실제로 열리는지 확인한다.
- 정책에 로컬 게임 저장, Game Center, 새 게임과 앱 삭제의 차이를 설명한다.

App Store Connect에 이미 외부 URL이 등록되어 있는지는 이번 감사에서 확인하지 않았다. 등록되어 있더라도 현재 앱 내부 경로의 부재는 별도로 해결해야 한다.

## 3. 실제 데이터 흐름

| 데이터 | 앱에서 하는 일 | 저장·전송 위치 | 근거 |
| --- | --- | --- | --- |
| 층·체크포인트·HP·주문·보상·튜토리얼·숙련도 | 진행 복원과 플레이에 사용 | 앱 컨테이너의 Application Support 아래 `DescentAuthorized/progress.json` | `App/GameSessionStore.swift:261`, `Core/Domain/DomainModels.swift:503` |
| 입력·음향·화면 설정 | 다음 실행에서도 선택 유지 | 앱 전용 UserDefaults | `Core/Persistence/GameSettingsStore.swift:29` |
| Game Center 표시 이름 | 연결 상태 화면에 표시 | 인증 상태의 메모리. 별도 저장 코드는 발견되지 않음 | `App/GameCenterManager.swift:123` |
| Game Center `gamePlayerID` | 계정별 업적 보고 여부 구분 | 앱 전용 UserDefaults 업적 원장 | `App/GameCenterManager.swift:137`, `:176`; `Core/Game/GameAchievements.swift:24` |
| 업적 ID·달성률 | Game Center 업적 동기화 | Apple Game Center에 보고 | `App/GameCenterManager.swift:140`, `:148` |
| 손가락·Pencil 입력 획 | 문양 판정 | 실행 중 입력 상태. 저장 모델에 원본 입력 획 필드는 없음 | `Core/Domain/DomainModels.swift:503`, `Core/Game/DemoGameSession.swift:268` |
| 자원 로딩 시간·연출 로딩 오류 | 오류 및 성능 진단 | 시스템 로그. 앱 코드의 별도 서버 전송은 발견되지 않음 | `Reality/RealitySceneController.swift:237`, `:258`; `Reality/RealityCombatPresentation.swift:577`, `:654` |

게임 진행 JSON은 atomic 쓰기를 사용한다(`Core/Persistence/GameSaveStore.swift:44`). 저장 실패 시 수정된 게임 상태를 확정하지 않으며(`Core/Game/GameSessionCoordinator.swift:27`), 저장 파일 복원이 실패하면 원본을 보존하는 임시 진행으로 전환하고 이용자에게 알린다(`App/GameSessionStore.swift:43`). 이는 정적 코드 확인 결과이며 저장 공간 부족·실기기 복원 동작까지 검증했다는 뜻은 아니다.

### 보존과 삭제를 설명할 때 주의할 점

- **새 게임:** 진행 파일을 삭제한다(`Core/Game/GameSessionCoordinator.swift:41`). 설정과 Game Center 업적 원장을 모두 지우는 기능은 아니다.
- **설정 초기화:** `GameSettingsStore.reset()`은 설정 키만 제거한다(`Core/Persistence/GameSettingsStore.swift:58`). 모든 개인정보나 업적의 삭제를 의미하지 않는다.
- **앱 삭제:** 앱 로컬 저장과 Apple 계정에 보고된 업적은 구분해야 한다. 현재 앱에는 Game Center 서버 업적을 초기화하는 호출이 없다.
- **보존 기간:** 로컬 설정과 업적 원장에 자동 만료 코드는 없다. “일정 기간 후 자동 삭제”라고 안내하면 현재 구현과 맞지 않는다.
- **기기 백업·복원:** 앱 코드 자체의 클라우드 동기화는 발견되지 않았다. 운영체제 백업에 의한 복원 여부와 정책 문구는 실기기 설정을 포함해 확인해야 한다.

## 4. 개인정보 라벨과 Game Center 외부 확인

자체 서버로 보내는 경로가 없다고 **“앱에서 외부로 전송하는 데이터가 전혀 없다”**고 쓰면 안 된다. Game Center 업적 보고가 실행된다. 반대로 로컬 저장이 존재한다는 이유만으로 이를 곧바로 개발자의 외부 데이터 수집으로 분류해서도 안 된다. Apple의 [App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/)에 나온 수집 정의와 실제 운영 경로를 기준으로 App Store Connect 응답을 결정해야 한다.

현재 `NSPrivacyCollectedDataTypes`가 없는 것만으로 규정 위반이라고 단정하지 않는다. 개인정보 매니페스트, App Store Connect 개인정보 응답, 이용자용 정책 문서는 목적이 서로 다르다. 실제 수집 여부를 확인한 뒤 서로 일관되게 작성해야 한다. [App Store Connect 개인정보 관리 안내](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/)도 최종 앱의 실제 데이터 처리 방식에 맞는 응답을 요구한다.

Game Center 구현에서 확인한 사실과 남은 확인 사항은 다음과 같다.

| 항목 | 확인 수준 | 결과·후속 확인 |
| --- | --- | --- |
| Game Center capability | 코드 확인 | entitlement가 켜져 있다(`Resources/DescentAuthorized.entitlements:5`). 배포 프로비저닝에 실제 반영됐는지는 별도 확인한다. |
| 자동 인증 | 코드 확인 | 앱 시작 시 인증을 설치한다(`App/DescentAuthorizedApp.swift:97`). 인증 취소·서비스 불가 시 게임 진행이 막히지 않는지 실제 기기에서 확인한다. |
| 인증 실패 처리 | 코드 확인 | 실패 상태로 바꾸고 설정에서 재연결한다(`App/GameCenterManager.swift:114`, `Features/Settings/SettingsView.swift:428`). |
| 미인증 업적 보존 | 코드 확인 | 로컬 원장에 보관하고 인증 후 다시 보고한다(`App/GameCenterManager.swift:89`, `:131`). 오프라인 복구·중복 보고 방지를 실제 계정으로 확인한다. |
| 식별자 범위 | 코드 확인 | 앱 범위의 `gamePlayerID`를 사용하고 `teamPlayerID`나 기존 `playerID`는 사용하지 않는다. [Apple의 범위 제한 식별자 안내](https://developer.apple.com/documentation/gamekit/protecting-the-player-s-privacy-using-scoped-identifiers)를 참고한다. |
| 식별자 지속성 | 추가 검토 | 현재 인증 여부는 확인하지만 `scopedIDsArePersistent()` 확인은 없다. 일시 식별자 조건에서 로컬 원장이 어떻게 남는지 검토한다. 즉시 심사 차단 문제로 단정하지 않는다. |
| 계정 전환 | 정책·기기 확인 | `desiredPercentages`는 기기 공통이고 보고 기록만 계정별이다(`Core/Game/GameAchievements.swift:24`). 새 계정에 기존 로컬 업적을 보고하는 동작이 의도인지 확정한다. |
| 업적 서비스 등록 | 외부 미검증 | 코드에 업적 ID 8개가 있다(`Core/Game/GameAchievements.swift:3`). App Store Connect 등록·문구·아이콘·심사 포함 여부를 확인해야 한다. |

## 5. 권한·SDK·보안 점검

정적 검색에서 아래 사항을 확인했다. “발견되지 않음”은 현재 저장소 범위의 결과이며 배포 아카이브 전체 및 실제 네트워크 관측을 대체하지 않는다.

- `Package.swift`에 외부 패키지 의존성이 없고, Xcode의 명시적 프레임워크 항목은 Apple의 GameKit·AVFAudio다(`DescentAuthorized.xcodeproj/project.pbxproj:223`). CocoaPods·Carthage·외부 SDK 묶음은 찾지 못했다.
- URLSession·HTTP 요청·WebView·자체 서버·광고·분석 SDK·IDFA·ATT·연락처·위치·사진 접근 코드는 찾지 못했다.
- 앱 Swift·JSON·plist·entitlement·shader 검색에서 API 키, 비밀번호, 개인 키 등 앱 내 자격 증명을 발견하지 못했다. 자원 전체의 보안 보증은 아니다.
- 3D 화면은 `ARView(... cameraMode: .nonAR, automaticallyConfigureSession: false)`다(`Reality/RealityStageView.swift:321`). 현재 동작에 카메라 권한 설명을 추가할 근거는 없다.
- 오디오는 번들 리소스의 `.ambient` 재생이다(`App/GameFeedbackManager.swift:623`, `:645`). 녹음 경로가 없어 마이크 권한 설명을 추가할 근거는 없다.
- 자체 계정 생성, 앱 내 결제, 이용자 게시물, 친구 목록 접근 기능은 발견되지 않았다. 현재 기능만으로 자체 계정 삭제 화면, ATT 창 또는 UGC 신고 기능을 새로 요구할 근거는 없다.
- 개인정보 처리방침 미비와 별개로, 게임 진행 JSON이 앱 컨테이너에 저장된다는 사실만으로 보안 결함이나 암호화 의무 위반이라고 단정하지 않는다.

## 제출 전 확인 목록

- [ ] SystemBootTime `35F9.1` 추가 후 실제 Release 아카이브의 매니페스트를 확인한다.
- [ ] 운영자와 연락 수단이 확정된 개인정보·지원 페이지를 공개하고 앱 안에서 연결한다.
- [ ] App Store Connect 개인정보 URL·지원 URL·개인정보 응답을 실제 배포 후보와 대조한다.
- [ ] Game Center 미로그인·취소·오프라인·복구·계정 전환과 업적 보고를 실기기에서 검증한다.
- [ ] 새 게임·앱 삭제·기기 복원·Game Center 업적 보존을 구분해 안내한다.
- [ ] 음향 추가 후 번들 재생만 유지되는지 확인한다. 다운로드·SDK·분석·권한·네트워크가 추가되면 해당 항목을 재감사한다.
