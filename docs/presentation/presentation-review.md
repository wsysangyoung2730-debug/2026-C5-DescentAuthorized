# 전투 UI·관절 모션·문 연출 후속 수정 (2026-09-30)

전체 결과 브랜치: **fix/#196-presentation-verified**. 시작점은 `add/#192-acquisition-glyph-assets`의 `85e20cd`이다. 범위별 브랜치는 앞선 결과를 포함하는 누적 방식이며, 로컬 커밋으로 남겼다.

## 변경 결과

- 상태 프레임의 큰 투명 여백을 잘라낸 후 모서리를 유지하며 늘린다. 제목·남은 턴·피해량이 프레임 안에 들어가고, 행동·피격 알림은 같은 상태 목록 아래에 쌓인다. 상세 버튼은 목록 제목 옆에 배치한다.
- 잔류체와 보스 21종에 실제 관절 표면을 복원했다. 팔·손·무기 동작을 캐릭터별 공격 클립에 연결했다. 금속 장비는 팔 관절을 따라 강체로 움직이며, 책·지팡이·검·포의 제스처는 각 모델의 클립을 사용한다.
- 8·9층 보스의 5개 관절에 존재하지 않는 최대 40번 관절을 참조하던 표면을 다시 연결했다. 집행 잔류체의 긴 도장이 다리에 끌려 늘어나는 부분은 금속 패널 단위로 결합했다.
- 처치는 2.45초에서 **1.05초**로 단축했다. 파편이 빠르게 분리되고, 마지막에 완전히 사라진다. 일시 정지·재개·전투 재진입 시 가시성도 복원한다.
- 중간문 **12곳**은 원본 Blender 다음 방의 실제 카메라 렌더로 교체했다. 1~4층은 첫 잔류체→두 번째 잔류체→관리자 경로를 각각 구분한다. 1층의 불투명 뒷판 가림과 중앙 봉인 장식 이동도 수정했다.
- 하강문 **9곳**은 짙은 남색·청록색의 느린 안개 파동을 사용한다. 2층 조리개 조각은 테두리 밖으로 튀어나가지 않고 렌즈 안으로 수납된다. 움직임 줄이기에서는 정지된 포탈 화면을 사용한다.

중간문 미리보기는 요청대로 실제 Blender 장면을 촬영한 정지 이미지다. 실시간으로 다음 방 전체를 이중 렌더링하지 않는다. 원본 Blender와 `sources/`는 수정하지 않았다.

## 실제 실행 검증

환경: iPad Pro 13 M5 시뮬레이터, iOS 26.5, 중간 그래픽 품질. 앱을 빌드·설치한 뒤 실제 RealityKit 프레임을 저장하여 확인했다. 전투 UI는 별도로 실제 전투 화면에서 확인했다.

| 항목 | 결과 |
|---|---|
| Xcode 시뮬레이터 빌드 | 성공 |
| 상태·전투 타이밍·층 경로 기존 테스트 | 12개 통과, 실패 0 |
| 모델·품질·관절 번호·텍스처 연결 검사 | 84개 조합 통과 |
| 적별 대기→공격 화면 및 관절 행렬 | 21종 관절 변화 확인 |
| 중간문 개방·목적지 화면 | 12곳 확인 |
| 하강문 개방·포탈 화면 | 9곳 확인 |
| 포탈 시간 변화 | 2초 간격 프레임 차이 확인 |
| 처치 종료·정지·재시작 | 불투명도 0, 비활성화, 정지 유지, 재시작 불투명도 1 확인 |
| 상태 UI | 내 봉인 상태·예약 2개·임박 표시가 프레임 안에 표시되는 것 확인 |

[실행 결과 JSON](review-20260930/runtime-results.json)에 개별 장면과 캡처 파일을 기록했다. 수정한 모델·문은 변경 이후 다시 실행했다. 물리 iPad의 성능 검사와 모든 층의 처음부터 끝까지 플레이 검증은 포함하지 않는다. 마지막 상세 팝오버 재클릭 확인은 Mac 잠금으로 진행하지 못했다.

## 대표 화면

