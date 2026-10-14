# Phase 6 - 완료 로그 (2026-10-14)

## 요구 → 구현
1. 현대적 UI + 다크테마 → Material3 light/dark 테마, 설정-화면에서 전환 (시스템/라이트/다크). 상태바→카드, 타임라인 행→카드
2. 일기 몰아보기 → 일기 기록 페이지에 몰아보기 버튼 (`DigestPage`: 전체 일기를 날짜 카드로 한 화면에)
3. 오래된 캡처 자동삭제 → 보관기간 설정 (7/15/30/90일/무기한, 기본 30일)
   - PNG 파일만 삭제, DB 메타행·일기는 유지 (썸네일은 플레이스홀더로 표시)
   - 시작시 + 6시간마다 자동 실행, 설정에서 용량 확인 + "지금 정리" 수동 실행

## 파일
- `lib/settings.dart`: `themeMode`, `shotRetentionDays` 추가 (+parseTheme)
- `lib/retention.dart` (new): `pruneShots()` (기간 지난 파일+고아 파일 삭제) + `shotsSize()` + `formatBytes()`
- `lib/digest_page.dart` (new): 일기 몰아보기
- `lib/main.dart`: VttApp 테마 상태화, 카드 UI, 시작시/주기적 prune
- `lib/settings_page.dart`: 화면 섹션(테마/보관기간) + 저장 공간 섹션(용량/지금 정리)
- `lib/diary_page.dart`: 몰아보기 진입 버튼

## 검증
- `flutter analyze`: No issues
- `flutter test`: 19/19 (기존 14 + retention 5: 오래된것만 삭제/무기한/용량/설정유지/최신순)
- 릴리즈 빌드 + 포터블 실행 스모크 통과
- `VTT-Portable-0.3.0.zip` (13.6MB). 구버전 zip(0.1.0/0.2.0) 삭제

## 수동 테스트 순서
1. 설정 → 다크 선택 → 저장 → 즉시 다크테마 적용되는지
2. 보관기간 7일 → 저장 공간 → "오래된 캡처 지금 정리" → 스낵바 메시지 확인
3. 일기 2개 이상 있는 상태에서 책 아이콘 → 몰아보기 → 전체가 한 화면에 보이는지
