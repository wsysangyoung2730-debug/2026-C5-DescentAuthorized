# #173·#180 브랜치 정리

2026-10-01 · 이슈별 대표 브랜치 하나에 기존 후속 커밋을 모두 보존한다.

기존 7개 브랜치의 모든 끝 커밋이 각 대표 브랜치의 최종 커밋과 #200 이력에 포함됨을 확인했다. 열린 PR 참조는 없으며, 대표 브랜치를 fast-forward하고 중간 브랜치 5개를 로컬·원격에서 정리한다. 커밋 재작성과 develop/main 병합은 수행하지 않는다. 기존 누적 이력에는 다른 이슈 작업도 포함되어 있다.

| 대표 브랜치 | 최종 커밋 |
|---|---|
| `fix/#173-upper-descent-doors` | `34c744851d70ec0328268e595fb470fd15f8c75e` |
| `fix/#180-battle-camera-and-status` | `18a3868eff492e58e7b2fe80a0c34e7623068fcd` |

## 기존 브랜치와 보존 커밋

| 기존 브랜치 | 끝 커밋 | 처리 |
|---|---|---|
| `fix/#173-upper-descent-doors` | `ee97b3254b00a0175dc71d2f5e92e2cc05dbaa0d` | 대표 브랜치 갱신 |
| `fix/#173-upper-room-import` | `34c744851d70ec0328268e595fb470fd15f8c75e` | 중간 브랜치 삭제 |
| `fix/#180-battle-camera-and-status` | `4b9fcbf289f351734d36598528d58b710ae69c18` | 대표 브랜치 갱신 |
| `fix/#180-battle-camera-distance` | `18a3868eff492e58e7b2fe80a0c34e7623068fcd` | 중간 브랜치 삭제 |
| `fix/#180-battle-subject-framing` | `31331e136d4334ddc80fcb43e26a1ccee5d797d4` | 중간 브랜치 삭제 |
| `fix/#180-battle-visibility-validation` | `e49313fc7264080816c0f7030057aa025d22cd5b` | 중간 브랜치 삭제 |
| `fix/#180-enemy-intent-clearance` | `55a8db502550375b3e3672f8c202410b756071d2` | 중간 브랜치 삭제 |

## 이슈 연결

#173·#180 본문은 대표 브랜치와 후속 검증 기록으로 정리한다. #182~#186에서 사용하던 중간 브랜치 링크도 대표 #180으로 갱신한다. 이슈 제목과 열림/닫힘 상태는 유지한다.
