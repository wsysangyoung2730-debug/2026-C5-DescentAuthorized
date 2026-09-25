# 전투 공격·무력화 모션

9층 기록 관리자부터 5층 원본 기억 관리자까지 9종의 일반 공격, 강공격, 무력화 모션을 강화했다. 기존 정점·UV·관절 가중치와 대기 모션은 보존했다.

| 구간 | 재생 시간 | 충격 시점 | 동작 |
| --- | --- | --- | --- |
| 일반 공격 | 1.0초 | 시작 후 0.46초 | 준비 → 짧은 타격 → 0.96초에 기본 자세 복귀 |
| 강공격 | 1.3초 | 시작 후 0.62초 | 큰 준비 → 강한 타격 → 1.28초에 기본 자세 복귀 |
| 무력화 | 1.8초 | 해당 없음 | 지지력 상실 → 상체 붕괴 → 마지막 자세 유지 |

각 `motion.json`에 재생 범위와 공격 충격 시점(`impact`), 복귀 완료 시점(`settledAt`)을 기록한다. USD는 30fps로 표본화하므로 프레임 사이의 충격 시점은 보간한다.

- 9층 관리자: 검을 당긴 뒤 찌르는 동작과 반대쪽 팔의 균형 동작.
- 8층 관리자: 대포를 조준한 뒤 발사 시점 직후 상체·팔 반동.
- 8층 잔류체: 양쪽 발톱을 교차하는 넓은 휘두르기.
- 7층: 대각선 타격과 상체 회전.
- 6층: 준비 자세를 유지한 뒤 짧고 강하게 내리치는 동작.
- 5층: 상체 회전과 양팔 휘두르기. 관리자의 단상은 고정한다.

관리자는 발·단상을 고정하고 상체를 약 60도로 접는다. 잔류체는 상체를 약 66도로 접고 몸 전체를 기울인다. 잔류체의 바닥 침투는 각 키 프레임에서 보정한다. 머리와 팔은 시간차를 두고 처지고, 최종 자세는 클립 끝까지 유지한다.

## 편집 및 재현

`CombatActors_Rigged.blend`는 9종 리그와 `DA_ACTOR_…` 장면, 구간·충격 마커, 검토용 카메라를 포함한다. 이 파일이 이번 모션의 편집용 라이브러리다. 기존 `legacy-actor-motion/LegacyActors_Rigged.blend`와 외부 v051 파일은 이전 모션의 기록이다. 저장소 파일 크기를 제한하기 위해 이 검토 파일에만 1024px 텍스처를 내장했다. 앱의 2048 / 1024 / 512px 자산과 원본 GLB는 변경하지 않았다.

제공된 원본 GLB 9개 경로를 줄마다 기록한 inventory 파일로 저장소 루트에서 실행한다.

```sh
blender -b --python docs/reality-assets/expansion-integration/build_actors.py -- \
  --inventory /tmp/actor-paths.txt --output /tmp/actors --all
python docs/reality-assets/optimize_portable_exports.py \
  --source /tmp/actors --output /tmp/portable-actors --image-python PILLOW_PYTHON
```

`build_actors.py`가 모든 애니메이션과 임팩트 마커를 만들고, 2048px USD 내보내기 후 편집용 라이브러리의 내장 텍스처를 줄인다. `optimize_portable_exports.py`는 USD와 Pillow가 설치된 Python 환경을 사용한다. 각 캐릭터 폴더의 3종 USDC와 `motion.json`을 함께 교체한다.

## 확인 자료

- `asset-comparison.json`: 기존 앱과 9종의 정점, 인덱스, 법선, UV, 관절 가중치, 대기 모션 전체 표본이 일치함을 확인.
- `pose-validation.json`: 9종의 일반·강공격·무력화 전체 프레임에서 지면 침투와 관리자 발·단상 이동을 검사.
- `actor-report.json`: 재생 범위, 충격·무력화 자세의 높이, 관절 회전, 루트 이동 기록.
- `expansion-contact-sheet.jpg`, `legacy-contact-sheet.jpg`: 대기 / 강공격 충격 / 최종 무력화 자세 비교.
- `source-artifact.json`: 편집용 Blender 파일 크기와 SHA-256.

이 리그는 기존 5관절 변형 리그를 유지한다. 긴 검·지팡이·등 장식은 별도의 강체 관절이 없으므로 큰 동작에서 함께 휜다. 원본을 재리깅한 강체 무기나 천 시뮬레이션은 포함하지 않는다.
