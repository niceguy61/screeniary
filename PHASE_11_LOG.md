# Phase 11 - 완료 로그 (2026-10-14)

## 요구 → 구현
- 버전별 변경 이력: `CHANGELOG.md` (0.1.0~0.5.6, 포터블 zip 동봉)
- 피드백 구글폼: 앱 설정 맨 아래 "피드백 보내기" 버튼 + URL 상수 자리 마련
  - 링크 수령 후 `feedbackFormUrl`에 한 줄 넣고 리빌드하면 즉시開通

## 파일
- `CHANGELOG.md` (new, zip 동봉)
- `lib/settings.dart`: `feedbackFormUrl` 상수 (현재 빈값)
- `lib/settings_page.dart`: 피드백 섹션 (빈값이면 "준비 중" 안내, 있으면 기본 브라우저로 열기)
- `packaging/README-INSTALL.md`: 변경이력·피드백 안내로 갱신

## 테스트 해프닝 (기록용)
- 위젯 테스트에서 path_provider 호출이 영원히 미완료: 구형과 달리 path_provider_windows가 FFI 직접 호출이라 mock 채널도 안 먹히는 줄 알았으나, 진짜 원인은 둘:
  1. `tester.pump()`는 가짜 시간이라 실제 IO/FFI가 안 돔 → `runAsync` + 폴링으로 해결
  2. TextField마다 내부 Scrollable이 있어 `scrollUntilVisible` 기본 조회가 "Too many" → ListView 내부 첫 Scrollable 지정
- 교훈: 실제 비동기 거는 위젯 테스트는 runAsync 패턴 사용

## 검증
- analyze 깨끗, 37/37 통과 (feedback 1 포함)
- 클린 풀빌드 exe: mtime 18:47:45(빌드 18:47:50) + 해시 변경 확인
- exe 해시: F7C8D2DE4D8C8FC64A4424AE07364353FEE224DC11C1D22CA550524B5F6C6ABF
- `VTT-Portable-0.5.6.zip` (13.8MB) 실행 확인. 구버전 zip 삭제
