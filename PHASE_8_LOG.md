# Phase 8 - 완료 로그 (2026-10-14)

## 요구 → 구현
- 멀티모니터 화면 선택 캡처. 설정-캡처 화면에서 체크한 화면만 기록
- 현재 연결된 화면만 목록에 표시. 캡처 중 추가된 화면은 포함 안 됨 (매 틱마다 열거한 목록과 저장된 이름만 매칭)
- 저장된 선택과 일치하는 화면이 하나도 없으면(선 뽑힘 등) 전체를 찍지 않고 주 화면만 캡처 + 상태 표시 (프라이버시 안전 폴백)

## 파일
- `lib/monitors.dart` (new): `EnumDisplayMonitors`+`GetMonitorInfo` FFI 열거, `resolveRegion()` 순수 함수
- `lib/screen_gdi.dart`: `captureRegionPng()` 추가 (기존 전체캡처는 래퍼로 유지)
- `lib/settings.dart`: `selectedMonitors` (빈값=전체) 저장
- `lib/capture_service.dart`: 매 틱 영역 계산 + 상태 `scopeText` (전체/선택 n개/주 화면만)
- `lib/settings_page.dart`: 캡처 화면 체크박스 섹션 (전체 체크=전체 녹화 정규화)
- `lib/main.dart`: 상태카드에 범위 표시

## 검증
- `flutter analyze`: No issues
- `flutter test`: 29/29 (monitors 6: 영역계산 3 + 실제 듀얼모니터 열거/영역캡처/설정유지)
- 릴리즈 빌드 + 포터블 실행 스모크 통과
- `VTT-Portable-0.5.0.zip` (13.7MB). 구버전 zip 삭제

## 수동 테스트 순서
1. 설정 → 캡처 화면 → 듀얼 2개가 `\\.\DISPLAY1/2 + 해상도 + (주)`로 보이는지
2. 서브 모니터만 체크 해제 → 저장 → "지금 캡처" → 미리보기가 주 화면만인지 + 상태 "선택 화면 1/2개"인지
3. (선택) 서브 모니터 케이블 뽑고 캡처 → "주 화면만 (선택 불일치)" 뜨는지
