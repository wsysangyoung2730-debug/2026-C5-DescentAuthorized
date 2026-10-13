# 최신 버전 출시 보완 · 2026-10-13

기준: 원격 최신 `main @ 35fe1a1`. 이전 #208 점검 이후 추가된 엔딩과 보스방 카메라까지 포함한다. 지원 URL은 요청에 따라 마지막 제작 항목으로 유보한다.

## #212 개인정보·언어

- `systemUptime`은 게임의 경과 시간과 연출 타이밍 측정에 사용한다. 개인정보 명세에 SystemBootTime / `35F9.1`을 추가했다. UserDefaults / `CA92.1`은 유지한다.
- 한국어로 제공하는 실제 UI에 맞춰 번들 기본 언어와 지원 언어를 `ko`로 선언했다.
- 설정에 기기 저장, Game Center 전송, 보관·삭제·백업 및 문의 이메일을 안내한다. 이메일: 사용자 제공 `sangyoung2730@naver.com`.
- 개인정보처리방침의 공개 URL은 아직 게시하지 않았다. 앱 내부 설명만으로 공개 URL 요구를 완료했다고 판단하지 않는다. 지원 URL과는 별도 출시 전 필수 확인 항목이다.

## 검증과 한계

- 수정 전 코어 테스트 255개 통과.
- 명세와 Xcode 프로젝트 plist 구문 검사 통과.
- 최종 누적 후보에서 Release 빌드·리소스·화면 검증을 수행하고 이 기록에 추가한다.
- 배포 서명, App Store Connect 실제 업적·개인정보 응답, 권리 증빙, 실물 iPad 장시간 성능은 로컬 빌드와 별개다.

## 공식 기준

- [필수 사유 API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [최소 SDK 요구](https://developer.apple.com/news/upcoming-requirements/?id=04282026a): 현재 Xcode 26 및 SDK 26 이상. 검사 환경은 Xcode 27.0 / SDK 27.0.
