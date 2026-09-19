# 5~7층 여섯 방 게임 연결

기준 코드는 develop의 `7490d61`(#116까지 통합)이다. 각 작업은 직전 작업 브랜치에서 분기했다. 최종 통합 브랜치는 `feat/#125-expansion-integration-polish`이며, develop으로 재병합하거나 원격에 게시하지 않았다.

## 작업 단위

| 브랜치 | 범위 |
| --- | --- |
| #117 expansion-scene-foundation | 여섯 장면 식별자, 진행 단계별 방·카메라 라우팅, 저장 복귀 검사 |
| #118 expansion-actor-pipeline | 제공 GLB 6종의 관절·8종 모션·품질별 자산과 재생기 |
| #119 floor7-residue-integration | 7층 잔류체 장면, 전투 이벤트와 3D 표현 연결 |
| #120 floor7-boss-integration | 7층 보스방, 런타임 보상 두루마리, 이중 하강 승인 |
| #121 floor6-residue-integration | 6층 잔류체 장면, 비활성·메뉴 상태 입력과 모션 중지 |
| #122 floor6-boss-integration | 6층 관리자 돔, 전투·보상·하강 시점 |
| #123 floor5-residue-integration | 최신 지지대와 측면 기물이 포함된 5층 잔류체 방 |
| #124 floor5-boss-integration | 5층 관리자 방, 빈 보상 슬롯 기준점 |
| #125 expansion-integration-polish | 좌표계 보정, 저장 승인 복귀, 보상 HUD, 품질 검증 및 Blender 검토 파일 |

모든 브랜치의 실제 이름에는 `feat/#번호-` 접두사가 붙는다. 자산·기능·수정·검증을 나누어 한국어 커밋을 남겼다.

## 장면과 시점

| 방 | Blender 장면 | 전투 | 보상 | 문 입력 |
| --- | --- | --- | --- | --- |
| 7층 잔류체 | DA_F07A_CoordinateResidue | F07A_iPadCamera | 해당 없음 | CAM_F07A_BossAccessDoor |
| 7층 관리자 | DA_F07_CoordinateAdministrator | F07_iPad_MainCamera | CAM_F07_RewardSelection | CAM_F07_DescentDoor |
| 6층 잔류체 | DA_F06A_ResultDelayResidue | F06A_iPadCamera | 해당 없음 | CAM_F06A_BossAccessDoor |
| 6층 관리자 | DA_F06B_CausalityAdministrator | F06_iPad_MainCamera | CAM_F06_RewardSelection | CAM_F06_DescentDoor |
| 5층 잔류체 | DA_F05A_MemoryOmissionResidue | F05A_iPad_MainCamera | 해당 없음 | CAM_F05A_BossAccess |
| 5층 관리자 | DA_F05B_OriginalMemoryAdministrator | F05_iPad_MainCamera | CAM_F05_RewardSelection | CAM_F05_DescentDoor |

출전 준비 → 잔류체 전투 → 봉인 입력 → 보스 출전 준비 → 보스 전투 → 보상 선택·학습 → 하강 승인으로 연결한다. 7층에서 6층, 5층을 거쳐 4층 승인 완료까지 이어진다. 잔류체 방에는 보상 선택 단계를 추가하지 않는다.

- 5층 양옆 배치와 잔류체 전용 지지대는 v050 배치를 유지한다. 잔류체 방에 보스 단상을 다시 넣지 않는다.
- 5층의 제공 문 모델은 장식이다. 하강 입력은 별도의 비석·받침대에 연결한다.
- 방 자산에는 보상 두루마리 실물을 저장하지 않는다. 세 개의 빈 앵커에 공용 두루마리를 생성하고, 보상 시점에서만 나타나게 한다.
- 비석·입력 받침대·보상 장치는 비활성 단계에도 환경 기물로 유지한다.
- 전투 재시도는 해당 방의 출전 준비로 돌아간다. 하강 1단계 승인과 2단계 승인 직후 저장 상태를 보존한다.
- 메뉴·설정·앱 비활성 상태에서 입력과 모션을 중단한다. 동작 줄이기를 지원한다.

## 캐릭터와 자산

CoordinateResidue, CoordinateAdministrator, CausalityResidue, CausalityAdministrator, MemoryOmissionResidue, OriginalMemoryAdministrator 6종을 각 방의 `SPAWN_...`에 연결했다.

원본 GLB에는 리그나 애니메이션이 없어 5관절의 보수적인 변형 리그를 만들었다. 대기·등장·예고·일반 공격·강공격·특수 행동·피격·무력화 8개 구간을 `motion.json`으로 재생한다. 7층은 비스듬한 찌르기, 6층은 준비 동작 후 지연된 타격, 5층은 팔을 휘두르는 동작을 사용한다. 이동·천 시뮬레이션은 포함하지 않는다.

RealityKit에서 방의 좌표 변환과 캐릭터 바깥 래퍼의 변환이 중복되지 않도록 처리하되, 관절 애니메이션의 경로는 유지한다. 높이는 잔류체 2.8m, 관리자 4.2m를 기준으로 원본 비율을 유지한다.

- 높음·보통·낮음 텍스처 한도: 2048 / 1024 / 512px.
- 지오메트리·관절 모션은 높은 품질 USDC 하나에 저장한다. 보통·낮음은 텍스처 오버라이드다.
- 오버라이드에도 단위·Z축·30fps·재생 범위를 명시한다.
- 방마다 512×256 HDR 환경과 제한된 실시간 조명을 사용한다.
- 여섯 방 약 300MiB, 캐릭터 여섯 종 약 26MiB. 원본 Blender와 GLB는 게임 앱에 포함하지 않는다.

## Blender 결과

원본 v050의 6층 두 장면은 저장 사용자 수가 0이어서 단순 복사 저장 시 누락될 수 있었다. 모든 15개 장면을 보존한 스냅샷으로 작업했다. 열려 있던 원본과 제공 GLB는 덮어쓰지 않았다.

- 통합 검토: `DA_F05_F06_F07_GameIntegration_v051.blend`
- 캐릭터 편집 라이브러리: `ExpansionActors_Rigged_v051.blend`
- 실제 파일 경로와 SHA-256: `blender-artifacts.json`

통합 파일에는 6개 방의 스폰에 캐릭터가 배치되어 있고, 타임라인의 `ACTOR_...` 마커로 모션을 볼 수 있다. `RuntimePreview_...` 컬렉션의 리그는 검토용이다. `export_rooms.py`가 `runtime_actor_preview` 표시와 하위 메시를 제외하므로 캐릭터가 방과 별도 자산에 중복 포함되지 않는다. 보상 앵커는 남기고 고정 두루마리 3개는 제거했다.

## 검증 결과

- Swift 핵심 로직 테스트 176개 성공. 세 층 전체 진행, 보상 학습, 승인 1단계 및 2단계 저장 복귀 포함.
- iOS Simulator Debug 앱 빌드 성공.
- `validation.json`: 18개 방·18개 캐릭터·3개 공용 두루마리 품질 검증. 필수 카메라·기물·텍스처·좌표계·모션 데이터 누락 없음.
- `runtime-validation.json`: 여섯 방 × 전투 3품질과 문 시점, 보스 보상 시점 총 27건 실행 성공. 여섯 캐릭터의 관절 변화와 환경 로드 확인.
- `reward-runtime-validation.json`: 보스 3개 방 × 보상 3품질 총 9건 실행 성공.
- 실제 게임 화면: 6층 잔류체 전투 HUD·입력판, 5층 보상 선택, 5층 승인 2단계 복귀 후 4층 완료 화면 확인.
- 통합 Blender 파일을 다시 열어 5층 관리자 카메라에서 렌더 확인.

Mac이 잠겨 있어 UI 직접 터치와 Apple Pencil 실기기 조작은 검증하지 못했다. 시뮬레이터 미리보기는 독립된 메모리 저장소를 사용하여 사용자 저장 데이터에 영향을 주지 않는다. 실제 iPad의 메모리·프레임 성능도 별도 실기기 확인 대상이다.

## 재현 도구

`build_actors.py`는 GLB 경로 목록을 받아 리그 라이브러리와 원본 USDC를 만든다. `export_rooms.py`는 보존된 Blender 파일에서 방·HDR·공용 두루마리를 내보낸다. 상위 폴더의 `optimize_portable_exports.py`가 품질별 자산을 만들며, 출력 폴더는 새 경로여야 한다. `assemble_blender.py`는 원본 방과 리그 라이브러리를 합친 별도 검토 파일을 만든다.

```sh
# 저장소 루트에서, usd-core와 Pillow가 있는 Python으로 실행
python docs/reality-assets/expansion-integration/validate_expansion.py \
  DescentAuthorized/Resources/Reality --report /tmp/expansion-validation.json

# Debug 앱 설치 후, 부팅한 시뮬레이터 UUID 지정
python docs/reality-assets/expansion-integration/verify_simulator.py \
  --device SIMULATOR_UUID --output /tmp/expansion-runtime
python docs/reality-assets/expansion-integration/verify_simulator.py \
  --device SIMULATOR_UUID --output /tmp/expansion-rewards --rewards-only
```

실제 진행 화면은 Debug 실행 인수 `--preview-floor 5 --preview-stage reward` 또는 `--preview-floor 6 --preview-battle`로 확인할 수 있다. 승인 복귀는 `--preview-floor 5 --preview-stage descent --preview-approvals 2`로 확인한다. 미리보기 인수는 Release에 포함되지 않는다.
