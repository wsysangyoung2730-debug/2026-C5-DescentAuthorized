# #203 두루마리 수령 모션 한 번

## 변경 내용

- resolving에서만 수령 이동을 재생한다.
- resolved는 선택된 두루마리의 최종 위치를 정적으로 유지하고 나머지는 숨긴다. 상태 재전달/복원 시 수령을 다시 시작하지 않는다.

## 검증

`issue-203-scenes.json`: 9·8·5층 실제 장치에서 resolving→resolved→동일 resolved 재적용 및 0.5초 뒤 상태 확인.

completionDoesNotReplay, completionKeepsSelectedPose, restorationDoesNotReplay, discardedRewardsHidden 모두 true. 최종 변환 차이는 2.38e-7~4.77e-7로 부동소수점 정규화 오차 범위이며 1e-4 허용 범위 안이다. 장치 출현 및 동작 줄이기 완료도 확인했다.

## 공통 검증 환경과 제한

2026-10-01, #200 원격 최신 2eadd12에서 이어받은 #201~#207 누적 코드. iPad Pro 13 M5 / iOS 26.5 Simulator, medium 그래픽. 핵심 테스트 235개 통과 및 누적 Debug 빌드 성공. 중간 브랜치 각각의 독립 앱 빌드/실기기 전체 진행을 수행했다는 의미는 아니다. 실제 지원 iPad의 메모리·발열·입력 성능은 별도 확인이 필요하다.
