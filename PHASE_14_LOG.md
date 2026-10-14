# Phase 14 - 완료 로그 (2026-10-14)

## 요구 → 구현
- 피드백 구글폼 URL을 앱에 연결. 설정 맨 아래 "피드백 보내기" → 기본 브라우저로 폼 열기
- `feedbackFormUrl` 상수에 수령한 링크 고정

## 파일
- `lib/settings.dart`: 폼 URL 상수
- `lib/main.dart`: 타이틀 0.5.9
- `CHANGELOG.md`: 0.5.9 항목
- `test/feedback_test.dart`: 버튼 존재 + URL 설정됨 검증 (탭은 실제 브라우저가 뜨므로 제외)

## 검증
- analyze 깨끗, 39/39 통과
- 클린 풀빌드 (exe mtime 19:12:12 == 빌드 19:12:13) + `VTT-Portable-0.5.9.zip` 실행 확인