- [상태 UI: 봉인 및 예약 2개](review-20260930/status-two-threats.png)
- [9층 보스 검 공격](review-20260930/attack-floor09_archive_redesign.jpg)
- [8층 보스 포 공격](review-20260930/attack-floor08_administrator_observatory.jpg)
- [4층 집행 잔류체 도장 공격](review-20260930/attack-floor04_rejection_execution_residual.jpg)
- [파편 분리](review-20260930/stamp-fracture.jpg) / [소멸 완료](review-20260930/stamp-death.jpg)
- [1층 다음 잔류체 방](review-20260930/gate-floor01_identity_comparison_residual.jpg)
- [1층 관리자 방](review-20260930/gate-floor01_exit_review_residual.jpg)
- [3층 관리자 방](review-20260930/gate-floor03_quarantine_enforcer_residual.jpg)
- [2층 렌즈 포탈](review-20260930/gate-floor02_seal_maintenance_administrator.jpg) / [2초 후](review-20260930/portal-two-seconds-later.jpg)

## 작업 브랜치와 작은 커밋

| 브랜치 | 범위 |
|---|---|
| fix/#193-status-panel-layout | 프레임 여백·목록 배치·상태 실제 화면 |
| feat/#196-articulated-combat-motion | 관절 런타임, 21종 표면, 빠른 처치와 복원 |
| feat/#194-room-window-previews | 다음 방 연결, Blender 렌더 12장 |
| fix/#196-rigid-weapon-motion | 기계 장비 강체 보정 |
| feat/#195-mysterious-portal-veil | 저채도 포탈 셰이더 |
| fix/#196-legacy-joint-bindings | 8·9층 잘못된 관절 번호 수정 |
| fix/#196-mechanical-limb-isolation / mechanical-cuff-boundary / rigid-arm-chains | 실제 화면에서 발견한 기계 팔·다리 연결 보완 |
| fix/#195-portal-shader-output / iris-housing-clearance | 발광 출력 및 조리개 수납 |
| fix/#194-first-floor-door-depth | 1층 미리보기 가림 및 봉인 장식 |
| fix/#196-rigid-stamp-panels | 긴 도장 금속 표면 결합 |
| fix/#196-presentation-verified | 전체 결과 및 실제 화면 기록 |

## 에셋 재생성 순서

1. `install_articulated_surfaces.py`: 원래 관절 표면 및 공격 클립 복원.
2. `rigid_mechanical_arms.py`: 기계형 관절 및 긴 도장 보정.
3. `repair_legacy_joint_bindings.py`: 8·9층 관절 인덱스 보정.
4. `validate_actor_assets.py`: 최종 연결 검사.

문 렌더는 `render_gate_room_previews.py`, 목적지 목록은 `gate-preview-manifest.json`에 있다. 1층 문을 다시 생성하면 `repair_first_floor_gate_depth.py`를 적용한다.

포탈은 RealityKit의 unlit CustomMaterial에서 emissive 출력을 사용한다. [Apple 공식 설명](https://developer.apple.com/documentation/realitykit/custommaterial/lightingmodel-swift.enum/unlit)에 따라 base color만 설정하여 검게 나오던 문제를 수정했다.


## 8층 → 7층 하강문 추가 수정

브랜치 `fix/#197-floor8-descent-door`. 앞선 검증에서는 포탈 표시를 확인했으나 8층 문틀이 함께 이동하며 찢어지는 문제를 놓쳤다. 기존 8층 문짝에는 상단과 양쪽 문틀의 큰 삼각형이 포함되어 있었다. 닫힌 표면을 문 안쪽 경계에서 정확히 잘라 고정 문틀과 좌우 문짝으로 다시 분리했다. 위치·법선·UV·재질을 보존하며 표면 면적도 변경 전후 동일하다. 다른 층의 문과 공용 열림 동작은 수정하지 않았다.

Xcode 빌드 성공. iPad 시뮬레이터에서 저·중·고 품질 모두 열림 완료, 고정 문틀의 변환 유지, 필수 노드 누락 없음 확인. 실제 렌더에서 개방 도중 및 완료 후 상단·기둥이 유지됨을 확인했다. 중간 품질에서 닫힘 복원과 움직임 줄이기 즉시 개방 화면도 확인했다. 검증은 문 연출 전용 실행 경로이며, 전체 8층 전투부터 7층 입장까지 플레이한 검증은 아니다.

- [닫힌 상태](review-floor8-door/ready.jpg)
- [열리는 도중](review-floor8-door/door-opening.jpg)
- [열림 완료](review-floor8-door/door-open.jpg)
- [닫힘 복원](review-floor8-door/door-reset.jpg)
- [움직임 줄이기](review-floor8-door/door-reduced-motion.jpg)
- [품질별 실행 결과](review-floor8-door/runtime-results.json)

원본 USD로 되돌려 문을 재생성할 경우 `repair_floor8_descent.py`를 마지막에 한 번 실행한다. 중·저 품질 USD는 수정된 본체 USD를 참조하므로 동일한 구조를 사용한다.
