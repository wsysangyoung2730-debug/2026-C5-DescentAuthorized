# 최신 버전 출시 보완 · #212–#215

최종 정리일: **2026-10-18**. 원격 최신 `main @ 35fe1a1`에서 시작했으며, 10월 18일 원격 main/develop에도 추가 변경이 없음을 확인했다. 이전 #208 점검 이후 추가된 엔딩과 보스방 카메라를 포함한 코드가 기준이다.

**코드 보완과 로컬 검증 결과이며, App Store 제출 준비 완료를 뜻하지 않는다.** 지원 URL은 사용자 요청대로 마지막 제작 항목으로 유보했다. 공개 개인정보처리방침 URL, 실물 iPad 및 App Store Connect 확인은 별도 남은 작업이다.

## 수정 범위와 브랜치

하나의 이슈에 하나의 브랜치를 사용한다. 다음 브랜치는 앞 브랜치를 포함하는 누적 구조이며, 최종 후보는 `fix/#215-full-release-achievements`다. main/develop 병합과 원격 푸시는 이번 마무리에서 하지 않았다.

| 이슈 | 브랜치 | 주요 변경 커밋 |
| --- | --- | --- |
| [#212](https://github.com/wsysangyoung2730-debug/2026-C5-DescentAuthorized/issues/212) | `fix/#212-release-privacy-metadata` | `e02ba7a`, `233203b` |
| [#213](https://github.com/wsysangyoung2730-debug/2026-C5-DescentAuthorized/issues/213) | `fix/#213-save-recovery-safety` | `234a7cd`, `96c779a` |
| [#214](https://github.com/wsysangyoung2730-debug/2026-C5-DescentAuthorized/issues/214) | `fix/#214-ipad-window-accessibility` | `4ad3c83`, `0d6f88e`, `932706b`, `b253838` |
| [#215](https://github.com/wsysangyoung2730-debug/2026-C5-DescentAuthorized/issues/215) | `fix/#215-full-release-achievements` | `2da4c59`, `b7cb73b`; #214 보완 병합 `d7f474f` |

### #212 개인정보·언어

- 경과 시간과 연출 타이밍 측정에 사용하는 `systemUptime`의 사유 `SystemBootTime / 35F9.1`을 추가했다. 기존 `UserDefaults / CA92.1`을 유지한다.
- 실제 한국어 UI와 일치하도록 번들 기본 언어를 `ko`로 선언했다.
- 설정에 기기 저장, 선택적 Game Center 전송, 보관·삭제·백업 및 문의 경로를 추가했다. 사용자 제공 이메일은 `sangyoung2730@naver.com`, 제작자는 `SangYoung Woo`다.
- 공개 개인정보처리방침 URL은 게시하지 않았다. 앱 내부 설명만으로 App Store Connect의 공개 URL 요구가 완료된 것은 아니다.

### #213 저장 안전성

- 진행 기록 또는 보존 중인 복구 대상 저장이 있으면 새 게임 전에 삭제 확인을 받는다. 내부 시작 함수도 명시적 교체 요청 없이는 기존 저장을 지우지 않는다.
- 지원하지 않는 저장 버전과 잘못된 하층 단계·카운터를 마이그레이션 전에 거부한다. 잘못된 2층 보상 단계에서 없는 체크포인트를 강제 해제해 종료되던 경로를 차단했다.
- 복원 실패 시 원본 파일을 보존하고 임시 세션임을 안내한다.

### #214 iPad 창·접근성

- iPadOS 26 이상은 네 방향과 크기 변경을 허용한다. 이전 OS는 가로 전체 화면 동작을 유지한다.
- 플레이 영역이 세로이거나 900×600pt보다 작으면 같은 게임 뷰를 유지한 채 안내를 표시한다. 전투 입력, 보스 카메라, 대사, 오프닝, 하강 인계를 일시 정지하고 복귀 시 재개한다. 진행 중인 입력 획은 취소한다.
- 홈 버튼과 설정 분류·조작 행을 좁은 화면에 맞춰 배치했다.
- 시스템 ‘동작 줄이기’와 앱 설정을 함께 반영하고 입력판을 접근성 요소로 노출했다. 전체 게임의 VoiceOver 지원을 인증한 것은 아니다.
- 아카이브에서 자동 생성 설정의 누락을 발견해 `AppInfo.plist`를 병합하도록 수정했다. `UIRequiresFullScreenIgnoredStartingWithVersion = 26.0`을 명시하고, 단일 저장·세션이 복수 창에서 동시에 진행되지 않도록 다중 scene 생성을 비활성화했다.

### #215 출시 업적

- 최종 완료는 7층 진입 대신 1층 마지막 승인 완료 시 지급한다.
- 하강 달성률은 10→1층의 아홉 번 이동을 반영한다.
- 한 회차로 수집할 수 없는 주문 28종은 여러 진행의 고유 주문 ID를 누적한다. 새 게임·재실행에서도 보존하고 같은 주문은 중복 계산하지 않는다.
- 예전 원장의 잘못 대기 중인 데모 100%를 새 규칙으로 재계산한다. 이미 서버에 지급된 업적은 취소할 수 없으므로 보존하며, 실제 서버 검증은 별도다.
- 자세한 등록 조건은 [Game Center 문서](../../../GAME_CENTER_SETUP.md)에 있다.

## 검증 결과와 범위

환경: Xcode 27.0 (`27A266a`), iOS SDK 27.0, 최저 배포 iPadOS 18.0. 코어는 Xcode 도구 체인의 Swift Package 테스트로 검사했다.

| 검사 | 결과·증거 |
| --- | --- |
| 코어 회귀 테스트 | **265개, 실패 0개**. 저장 검증·마이그레이션·전 층 진행·엔딩·업적 테스트 포함. [로그](evidence/core-tests.log) |
| 시뮬레이터 Release | 최종 설정 포함 빌드 확인. [빌드 요약](evidence/build-summary.txt) |
| 기기용 Release 아카이브 | 최종 설정 포함 생성 확인, **서명 제외**. [검사 JSON](device-release-inspection.json) |
| 비압축 앱 크기 | **1,599,421,418바이트** (약 1.60 GB), 파일 3,000개. 서명 전 크기이며 다운로드 크기는 미측정 |
| 번들 리소스 | Reality **2,972개** 모두 원본 해시 일치, 누락·추가·변경 0. [보고서](reality-bundle-check.json) |
| 메타데이터 | 한국어, 개인정보 API 사유 2종, RGB 1024px 앱 아이콘, 선택한 DEBUG 미리보기 인수 5종 미포함 검사. 포괄적 비공개 API 검사는 아님 |
| 실제 첫 실행 | 전용 iPad mini / iPadOS 27 시뮬레이터에서 Release 앱 실행 및 세로 홈 확인. [화면](evidence/portrait-launch.png) |
| 손상된 저장 복구 | 전용 컨테이너에 `saveVersion:999` 테스트 파일을 넣고 재실행. 충돌 없이 원본 보존 안내 표시. [화면](evidence/invalid-save-recovery.png) |
| 원본 보존 | 재실행 전후 테스트 파일 SHA-256 동일: `3f4467f24f629d7a0b4c78925972076f94f487e0de75cf8fd8927b296966f1e3` |

화면 제어 도구가 Device Hub 연결에서 시간 초과하여 **새 게임 확인창의 확인·취소, 설정 내부 조작, 전투 중 회전·크기 변경을 실제로 눌러 확인하지 못했다.** 해당 동작은 코드 검토·빌드와 직접 조작 검증을 구분한다. 세로 홈 캡처는 `b7cb73b`, 복구 안내 캡처는 최종 누적 코드 `d7f474f`의 시뮬레이터 Release 앱에서 얻었다. 기기·시뮬레이터 번들 모두 [메타데이터 검사](validate_bundle.py) 8개 항목을 통과했다. 최종 빌드의 실행 확인은 빌드 요약에도 기록했다. 기존 사용자 플레이 데이터는 변경하지 않았다.

## 남겨둔 출시 전 작업

- 누구나 접근 가능한 개인정보처리방침 URL 게시, 앱 연결 및 App Store Connect 개인정보 응답 확인. **지원 URL은 요청대로 추후 제작.**
- 실제 iPad에서 전 층 플레이, 저장·복구, 회전·창 모드, 최소 사양의 발열·메모리·로딩, Pencil 및 접근성 검증.
- Game Center 8개 업적의 서버 등록·표시명·설명·아이콘·보고·계정 전환 검증. 개발 중 이미 지급된 업적은 별도 테스트 계정으로 검증.
- 배포 서명, 최종 버전·빌드 번호 확정(현재 0.1.0 / 1), TestFlight 설치 및 App Store Connect 검증.
- 모든 모델·이미지·음향의 상업 배포 권리·크레딧, 추가될 음향의 재생·인터럽션, 연령 설문·출시 국가·수출 규정·스토어 자료 확인.

## 공식 기준

- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/): 완성도와 개인정보처리방침 접근성 등.
- [필수 사유 API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api).
- [최소 SDK 요구](https://developer.apple.com/news/upcoming-requirements/?id=04282026a): Xcode 26 및 SDK 26 이상.
- [TN3192 iPad 전체 화면 호환성 변경](https://developer.apple.com/documentation/technotes/tn3192-migrating-your-app-from-the-deprecated-uirequiresfullscreen-key).
- [빌드 크기 제한](https://developer.apple.com/help/app-store-connect/reference/app-uploads/maximum-build-file-sizes/). 검사된 크기는 서명 전 비압축 앱이며, IPA 다운로드·앱 슬라이싱 크기가 아니다.

## 재개 시점 메모 · 2026-10-18

사용자 요청으로 여기까지 정리 후 작업 대기. 앱 소스 최종 누적 기준은 `d7f474f`이며 이후 커밋은 검증 문서와 증거 정리다. #212~#215 이슈는 같은 양식으로 수정·검증·미확인 사항을 반영했으며, 외부 확인과 직접 UI 조작이 남아 있으므로 열어 두었다. 원격 푸시 및 main/develop 병합은 하지 않았다.

다음 재개 시 우선 확인할 것은 새 게임 확인/취소, 설정 내 개인정보 안내, 실제 전투 중 회전·작은 창·복귀, Game Center 실제 보고다. 기존 자동 테스트 265개와 Release 아카이브·번들 검사 결과는 이 폴더에 보존했다. 새 변경이 없다면 자동 테스트 전체를 반복하기보다 미확인 직접 조작 항목부터 확인한다.
