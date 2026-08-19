# 하강 승인: 제0균열

> DESCENT AUTHORIZED: Rift Zero

Apple Pencil 또는 손가락으로 마법진을 그려 층 관리자와 싸우는 iPadOS용 턴제 전략 배틀 어드벤처입니다.

## 프로젝트 열기

Xcode에서 아래 프로젝트 파일을 엽니다.

```text
DescentAuthorized.xcodeproj
```

권장 환경:

- Xcode 26.5 이상
- iPadOS 18.0 이상
- iPad Simulator 또는 Apple Pencil을 지원하는 iPad
- Scheme: `DescentAuthorized`

## 기술 방향

- Swift
- SwiftUI
- RealityKit 기반 2.5D 전투 무대
- Apple Pencil 및 손가락 드로잉 입력
- 순수 Swift 턴 상태 관리

현재 저장소에는 개발을 시작하기 위한 iPadOS 프로젝트 골격과 기획 문서만 포함합니다.

## 폴더 구조

```text
DescentAuthorized/
├── App/                 # 앱 진입점
├── Core/
│   └── Game/            # 전투 상태와 공통 게임 규칙
├── Features/
│   ├── Home/            # 시작 화면
│   └── Battle/          # 전투 기능
└── Resources/           # 이미지, 사운드, 에셋
docs/
└── PRD.md               # 게임 기획 기준 문서
```

## 문서

- [게임 PRD](./docs/PRD.md): 전체 방향과 확정 범위
- [전투 시스템 및 밸런스](./docs/COMBAT_SYSTEM.md): 턴 규칙, 수치와 적 패턴
- [주문 및 마법진](./docs/SPELL_GLYPH_SPEC.md): 주문 5종의 획과 판정 기준
- [층별 진행 및 튜토리얼](./docs/LEVEL_FLOW.md): 10층부터 8층까지의 플레이 흐름
- [UI/UX](./docs/UI_UX_SPEC.md): 화면, 입력, 상태와 접근성
- [스토리 및 대사](./docs/NARRATIVE.md): 정보 공개 순서, 기록과 실제 대사

## Git 전략

### 태그 컨벤션

태그는 반드시 소문자로 작성합니다.

| 태그 | 사용 기준 |
| --- | --- |
| `init` | 가장 처음 Initial Commit에 사용 |
| `feat` | 새로운 기능 구현 |
| `fix` | 버그나 오류 해결 |
| `docs` | README, 템플릿 등 문서 수정 |
| `setting` | 프로젝트 관련 설정 변경 |
| `add` | 사진 등 에셋이나 라이브러리 추가 |
| `refactor` | 기존 코드 리팩터링 또는 수정 |
| `chore` | 중요도가 낮은 기타 수정 |

### 커밋 컨벤션

```text
[태그] 작업 내용
```

- 태그는 소문자로 작성합니다.
- 작업 내용은 한글로 작성합니다.
- 제목은 50자를 넘지 않도록 간단한 명령조로 작성합니다.
- 추가 설명이 필요하면 커밋 본문에 작성합니다.

예시:

```text
[feat] 마법진 입력 기능 구현
[docs] 전투 규칙 문서 수정
[setting] 프로젝트 기본 설정 추가
```

### 브랜치 컨벤션

```text
태그/#이슈번호-작업하는파일
```

예시:

```text
feat/#1-runeDrawing
docs/#2-readme
setting/#3-projectStructure
```

### 브랜치 전략

#### `main`

출시에 사용하는 브랜치입니다.

#### `develop`

기본 개발 브랜치이며, 완료된 기능을 합쳐 최종 확인합니다.

- 개발 완료 후 변경 사항은 반드시 `develop`에 병합합니다.
- 개인 브랜치에서는 `develop`을 먼저 병합해 충돌을 확인합니다.
- 확인 후 `develop`을 대상으로 Pull Request를 요청합니다.

#### 작업 브랜치

기능 개발, 버그 수정, 문서 수정, 설정 변경 등 태그가 붙는 모든 작업은 브랜치 컨벤션에 맞는 별도 브랜치에서 진행합니다.
