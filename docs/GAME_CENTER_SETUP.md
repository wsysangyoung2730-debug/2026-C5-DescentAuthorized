# Game Center 출시 업적 설정

> 문서 상태: 운영 및 배포 참고 문서
> 기준 구현: #215 전 층 업적·누적 주문 보관소
> 마지막 갱신: 2026-10-13

## 목적

현재 구현은 10층부터 1층까지의 게임 진행과 기기에 누적된 주문 습득 기록으로 업적 진행률을 계산한다. Game Center 로그인이 완료되면 여러 업적을 한 번에 보고한다. 로그인 실패나 네트워크 오류가 발생하면 보고할 내용을 로컬 원장에 남기므로 전투와 저장은 계속 진행된다. 인증과 지속 식별자가 확인된 경우에만 계정별 보고를 수행한다.

기존 서버 ID 8개를 그대로 유지한다. `demoCompleted`는 호환성을 위한 내부 이름이며 출시 화면에는 아래의 최종 완료 문구를 사용한다. App Store Connect의 현재 등록 상태는 코드 검사로 확인할 수 없으므로 이름·설명·아이콘·점수·제출 상태를 별도로 대조해야 한다.

## 업적 목록

| 코드 ID | 표시명 제안 | 조건 | 진행 방식 | 점수 제안 |
| --- | --- | --- | --- | ---: |
| `com.wsysangyoung.DescentAuthorized.achievement.firstGlyph` | 첫 승인 | 첫 주문 훈련 완료 | 100% | 5 |
| `com.wsysangyoung.DescentAuthorized.achievement.perfectCast` | 오차 없음 | 완벽 등급 시전 달성 | 100% | 10 |
| `com.wsysangyoung.DescentAuthorized.achievement.recordsCleared` | 기록 말소 | 9층 기록 관리자 처치 | 100% | 10 |
| `com.wsysangyoung.DescentAuthorized.achievement.spellArchive` | 개인 주문 보관소 | 새 게임·체크포인트 재진입을 포함해 서로 다른 주문 28종 누적 습득 | `누적 고유 주문 수 × 100 / 28`의 정수 몫 | 15 |
| `com.wsysangyoung.DescentAuthorized.achievement.absoluteBarrierDispelled` | 절대 승인 거부 | 봉인 해제로 절대 방어막 해제 | 100% | 15 |
| `com.wsysangyoung.DescentAuthorized.achievement.observationCleared` | 관측 종료 | 8층 관측 관리자 처치 | 100% | 15 |
| `com.wsysangyoung.DescentAuthorized.achievement.descentProcedure` | 하강 봉인 절차 | 10층에서 1층까지 아홉 번 하강 | 9층 11%, 8층 22%, 7층 33%, 6층 44%, 5층 55%, 4층 66%, 3층 77%, 2층 88%, 1층 100% | 10 |
| `com.wsysangyoung.DescentAuthorized.achievement.demoCompleted` | 최종 승인 | 1층 최종 기록과 승인 절차를 마쳐 엔딩 도달 | `expansion.isComplete`일 때 100% | 20 |

제안 점수 합계는 100점이다.

주문은 한 번의 진행에서 선택 가능한 수가 제한되므로 여러 진행의 고유 ID를 합산한다. 동일 주문을 다시 익혀도 중복 계산하지 않는다. 새 게임은 진행 세이브를 초기화하지만 업적 원장은 유지하므로 누적 주문과 달성한 업적은 유지된다. 앱 삭제 또는 기기 데이터 삭제 후에는 이 로컬 원장을 보장할 수 없으며 자체 클라우드 복원 기능은 없다.

## 이전 개발 버전의 원장 이관

- UserDefaults 저장 키 `game-center.achievement-ledger.v2`는 유지하고, 원장 내부 `rulesVersion`을 2로 기록한다. 버전 및 누적 주문 필드가 없는 기존 JSON도 읽는다.
- 이전 버전에서 대기 중이던 `spellArchive`, `descentProcedure`, `demoCompleted` 수치는 삭제하고 현재 세이브와 새 규칙에서 다시 계산한다. 오프라인 원장에 남은 7층 진입 100%가 새 계정에 최종 완료로 전송되지 않게 한다.
- 다른 업적과 이미 성공한 계정별 보고 기록은 보존한다. 새 규칙으로 획득한 최종 완료·하강·주문 기록은 다음 실행에서 다시 삭제하지 않는다.
- 이전 원장에는 주문 ID가 없으므로 과거 다른 진행에서 익혔으나 현재 세이브에도 없는 주문을 추정해 복원하지 않는다. 현재 보유 주문에서 시작해 이후 습득을 누적한다.
- **개발 중 이미 서버에 잘못 지급된 100% 업적은 이번 로컬 수정으로 취소되거나 낮아지지 않는다.** 기존 계정의 정상 재검증에는 App Store Connect의 테스트 운영 절차와 별도 테스트 계정을 사용한다. 운영 데이터 전체 초기화는 이 변경에 포함하지 않는다.

원장의 최고 진행률과 누적 주문은 기기 공통이다. 보고 완료 기록만 Game Center 계정별로 보관하며, 다른 계정으로 연결하면 그 기기의 누적 기록을 해당 계정에도 보고한다. 사용자별 세이브 분리 기능으로 오해하지 않도록 이 정책을 유지한다.

## App Store Connect 작업

1. 앱의 Bundle ID가 Xcode의 `com.wsysangyoung.DescentAuthorized`와 같은지 확인한다.
2. 앱 버전에서 Game Center를 활성화한다.
3. 위 표의 ID로 업적 8개를 생성한다.
4. 한국어 표시명, 달성 전 설명, 달성 후 설명과 업적 이미지를 등록한다. 구형 “데모 주문 5종”, “7층 100%”, “데모 엔딩” 문구를 위 조건으로 정정한다.
5. TestFlight 또는 개발 서명된 실제 iPad에서 인증, 취소, 미연결 플레이, 오프라인 후 재보고, 중간 진행률, 완료 배너를 확인한다.
6. 7층 진입에서 최종 승인 업적이 지급되지 않고, 1층 마지막 승인 완료 후 지급되는지 확인한다. 서로 다른 보상을 선택한 새 진행·재진입에서 주문 누적이 증가하고 같은 주문으로는 늘지 않는지 확인한다.

App Store Connect에 업적이 아직 생성되지 않은 상태에서는 앱과 코어 테스트가 정상 작동하더라도 서버 보고는 실패할 수 있다. 실패한 보고는 앱의 로컬 원장에 유지된다.

## 코드 연결 지점

- `GameAchievementTracker`: 전체 층 진행·최종 승인·시전 결과를 업적 진행률로 변환한다.
- `GameAchievementLedger`: 원장 버전 이관, 누적 고유 주문, 전체 최고 진행률과 플레이어별 보고 성공치를 보관한다.
- `GameCenterManager`: 인증 화면, 로컬 원장, 묶음 보고와 재시도를 담당한다.
- `GameSessionStore`: 초기 저장 복원 및 명령 처리 후 최신 업적과 보유 주문 ID를 전달한다.

진행·완료·주문 업적은 복원한 세이브에서 다시 계산할 수 있다. 절대 방벽 해제는 실제 성공 전투 이벤트를 확인한 뒤 로컬 업적 원장에 기록한다. 업적 보고가 실패하면 기록된 진행률을 다음 연결 시 재시도한다.
