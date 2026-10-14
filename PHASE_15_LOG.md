# Phase 15 - 완료 로그 (2026-10-14)

## 요구 → 구현
1. 설정 폼 조밀화: 페이지 패딩 16→12, 섹션 타이틀 15→13, 구분선 32→20, 입력칸 간격 축소
2. 버전 정보 + 업데이트 체크: 설정 맨 아래 "앱 정보" 섹션 (버전 표시, 업데이트 확인, 다운로드 페이지). GitHub latest → 404시 태그 목록 폴백, 버전 비교 순수함수
3. 피드백 버튼 버그: `explorer.exe URL` 호출이 문서 폴더를 여는 문제 → `url_launcher`(ShellExecute 정석)로 교체

## 파일
- `lib/settings.dart`: `appVersion` 상수 (타이틀·설정·체크 단일 소스)
- `lib/update.dart` (new): compareVersions + checkForUpdate (latest→tags 폴백)
- `lib/settings_page.dart`: 조밀화 + 앱 정보 섹션 + launchUrl 적용
- `lib/main.dart`: 타이틀 0.5.11 (상수 참조)
- `test/update_test.dart` (new): 비교 1 + 시나리오 4

## 검증
- analyze 깨끗, 44/44 통과
- 클린 풀빌드 (exe mtime == 빌드 시각) + `VTT-Portable-0.5.11.zip` 실행 확인
- GitHub Release v0.5.10, v0.5.11 발행 (업데이트 체크 실동작용). 익명 API 복제 지연 관측 → 태그 폴백으로 대응
- 푸시 완료
