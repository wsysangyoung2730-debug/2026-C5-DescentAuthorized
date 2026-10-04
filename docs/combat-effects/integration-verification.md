# 제공된 3D 전투 효과 적용 및 검증

2026-09-30 · `feat/#199-authored-combat-effects-3d` · 기준 `fix/#198-all-floor-natural-attack-motion` (`55cef5f`)

제공된 GLB 18종을 RealityKit에서 읽는 USDC와 1K 텍스처로 변환하고, 실제 전투 상태와 공격 시점에 연결했다. #198의 21종 캐릭터 공격 모션과 소켓을 유지하며 손·무기에서 준비, 발사, 충돌, 소멸이 이어진다. 원본 파일은 변경하지 않았다.

## 적용 위치

| 모델 | 연결한 동작·상태 |
|---|---|
| 01 record-lance | 9층 기록 창 공격 |
| 02 focus-lens | 8층 관측·집중 상태 |
| 03 rift-ray | 8층 관리자 공격 |
| 04 coordinate-wedge | 7층 좌표 공격 |
| 05 axis-anchors | 7층 교정 방어막 유지 상태 |
| 06 causality-bolt | 6층 인과 공격 |
| 07 memory-compression | 5층 기억 압축 공격 |
| 08 signature-stroke | 4·1층 일반·모방 공격 |
| 09 verdict-stamp | 4·2·1층 반격 집행, 1층 예약 단독 집행 |
| 10 isolation-ring | 3층 격리 공격 |
| 11 seal-energy-core | 2층 일반·예약 공격 |
| 12 identity-scanner | 1층 복제 기록 상태 |
| 13 suppression-band | 출력 억제·모방 금지 상태 |
| 14 preservation-band | 5층 기억 보존 상태 |
| 15 document-barrier | 9층 일반 방어막 |
| 16 observation-barrier | 절대 방어막 |
| 17 correction-barrier | 7층 일반 방어막 |
| 18 general-barrier | 나머지 일반·시간제 방어막 |

8층 잔류체 공격의 유리 효과, 기억 기록, 증폭, 예약·집행 모래시계, 주문 봉인 자물쇠는 기존 모델을 재사용한다. 머리 위 의도 표시와 피격·소거 효과도 유지한다. 공격 판별은 표시 문자열 대신 전투 동작을 사용한다.

## 리소스와 표시 방식

- 추가 리소스 약 35MB. 원본 해시·크기·삼각형 수·텍스처 해상도는 `DescentAuthorized/Resources/Reality/VFX/Authored/manifest.json`에 기록했다.
- 원본은 각각 단일 메시이며 별도 애니메이션이 없다. 준비 단계 크기 변화, 방향 정렬, 회전, 수축과 이동을 런타임에서 적용한다. 개별 패널 관절 애니메이션은 포함하지 않는다.
- 방마다 필요한 모델만 미리 읽고, 표시할 때 복제한다. 방을 나갈 때 캐시를 해제한다.
- 방어막은 캐릭터 크기에 맞춰 배치하고 열린 면을 카메라로 향하게 했다. 7층 교정 방어막은 폭·방향·투명도를 조정해 몸통과 공격 자세가 보이도록 했다.
- 일시정지에는 공격·상태 효과 시간이 멈춘다. 동작 줄이기 설정과 승리·패배에서는 진행 중 효과를 정리한다.

## 확인 결과

iPad Pro 13 M5 / iOS 26.5 시뮬레이터에서 실제 방을 로드하고 production 렌더러를 호출하는 DEBUG 진단으로 확인했다. 실기기 검증은 이번 결과에 포함하지 않는다.

| 항목 | 결과 |
|---|---|
| 1~9층 전투방 | 21개 로드·촬영 완료 |
| 제공된 모델 | 18종 모두 로드 |
| 일반·강공격·반격 표시 | 63/63 통과 |
| 공격 중 일시정지 | 63/63 통과 |
| 지속 상태 정리 | 21/21 통과 |
| 대표 방 연속 공격 영상 | 9·8·5·3·1층 5개 |
| 영상 촬영 방의 수명 검사 | 방어막 일시정지, 동작 줄이기 안정화, 공격 제거, 전투 종료 방어막 제거 모두 통과 |
| 최종 교정 방어막 재검증 | 7층 관리자·잔류체 두 방 재촬영·수명 검사 통과 |
| 회귀 테스트 | CombatEffectCatalogTests 3개 + CombatPresentationTimelineTests 8개 통과 |
| 시뮬레이터 앱 빌드 | 성공 |

수치 원본 요약은 [verification-summary.json](verification-summary.json)에 있다. 전체 장면의 공격·방어막·상태 스크린샷과 대표 연속 재생 영상을 직접 비교했다. DEBUG 진단은 효과와 상태를 의도적으로 주입하는 검사이며 전체 캠페인 수동 플레이를 뜻하지 않는다.

## 검증 자료와 재실행

프로젝트 작업공간의 `outputs/combat-effects-integration-20260930/index.html`에서 방과 장면을 선택해 확인할 수 있다. `final-simulator/`에는 최종 21개 방의 화면과 보고서, `lifecycle-video/`에는 대표 영상과 시간별 상태가 있다. 대용량 검증 영상은 Git에 포함하지 않는다.

```sh
python3 docs/combat-effects/verify_effects.py \
  --app /tmp/c5-natural-attack-app/Build/Products/Debug-iphonesimulator/DescentAuthorized.app \
  --output ../outputs/combat-effects-integration-20260930/final-simulator
```

특정 방만 재실행할 경우 `--rooms`를 사용한다. 실행별 `summary.json`은 해당 실행 범위만 포함하므로 전체 집계는 각 방의 `report.json`을 기준으로 한다.

브랜치 번호·업로드 순서는 [branch-order.md](branch-order.md)에 정리했다. #198의 이력을 재작성하지 않았으며 #199가 #198을 포함한다. 원격 업로드와 병합은 수행하지 않았다.
