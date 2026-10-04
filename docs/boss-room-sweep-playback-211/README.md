# #211 보스 조우 후 보스방 이동 카메라

## 기준과 범위

- 브랜치: `feat/#211-boss-room-sweep-playback`
- 기준: 카메라 제작 #210 브랜치의 마지막 커밋 `87f3ed5`
- 이슈: https://github.com/wsysangyoung2730-debug/2026-C5-DescentAuthorized/issues/211
- 카메라 원본: [#210 Blender 제작 및 검증](../boss-room-cameras-210/README.md)

9층~1층 보스의 조우 대사가 끝나면 제작된 경로로 방을 보여준 뒤 전투를 시작한다. 원래 조우 진행 상태는 연출 종료까지 유지한다. 10층에는 보스가 없으며 잔류체 조우, 처치 대사, 보상과 엔딩은 같은 연출을 재생하지 않는다.

## 연결 방식

1. Blender에서 검증한 30fps·12초 경로를 작은 JSON 리소스로 앱에 포함한다. 9개 방에 각 361개, 총 3,249개 포즈다.
2. 대사 종료 시 정적인 대사 이미지를 내리고 실제 방의 카메라 위치·방향·화각을 바꾼다.
3. 왼쪽 장치 → 중앙 전경 → 오른쪽 장치 → 보스 정면의 경로를 재생한다.
4. 마지막 1.2초에 앱에서 보정한 실제 전투 구도로 이어준다. 좌표축은 방 루트에서 Z-up → Y-up으로 한 번 변환하고, 화각은 화면 비율에 맞춰 계산한다.
5. 연출 완료 또는 건너뛰기 후 기존 전투 시작 명령을 한 번만 보낸다.

일시정지·설정·앱 비활성화 중에는 연출 시간도 정지한다. 체크포인트 이동이나 타이틀 복귀 시 이전 연출의 완료 작업을 취소한다. 동작 줄이기를 사용하면 연출을 생략한다. 경로 리소스를 읽을 수 없는 경우에도 전투를 막지 않는다.

## 검증 기록

2026-10-03 기준:

| 항목 | 결과 |
| --- | --- |
| 코어 테스트 | 255개 통과. 전 층 조우/전투 대기 경계, 경로 보간, 비정상 데이터, 중단 시간과 중복 완료 방지 포함 |
| 앱 빌드 | Xcode 26.5, Debug iOS 시뮬레이터 빌드 성공 |
| 원본 경로 일치 | 내보내기 검사로 9개 방·3,249개 Blender 포즈와 앱 리소스 일치 확인 |
| 전 층 실제 재생 | 9층→1층 모두 실제 조우 대사 후 12초 경로 완료, 이후 전투 HUD 확인 |
| 전투 구도 복귀 | 9개 층 모두 목표 대비 최종 위치 오차 0, 화각 오차 0. [수치 요약](evidence/runtime-summary.json) |
| 5층 일시정지 | 53.34초 대기 후 카메라 행렬과 화각이 정지 시점과 동일하게 재개됨. 이후 정상 완료 |
| 5층 설정 | 58.23초 대기 후 동일 카메라 행렬·화각으로 재개됨 |
| 5층 건너뛰기 | 설정에서 복귀한 뒤 경로 시간 2.256초에 생략. 목표 위치·화각 오차 0, 회전 내적 1로 전투 진입 |
| 5층 동작 줄이기 | 설정을 켜고 조우 대사 완료 시 경로 시간 0초에 정상 전투 구도로 이동. 검증 후 원래 설정으로 복원 |
| 5층 백그라운드 복귀 | 홈 화면에서 38.99초 대기 후 동일 카메라 행렬·화각으로 재개하고 전투에 진입 |
| 연출 중 타이틀 복귀 | 일시정지 → 타이틀 복귀 확정 후 12초 이상 지나도 타이틀 유지. 이전 연출의 전투 시작이 실행되지 않음 |
| 최종 조작 버튼 | 밝은 5층에서 어두운 작은 바탕과 금색 아이콘의 대비 확인. 버튼별 접근성 식별자와 최종 Debug 재빌드 확인 |

전 층의 좌측·중앙·우측·복귀·전투·HUD를 실제 시뮬레이터에서 캡처했다. 주요 장치와 보스 구도가 보이며, 확인한 정지 화면에서 빈 구도·벽 내부·심한 가림은 발견되지 않았다. `return`은 11.2초 부근으로 전투 구도 보간이 진행 중이며, 정확한 최종 복귀는 `battle` 기록을 기준으로 확인한다.

| 층 | 실제 화면 구도표 |
| --- | --- |
| 9 | [기록 관리자](evidence/F09-runtime.jpg) |
| 8 | [관측 관리자](evidence/F08-runtime.jpg) |
| 7 | [좌표 관리자](evidence/F07-runtime.jpg) |
| 6 | [인과 관리자](evidence/F06-runtime.jpg) |
| 5 | [원본 기억 관리자](evidence/F05-runtime.jpg) |
| 4 | [책임 감사 관리자](evidence/F04-runtime.jpg) |
| 3 | [자발 격리 관리자](evidence/F03-runtime.jpg) |
| 2 | [봉인 유지 관리자](evidence/F02-runtime.jpg) |
| 1 | [최종 승인 관리자](evidence/F01-runtime.jpg) |

일시정지 증거는 [정지](evidence/controls/pause-paused.json)·[재개](evidence/controls/pause-resumed.json)·[전투 복귀](evidence/controls/pause-battle.json), 설정 증거는 [진입](evidence/controls/settings-start.json)·[재개](evidence/controls/settings-resumed.json)·[건너뛰기](evidence/controls/settings-skipped.json)에 기록했다.

추가 증거: [동작 줄이기](evidence/controls/reduced-motion.json), [백그라운드 진입](evidence/controls/background-start.json)·[복귀](evidence/controls/background-resumed.json)·[전투](evidence/controls/background-battle.json), [최종 조작 버튼](evidence/controls/final-controls.jpg).

검증 환경은 iPad mini (A17 Pro), iOS 26.5 시뮬레이터다. 전 층 검증은 `7811eed`, 버튼 대비·개별 접근성 식별자 보완 후 최종 빌드와 5층 화면 재검증은 `ab8a721` 기준이다. 정지 캡처와 진단용 스냅샷은 프레임 속도·성능 측정 자료가 아니며, 실기기 검증과 전 층 전투 완주는 아직 하지 않았다.

## 재현 방법

저장소 루트에서 경로 일치와 코어 동작을 확인한다.

```sh
python3 scripts/export_boss_room_sweep.py --check
swift test
```

Debug 앱에 `--preview-boss-encounter 5 --boss-sweep-diagnostics` 실행 인자를 주면 5층의 실제 조우 대사부터 확인할 수 있다. 층 번호는 1~9로 바꿀 수 있다. 이 프리뷰는 `InMemoryGameSaveStore`를 사용하므로 기존 사용자 세이브를 읽거나 수정하지 않는다.

대사를 마친 후 연출을 끝까지 재생하거나 일시정지·설정·건너뛰기를 조작한다. 진단 JSON과 이미지가 앱 컨테이너의 `Documents/BossRoomSweepDiagnostics`에 기록된다. `entityCamera`와 `fieldOfView`로 정지/재개 상태를, 최종 `battlePositionError`·`battleFieldOfViewError`로 전투 복귀를 비교한다. 구도표는 해당 원본 캡처를 축소·배열하고 HUD 방향만 맞춘 결과다.

## 세부 커밋

| 커밋 | 내용 |
| --- | --- |
| `aff73cb` | #210 카메라 제작 브랜치에서 연결 계획 시작 |
| `f48727c` | 전 층 조우 프리뷰와 전투 대기 경계 검증 |
| `28dbbf8` | Blender 경로의 경량 앱 리소스와 재현 가능한 내보내기 |
| `c6d8400` | 카메라 보간·재생 시간·중단 동작 검증 |
| `5e75753` | 실제 방에서 경로 재생 및 전투 카메라 복귀 |
| `7811eed` | 조우 대사 → 방 연출 → 전투 연결과 조작 버튼 |
| `ab8a721` | 밝은 배경에서 조작 버튼 대비와 개별 접근성 식별자 보완 |
