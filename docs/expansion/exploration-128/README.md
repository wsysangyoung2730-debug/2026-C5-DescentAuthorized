# 5~7층 전투 시점 및 잔류체 조사

## 브랜치 계보

`feat/#125-expansion-integration-polish` → `feat/#126-expansion-battle-camera` → `feat/#127-expansion-residue-investigation` → `test/#128-expansion-exploration-validation`

## 변경 사항

- 전투 배경 드래그를 화면 컨테이너에서 수신하며 첫 이동량도 반영한다. 입력판·카드 영역에서 시작한 드래그와 안내/일시정지 중 입력은 시점 조작에 사용하지 않는다.
- 기존 카메라 회전 한계와 기본 시점 복귀를 유지한다.
- 각 잔류체방에 두 개씩, 총 여섯 조사 기록을 추가한다. 7층 좌표 교정, 6층 결과 지연, 5층 기억 누락과 각 전투의 대응 방법을 기록한다.
- 두루마리 표식은 방의 실제 기물에 연결한다. 조사 중 적을 숨기고 좌우 65도 범위에서 탐색한다.
- 마지막 두루마리를 닫으면 기존 공통 조사 흐름으로 카메라를 정면에 복귀·고정한 뒤 적을 드러낸다. 이후 입장 및 출전 준비가 이어진다.
- 조사 기록은 기존 저장 항목 `readRecordIDs`를 사용한다. 도중 복귀와 중복 열람을 지원하며 다른 층의 기록을 완료 조건에 포함하지 않는다.
- 이전 저장의 잔류체 출전 준비에서도 미조사 기록이 있으면 조사를 먼저 진행한다. 보스방에는 잔류체 조사를 삽입하지 않는다.

## HP 확인 결과

기존 기획 `Floors_7_5_Gameplay_Design_v3.md`의 회복 규칙을 유지한다.

| 시점 | HP |
| --- | --- |
| 일반 전투 시작 | 진행 데이터의 남은 HP 유지 |
| 잔류체 승리 | 남은 HP +20, 최소 60 / 최대 100 |
| 보스 이후 다음 층 | +30, 최대 100 |
| 패배 후 재도전 | 출전 준비로 복귀, 100으로 회복 |
| 전투 중 저장에서 재실행 | 출전 준비로 복귀, 100으로 회복 |

여섯 전투에서 HP 37 진입, 실제 패배, 재도전의 HP 100 및 첫 턴/예약 상태 초기화, 전투 저장 복귀를 테스트했다.

## 검증

- Swift 테스트 178개 통과.
- iOS Simulator Debug 빌드 성공.
- 6개 조사 기물 × 3개 품질의 존재·경계·카메라 상대 각도 검증: 18개 통과 (`asset-validation.json`).
- 실제 Simulator 장면에서 6개 전투 + 3개 조사 진입 검증: 9개 통과 (`runtime-validation.json`).
- 실제 카메라 행렬이 양방향 시선 이동에 따라 변하고, 복귀하면 원위치로 돌아오며, 고정 후에는 이동을 거부하는지 확인했다.
- 조사 진입에서 적이 숨겨지고 두 조사 앵커가 연결되는지, 전투 진입에서 적이 표시되는지 확인했다.
- Mac 잠금으로 최종 터치 드래그 및 두루마리 닫기부터 적 등장까지의 수동 연속 조작 확인은 남아 있다. 실행 진단은 실제 카메라/장면 API 검증이며 터치 자동화 검증은 아니다.

## 재현

Simulator에 Debug 앱을 설치한 뒤 실행한다. 모든 프리뷰는 임시 메모리 저장소를 사용한다.

```sh
python3 docs/expansion/exploration-128/verify_runtime.py --device <SIMULATOR_UDID> --output /private/tmp/c5-exploration-qa
```

일반 조사 화면: `--preview-floor 7 --preview-stage entrance` (7 대신 6/5 가능).
전투 화면: `--preview-floor 7 --preview-battle` (보스는 `--preview-boss` 추가).
실행 진단은 `--expansion-exploration-diagnostics`를 추가한다. DEBUG 빌드의 분리된 프리뷰에서만 동작한다.
