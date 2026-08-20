# Game Center 임시 업적 설정

## 목적

현재 구현은 게임 진행 상태에서 업적 진행률을 계산하고, Game Center 로그인이 완료되면 여러 업적을 한 번에 보고한다. 로그인 실패나 네트워크 오류가 발생하면 보고할 내용을 로컬 대기열에 남기므로 전투와 저장은 계속 진행된다.

이 문서의 업적 ID는 초기 개발용으로 확정한 값이다. App Store Connect에 등록한 뒤에는 ID를 수정할 수 없으므로 출시 계정에 생성하기 전에 최종 명칭과 점수를 다시 검토해야 한다.

## 임시 업적 목록

| 코드 ID | 표시명 제안 | 조건 | 진행 방식 | 점수 제안 |
| --- | --- | --- | --- | ---: |
| `com.wsysangyoung.DescentAuthorized.achievement.firstGlyph` | 첫 승인 | 첫 주문 훈련 완료 | 100% | 5 |
| `com.wsysangyoung.DescentAuthorized.achievement.perfectCast` | 오차 없음 | 완벽 등급 시전 달성 | 100% | 10 |
| `com.wsysangyoung.DescentAuthorized.achievement.recordsCleared` | 기록 말소 | 9층 기록 관리자 처치 | 100% | 10 |
| `com.wsysangyoung.DescentAuthorized.achievement.spellArchive` | 개인 주문 보관소 | 데모 주문 5종 습득 | 주문당 20% | 15 |
| `com.wsysangyoung.DescentAuthorized.achievement.absoluteBarrierDispelled` | 절대 승인 거부 | 봉인 해제로 절대 방어막 해제 | 100% | 15 |
| `com.wsysangyoung.DescentAuthorized.achievement.observationCleared` | 관측 종료 | 8층 관측 관리자 처치 | 100% | 15 |
| `com.wsysangyoung.DescentAuthorized.achievement.descentProcedure` | 하강 봉인 절차 | 9층 34%, 8층 67%, 7층 100% | 누적 | 10 |
| `com.wsysangyoung.DescentAuthorized.achievement.demoCompleted` | 다음 10층 | 데모 엔딩 도달 | 100% | 20 |

제안 점수 합계는 100점이다.

## App Store Connect 작업

1. 앱의 Bundle ID가 Xcode의 `com.wsysangyoung.DescentAuthorized`와 같은지 확인한다.
2. 앱 버전에서 Game Center를 활성화한다.
3. 위 표의 ID로 업적 8개를 생성한다.
4. 한국어 표시명, 달성 전 설명, 달성 후 설명과 업적 이미지를 등록한다.
5. TestFlight 또는 개발 서명된 실제 iPad에서 인증, 중간 진행률, 완료 배너를 확인한다.

App Store Connect에 업적이 아직 생성되지 않은 상태에서는 앱과 코어 테스트가 정상 작동하더라도 서버 보고는 실패할 수 있다. 실패한 보고는 앱의 로컬 대기열에 유지된다.

## 코드 연결 지점

- `GameAchievementTracker`: 저장 가능한 게임 진행을 업적 진행률로 변환한다.
- `GameAchievementQueue`: 동일 업적의 가장 높은 진행률만 보관한다.
- `GameCenterManager`: 인증 화면, 로컬 대기열, 묶음 보고와 재시도를 담당한다.
- `GameSessionStore`: 명령 처리 후 최신 진행 상태를 업적 추적기에 전달한다.

업적은 전투 이벤트의 일시적인 화면 상태가 아니라 `GameProgress`에 남은 기록을 기준으로 계산한다. 앱이 업적 보고 직전에 종료되더라도 다음 실행에서 같은 진행 상태를 다시 계산할 수 있다.
