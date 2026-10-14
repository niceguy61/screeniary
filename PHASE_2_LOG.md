# Phase 2 - 완료 로그 (2026-10-14)

## 한 일
- 10초 간격 화면 캡처 + aHash 중복제거 + SQLite 저장 파이프라인 구현
  - `lib/screen_gdi.dart`: GDI(FFI) 전체화면 캡처 → PNG 저장. 네이티브 플러그인 불필요
  - `lib/hash.dart`: 8x8 average-hash + Hamming 거리 (역치 3 이하 = 중복, 파일 삭제)
  - `lib/db.dart`: `sqflite_common_ffi` 로컬 DB (`timeline.db`, 테이블 `entries`)
  - `lib/capture_service.dart`: 캡처 루프 + Win32 포그라운드 창 제목 수집
  - `lib/main.dart`: 실제 타임라인 UI (썸네일 + 제목 + 시간 + 캡처 시작/중지/지금캡처 버튼)
- `test/pipeline_test.dart`: 해시/DH roundtrip/실제 GDI 캡처 테스트

## 우회 기록 (중요)
- `screen_capturer` 플러그인이 `atlimage.h`를 요구 → VS Build Tools에 ATL 없음
- `vs_installer modify +ATL` 2회 시도했으나 반영 안 됨 (권한 문제 추정)
- → 플러그인 제거(`flutter pub remove screen_capturer`), Dart FFI GDI 직접 캡처로 전환
- 결과: 네이티브 컴파일 의존성 0개, 빌드 31초로 단축

## 검증
- `flutter analyze`: No issues
- `flutter test`: 4/4 통과 (해시, DB roundtrip, 실제 화면캡처 PNG 디코딩, 위젯 스모크)
- `flutter build windows --release`: 성공
- 런타임 스모크: exe 실행 → `%APPDATA%/com.vtt/vtt_app/timeline.db` 16KB 생성 확인 → 프로세스 정상 종료

## 빌드물 (직접 테스트)
- `D:\idea_bank\vtt_app\build\windows\x64\runner\Release\vtt_app.exe`
- 테스트 순서:
  1. exe 더블클릭
  2. "지금 캡처" 클릭 → 리스트에 현재 화면 썸네일 + 창 제목이 1건 추가되는지 확인
  3. 같은 화면에서 한 번 더 → "중복제거 +1" (DB 총 건수 그대로) 확인
  4. 크롬 탭 바꾸고 캡처 → 새 건 추가 확인
  5. "캡처 시작" → 10초마다 자동 누적 확인

## 다음 (Phase 3)
- 변화 프레임만 `qwen2.5vl:3b`로 한줄 캡션 → DB `caption` 컬럼 업데이트
- "오늘 일기 생성" 버튼 → `qwen3:8b`로 3줄 요약
- VRAM: VLM/LLM 순차 적재 (동시 금지)

## Phase 2d 수정 (유저 피드백 반영)
증상: 자동 10초 캡처가 안 도는 것처럼 보임 + 중복제거라는데 뭘 보고 있는지 모름 (듀얼모니터)
원인 추정:
1. 화면이 가만히 있으면 매 틱이 전부 중복 스킵 → 새 행이 안 생기니 "안 돈다"로 보임. 타이머가 살았는지 보여주는 표시가 없었음
2. 썸네일이 듀얼 풀샷을 96px로 줄인 거라 글자가 안 보임
수정:
- 매 틱마다 `마지막: 저장됨/중복 스킵 HH:mm:ss` 심장박동 표시 (타이머 생존 증명)
- 리스트 행 탭 → 원본 크기 미리보기 다이얼로그
- 저장 전 가로 1600px로 다운스케일 (듀얼 4K PNG 용량/속도 대책, 캡션용에도 충분)
검증: analyze 깨끗, test 4/4, 릴리즈 빌드 + 실행 스모크 통과
