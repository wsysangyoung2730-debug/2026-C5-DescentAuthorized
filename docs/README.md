# 문서 관리 안내

> 문서 상태: 관리 기준
> 적용 기준: `develop @ dd2f8e2` (`#74` 포함)
> 마지막 갱신: 2026-09-01

이 디렉터리는 현재 구현, 출시 목표, 과거 기준선을 구분해 관리한다. 루트 문서는 항상 최신 기준이며, 보관 폴더의 문서는 특정 마일스톤을 재현하기 위한 읽기 전용 기준선이다.

## 문서 구분

### 최신 기준 문서

- `PRD.md`: 제품 목표와 범위
- `LEVEL_FLOW.md`: 층별 진행과 콘텐츠 배치
- `COMBAT_SYSTEM.md`: 전투 규칙과 밸런스
- `SPELL_GLYPH_SPEC.md`: 주문과 문양 입력 규칙
- `UI_UX_SPEC.md`: 화면과 상호작용 기준
- `TUTORIAL_SPEC.md`: 상황별 튜토리얼 노출과 학습 설계
- `NARRATIVE.md`: 서사와 대사
- `CORE_IMPLEMENTATION_STATUS.md`: 실제 구현 현황

### 운영 및 참고 문서

- `AUDIO_ASSET_MANIFEST.md`: 음향 리소스 연결 기준
- `GAME_CENTER_SETUP.md`: Game Center 설정
- `IMPLEMENTATION_PLAN.md`: 과거 비UI 구현 계획
- `INPUT_IMPLEMENTATION_PLAN.md`: 입력 구현 기준과 과거 계획
- `reality-assets/`: Reality 에셋 내보내기 및 검증 자료

### 마일스톤 문서

- `archive/mvp-baseline/`: 현재 최신 `develop`과 74번까지의 MVP 기준선
- `releases/1.0/`: 1층부터 10층까지의 정식 출시 목표와 차이 분석

## 관리 원칙

1. 최신 기획은 루트 문서에서만 수정한다.
2. `archive/`의 보관본은 생성 후 내용을 수정하지 않는다.
3. 브랜치나 이슈마다 전체 문서를 복제하지 않는다.
4. MVP, 알파, 베타, 정식 출시처럼 의미 있는 시점에만 기준선을 추가한다.
5. 문서 변경의 이유와 영향은 `CHANGELOG.md`에 기록한다.
6. 실제 구현 여부는 `CORE_IMPLEMENTATION_STATUS.md`에서 관리한다.
7. 출시 목표와 현재 구현의 차이는 `releases/1.0/GAP_ANALYSIS.md`에서 관리한다.

## 문서 상태 값

- `현재 구현 기준`: 코드와 대조가 끝난 최신 문서
- `정리 중`: 현재 구현과 대조 중인 문서
- `출시 목표 작성 중`: 1.0 목표를 확장하는 문서
- `운영 참고`: 에셋, 서비스 또는 배포 절차 문서
- `과거 계획 참고`: 구현 이전의 계획을 보존한 문서
- `보관본`: 특정 마일스톤의 수정 금지 문서
