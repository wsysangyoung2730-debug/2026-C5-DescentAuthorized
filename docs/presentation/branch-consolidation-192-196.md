# #192~#196 브랜치 정리

2026-10-01 · 이슈별 대표 브랜치 하나와 기존 세부 커밋을 유지한다.

## 정리 기준

기존 20개 브랜치는 하나의 누적 이력 안에 있으며 모든 끝 커밋이 `3022140`과 #200의 이력에 포함됨을 확인했다. 이슈별 대표 브랜치를 각 작업의 마지막 커밋까지 fast-forward하고 중간 브랜치 15개를 정리한다. 커밋 재작성, squash, rebase 및 develop/main 병합은 수행하지 않는다.

과거 수정은 이슈별로 교차 진행됐으므로 대표 브랜치에도 앞서 작업한 다른 이슈의 변경이 포함된다. 이슈 번호 순서는 작업 완료 순서와 같지 않다. 독립적인 기능 브랜치로 이력을 재구성한 것은 아니다.

## 대표 브랜치

| 이슈 | 브랜치 | 작업 종료 커밋 |
|---|---|---|
| #192 | `feat/#192-spell-acquisition-glow` | `85e20cd` |
| #193 | `feat/#193-combat-status-hud` | `564661f` |
| #194 | `feat/#194-middle-gate-transition` | `8cdea16` |
| #195 | `feat/#195-descent-portal-iris` | `d43bd24` |
| #196 | `feat/#196-enemy-combat-motion` | `3022140` |

## 기존 브랜치와 보존된 끝 커밋

아래 브랜치 이름은 과거 작업 기록이다. 삭제되는 브랜치의 끝 커밋도 대표 #196 및 후속 #197~#200에서 계속 접근할 수 있다.

| 기존 브랜치 | 끝 커밋 | 처리 |
|---|---|---|
| `add/#192-acquisition-glyph-assets` | `85e20cd733e059dc7f5b78a857c952a82f1fe259` | 중간 브랜치 삭제 |
| `feat/#192-spell-acquisition-glow` | `cc0cd20da01873b2486fa363adfc1416c765343a` | 대표 브랜치 유지·fast-forward |
| `feat/#193-combat-status-hud` | `7c88d94f8a69bed89c926e37d2f6ebe7eee5abb0` | 대표 브랜치 유지·fast-forward |
| `feat/#194-middle-gate-transition` | `2ec4369b51d3ee676b6d01c2878a913fc58da9cf` | 대표 브랜치 유지·fast-forward |
| `feat/#194-room-window-previews` | `5f1daca080320651ab8d2540b15709bdbca76ee1` | 중간 브랜치 삭제 |
| `feat/#195-descent-portal-iris` | `1c10256f477f13f5e98036b40d568878c5b920de` | 대표 브랜치 유지·fast-forward |
| `feat/#195-mysterious-portal-veil` | `747f1dc813d78734cf3078b0a7aa0b6dec25435a` | 중간 브랜치 삭제 |
| `feat/#196-articulated-combat-motion` | `3fba1dd45ba64a257454562174cac09335a342d6` | 중간 브랜치 삭제 |
| `feat/#196-enemy-combat-motion` | `bd0c796583445a99e807940a42fd4ec5bd46460a` | 대표 브랜치 유지·fast-forward |
| `fix/#193-status-panel-layout` | `564661fb193abf99e56f67f04191a5456cd33fb7` | 중간 브랜치 삭제 |
| `fix/#194-first-floor-door-depth` | `1c289ca53252d7a67bdc72e1949d219a2eb36c75` | 중간 브랜치 삭제 |
| `fix/#195-iris-housing-clearance` | `d43bd248bb11390f6a7fbf5c9391fb93e2357798` | 중간 브랜치 삭제 |
| `fix/#195-portal-shader-output` | `028d2a9fe944d80105cb192dd07910c45d854bb5` | 중간 브랜치 삭제 |
| `fix/#196-legacy-joint-bindings` | `000570d6a3a165ab51bf37d703ca607ec9892f72` | 중간 브랜치 삭제 |
| `fix/#196-mechanical-cuff-boundary` | `76079c3472545bb2621aafc97592f9a2d7c523f9` | 중간 브랜치 삭제 |
| `fix/#196-mechanical-limb-isolation` | `260ae0562bd24fcb1de4067adf1de9fa4f8b425c` | 중간 브랜치 삭제 |
| `fix/#196-presentation-verified` | `3022140b6636e71c0b5134d7c691fde9ffb8bb13` | 중간 브랜치 삭제 |
| `fix/#196-rigid-arm-chains` | `ea45c5fed91ce76e18ec5031d4b1b343e64a3b9f` | 중간 브랜치 삭제 |
| `fix/#196-rigid-stamp-panels` | `fe548856fa6ce1cfd513fc794e015911a5269a84` | 중간 브랜치 삭제 |
| `fix/#196-rigid-weapon-motion` | `6818690c1811b42d1b986a80cce56f0da2aeebe1` | 중간 브랜치 삭제 |

## 확인

- 전체 20개 기존 끝 커밋의 #196·#200 포함 여부 확인.
- 삭제 대상 브랜치를 참조하는 열린 PR 없음 확인.
- 원격 브랜치를 한 번의 atomic 업데이트로 갱신한다.
- 이슈 #192~#196은 대표 브랜치 하나와 관련 세부 커밋 링크를 사용한다.
- 정리는 참조와 문서에 한정하며 게임 코드·에셋을 변경하지 않는다.
