# #210 보스방 공간 이동 카메라

## 결과

9층~1층의 관리자 보스방 9곳에 카메라 45개, 시선 타깃 36개, 재생용 장면 9개를 추가했다. 카메라의 실제 위치가 왼쪽 장치 옆 → 중앙 전경 → 오른쪽 장치 옆 → 보스 정면으로 이동한다. 기본 길이는 12초다.

- 브랜치: `feat/#210-boss-room-sweep-cameras` (기준 `8f89ac2`)
- 이슈: https://github.com/wsysangyoung2730-debug/2026-C5-DescentAuthorized/issues/210
- 계획: [PLAN.md](PLAN.md)
- 전체 작업 파일: 프로젝트 루트의 `outputs/DA_F01_F02_F03_F04_F05_F06_F07_F08_F09_F10_Combined_v068_boss_room_sweep_cameras.blend`
- Git에 기록한 카메라 전용 라이브러리: [EncounterCameraRigs_v068.blend](EncounterCameraRigs_v068.blend)
- 좌표·참조 오브젝트·시간별 포즈·렌즈와 센서 설정: [camera-manifest.json](camera-manifest.json)

v067 원본은 덮어쓰지 않았다. 전체 2.6GiB 장면 파일은 기존 `outputs/`에 보관하고, Git에는 재현 스크립트·카메라 라이브러리·전달 명세·검증 기록을 남긴다. 새 모델·재질·조명 변경은 없다.

## Blender에서 보기

1. 전체 v068 파일을 연다.
2. 상단 장면 목록에서 `PREVIEW_F09_EncounterSweep` 등 보고 싶은 층을 선택한다.
3. 카메라 보기(숫자 키패드 0)에서 타임라인을 1프레임으로 옮기고 재생한다.
4. 1~361프레임, 30fps로 좌측·전경·우측·복귀를 확인한다. 337~361프레임은 복귀 후 정지 구간이다.

각 원래 보스방에는 `Fxx_EncounterCameras_v068` 컬렉션이 추가돼 있다. 그 안의 `CAM_Fxx_Encounter_Left/Wide/Right/Return`은 구도 편집용 정적 카메라, `CAM_Fxx_Encounter_Preview`는 이동 재생용 카메라다. `TARGET_...` 오브젝트의 `source_object`와 `world_offset_from_source`에 실제 피사체와 오프셋을 기록했다. 피사체 이름만 참조하므로 원래 오브젝트에 제약이나 부모를 추가하지 않는다.

미리보기 장면은 기존 방의 오브젝트를 공유한다. 카메라 확인 전용으로 사용하고, 그 안에서 방의 메시를 편집하면 원래 장면에도 반영된다는 점에 유의한다. 기존 장면의 활성 카메라·프레임 범위·조명은 유지했다.

## 층별 구도

| 층 | 주요 피사체 | 구도 검토 |
| --- | --- | --- |
| 9 | 기록함·문서 선반 / 기록 단상 / 파손 유리함 | [9층](contact-sheets/F09-sweep.jpg) |
| 8 | 관측 렌즈 / 대형 링 / 우측 모니터·후면 통로 | [8층](contact-sheets/F08-sweep.jpg) |
| 7 | 위상 프리즘 / 좌표 기준 게이트 / 보정 장치 | [7층](contact-sheets/F07-sweep.jpg) |
| 6 | 시간 모니터 / 인과 사슬 장치 / 순서 검증 콘솔 | [6층](contact-sheets/F06-sweep.jpg) |
| 5 | 정체성 콘솔 / 기억 추출 의자 / 기억 보관함 | [5층](contact-sheets/F05-sweep.jpg) |
| 4 | 증거 처리 장치 / 책임 심판대 / 판결 장부 | [4층](contact-sheets/F04-sweep.jpg) |
| 3 | 좌측 경계 날개 / 동의 잠금 허브 / 우측 경계 날개 | [3층](contact-sheets/F03-sweep.jpg) |
| 2 | 유지 설비 / 봉인 심장 / 반대편 유지 설비 | [2층](contact-sheets/F02-sweep.jpg) |
| 1 | 정체성 권한 기둥 / 최종 승인 왕관 / 인계 권한 기둥 | [1층](contact-sheets/F01-sweep.jpg) |

1~3층은 기존 주 카메라가 바닥 경계 뒤에 있어 최종 복귀점을 실내로 조정했다. 8층 우측은 칸막이가 콘솔을 가리고 그 뒤에 빈 벽이 크게 보여, 칸막이 안쪽에서 관측 모니터와 후면 통로를 바라보도록 위치와 시선을 보정했다.

## 검증

- Blender 5.2.0 LTS에서 저장 후 파일을 다시 열었다.
- v067 SHA-256이 최초 조사와 같음을 확인했다. 검사한 기존 객체의 위치·회전·크기·부모·데이터/재질 연결·토폴로지 개수와 기존 카메라 설정도 같다.
- 9개 방 × 361프레임 = **3,249개 포즈**의 위치·회전·렌즈·시프트가 명세와 허용 오차 안에서 일치했다.
- 카메라 중심의 프레임 사이 선분과 주변 26방향 25cm 범위를 검사했다. 표면 교차·근접 후보가 검출되지 않았다.
- 9개 방 × 7구도 = **63장**을 실제 장면에서 렌더하고 검토했다. 원래 장면 화면 비율을 유지했다.
- 상세 수치: [verification.json](verification.json), 각 층의 `verification-xx.json`.

구도 검토 이미지는 Workbench의 형상 확인용 렌더이며 최종 재질·조명이나 앱 화면이 아니다. 경로 검사는 카메라 중심 주변의 표본 검사로, 전체 카메라 체적의 충돌을 수학적으로 보증하지 않는다. 이 파일에 원래 분리된 전투 캐릭터를 새로 합치지 않았으므로 일부 단상은 비어 있다.

## 이후 앱 연결

이번 변경은 Blender 저작까지다. 조우 대사 후 자동 재생되는 게임 기능은 아직 연결하지 않았다. 현재 게임 내보내기는 카메라를 명시적으로 선별하고 애니메이션을 제외하므로, 이 파일을 단순 교체하는 것만으로 재생되지 않는다.

다음 단계는 조우 종료 시 대사 이미지를 내리고 이동 포즈를 재생한 뒤, 앱이 보정한 전투 카메라로 연결하는 것이다. 플레이 중 일시정지·건너뛰기·동작 줄이기도 그 단계에서 처리한다. 좌표계와 삽입 지점은 [계획 문서](PLAN.md)의 앱 연결 계약을 따른다.

## 재현

Blender 실행 파일을 이용해 원본 v067을 열고 `author_cameras.py`에 새 출력 경로와 이 문서 폴더를 전달한다. 기존 출력 파일이 있으면 덮어쓰지 않고 중단한다.

```sh
blender --background ORIGINAL.blend --python author_cameras.py -- \
  --output NEW_OUTPUT.blend --evidence EVIDENCE_DIRECTORY
blender --background NEW_OUTPUT.blend --python verify_render.py -- \
  --evidence EVIDENCE_DIRECTORY
python3 make_contact_sheets.py
```

`verify_render.py --skip-render`는 이미지 생성 없이 재개방 애니메이션과 경로 검사를 수행한다. 전체 v068 파일은 아직 원격에 올리지 않았으며 이 브랜치도 로컬 커밋 상태다.
