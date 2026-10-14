# Phase 16 - 완료 로그 (2026-10-15)

## 요구 (UX 리뷰 P0) → 구현
1. **트레이 상주 + 자동시작** (`tray_manager` 0.5.x-compat + `launch_at_startup`)
   - X 닫기 → 트레이로 숨김. 실제 종료는 트레이 메뉴 → 종료
   - 트레이 메뉴: 열기 / 녹화 시작·정지(상태 반영) / 종료. 좌클릭 토글
   - 설정-일반에서 Windows 시작 시 실행 on/off
   - 트레이 초기화 실패 시 prevent-close를 걸지 않아 창이 정상 동작 (폴백)
2. **첫 실행 안내**: 타임라인 상단 시작 카드 (LLM 선택→연결 테스트→녹화) + 다시 보지 않기
3. **통합 검색**: 캡처 제목·캡션·일기 LIKE 검색 (2자 이상, 디바운스, 특수문자 이스케이프)

## 파일
- `lib/tray_service.dart` (new), `lib/search_page.dart` (new)
- `lib/db.dart`: searchEntries/searchDiaries (+On 정적 분리)
- `lib/settings.dart`: onboarded 플래그, `appVersion` 0.6.0
- `lib/main.dart`: 검색 액션, 온보딩 카드, 트레이 생명주기, 타이틀
- `lib/settings_page.dart`: 일반 섹션 (자동시작)
- `assets/tray_icon.ico` (러너 아이콘 재사용)
- `test/search_test.dart` (검색 3 + onboarded 1)

## 검증
- analyze 깨끗, 48/48 통과
- 클린 풀빌드 (exe mtime == 빌드 시각) + `VTT-Portable-0.6.0.zip` (14.5MB) 실행 확인
- GitHub Release v0.6.0 발행, 푸시 완료
