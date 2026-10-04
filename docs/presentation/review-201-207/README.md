# 전투·층 이동 개선 검증 (#201–#207)

기준: 원격 `feat/#200-compact-damage-order-panel`의 `2eadd12`. 이슈마다 브랜치 하나를 사용하고 세부 단계는 커밋으로 관리했다. 아래 순서로 누적되며 마지막 #207에 전체 변경이 포함된다.

| 이슈 | 브랜치 | 기록 |
|---|---|---|
| #201 | `perf/#201-combat-room-prefetch` | [사전 준비](issue-201.md) |
| #202 | `fix/#202-defeat-presentation-lifecycle` | [처치 연출](issue-202.md) |
| #203 | `fix/#203-single-reward-acquisition` | [두루마리 수령](issue-203.md) |
| #204 | `fix/#204-door-portal-and-fixed-platforms` | [문과 발판](issue-204.md) |
| #205 | `fix/#205-absolute-barrier-guidance` | [절대 방벽 안내](issue-205.md) |
| #206 | `fix/#206-seal-spell-availability` | [해제 조건·자동 취소](issue-206.md) |
| #207 | `fix/#207-acquisition-glyph-fidelity` | [습득 문양](issue-207.md) |

## 최종 확인

- 핵심 테스트 235개 통과.
- iOS Simulator Debug 및 Release 빌드 성공.
- 10~1층 하강문과 5층 중앙문: 고정 발판과 문 개폐 진단·화면 확인.
- 9·8층 처치 후 모델 숨김, 9·8·5층 두루마리 수령 1회 진단 통과.
- 8층 실제 앱에서 첫 행동 후 안내, 안내 확인, 봉인 해제 및 재비활성 흐름 확인.
- 28종 입력 좌표 기반 습득 문양 재렌더링 및 전체 비교 화면 확인.
- 브랜치 정리 전후 Git tree 일치 확인.

## 사전 준비 측정 해석

전투 중에는 파일만 1MB씩 준비하고 RealityKit 디코딩은 전투·처치 연출이 끝난 뒤 수행한다. 4~1층 측정에서 전투 중 p95 약 16.7ms, 최대 17.3ms. 디코딩까지 완료한 방의 CPU ready 전환은 0.32~0.46초였다. 아직 준비 중인 방을 바로 열면 남은 작업에 따른 Loading이 표시된다.

Mac 잠금으로 수동 클릭 검증은 제한되었고, 격리된 DEBUG 저장 상태의 실제 게임 명령과 시뮬레이터 캡처를 사용했다. 실기기 전체 플레이, 발열/메모리 및 프레임 성능은 아직 확인하지 않았다. 2층 원형 기계 문틀은 보존했고, 하강 이펙트 면만 사각으로 변경했다.
