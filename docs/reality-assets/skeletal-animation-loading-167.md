# #167 시뮬레이터 관절 애니메이션 로딩 오류 복구

브랜치: `fix/#167-skeletal-animation-loading`
기준: `origin/develop`의 `8759c5c`.

## 원인

제보 화면은 9층 높은 품질이다. 시뮬레이터 로그에서도 `floor09_archive_redesign quality=high` 이후 캐릭터 준비 완료가 없었다.
설치된 앱의 `record_administrator.usdc`는 구형 SHA-256 `89cb18631d08c67368e476eae51089b9166a77ad3d4f53d0cce11f6301a3200c`였고, 최신 develop은 `91d713eca671c56f9d624ca3dcb7d03cc02e28bef09d6b3d1d4b5ddaf0be3d48`이다.

구형 파일에는 SkelAnimation이 있지만 SkelRoot가 없어 RealityKit이 관절 애니메이션을 노출하지 않는다. 수정은 이미 #165의 `b8631f1`에서 완료되어 develop에 포함되어 있었다. 설치 파일은 Desktop의 #147 체크아웃 파일과 일치한다. 설치된 앱 전체 자산도 최신 체크아웃과 비교해 누락/변경 2,611개, 추가 2,405개여서 최신 결과를 실행 중인 상태가 아니었다.

따라서 이번 작업은 정상적인 오류 검사를 제거하거나 임시 대기 모션으로 덮지 않는다. 최신 develop 기반 브랜치에서 별도 DerivedData로 다시 빌드하고, 자산 일치를 검사한 앱을 기존 시뮬레이터에 재설치했다. 앱 삭제나 저장 데이터 초기화는 수행하지 않았다.

## 재발 구분 도구

`verify_bundled_reality.py`는 설치 또는 빌드된 `.app/Reality` 전체 파일을 현재 체크아웃과 SHA-256으로 비교한다. 누락·변경·추가 파일이 있으면 종료 코드 1, 정확히 일치하면 0을 반환한다. 앱·저장 파일·캐시를 수정하지 않으며 별도 Python 패키지가 필요 없다.

```sh
python3 docs/reality-assets/verify_bundled_reality.py /path/DescentAuthorized.app --report /tmp/reality-bundle-report.json
```

빌드할 프로젝트는 이번 브랜치가 체크아웃된 `c5-final-assets/DescentAuthorized.xcodeproj`다. 이전 Desktop 폴더의 #147 프로젝트를 다시 빌드하면 구형 자산이 다시 설치될 수 있다. 해당 폴더는 사용자의 작업 보존을 위해 임의 전환하지 않았다.

## 확인 결과

- 새 Debug 시뮬레이터 빌드 성공.
- Reality 자산 2,911개 일치, 누락/변경/추가 0.
- 9층 높음·보통·낮음에서 캐릭터 표시 및 5개 관절 변화 확인.
- 8층 잔류체·관리자 높은 품질에서 관절 변화 확인.
- 위 5건 모두 소멸 opacity 0, 재도전 opacity 1, 일시정지 유지 확인.
- 9층 높은 품질 실제 화면에서 로딩 오류가 사라지고 캐릭터가 표시됨.
- 런타임 게임 규칙이나 모델 가중치를 이번 브랜치에서 새로 변경하지 않았다.
- 실기기 검증은 수행하지 않았다.

검증 데이터: `skeletal-animation-loading-167.json`.
