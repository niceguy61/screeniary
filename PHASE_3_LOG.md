# Phase 3 - 완료 로그 (2026-10-14)

## 한 일
- `lib/ollama.dart`: localhost Ollama 최소 클라이언트 (tags/generate, stream:false)
  - 캡션: `qwen2.5vl:3b`, 한줄 한국어 프롬프트
  - 일기: `qwen3:8b`, 3줄 요약 + 불릿 프롬프트
- `lib/db.dart` → 스키마 v2: `diary(day, content, created_at)` 테이블 추가
  - 기존 v1 DB는 `onUpgrade`로 diary 테이블만 생성 (entries 보존됨)
  - `updateCaption / uncapped / todayRows / saveDiary / getDiary` 추가
- `lib/capture_service.dart`: 저장 직후 캡션 single-flight (바쁘면 스킵, 다음 틱 블로킹 없음)
  - Ollama 미연결이면 캡션 없이 캡처만 저장 + 상태바 경고
  - `fillMissingCaptions()`: 비어있는 캡션 최대 20건 보충
- `lib/main.dart`: "빈 캡션 채우기" + "오늘 일기 생성" 버튼, 일기 다이얼로그, 캡션 카운터
- `test/ollama_test.dart`: 실모델 통합 테스트

## VRAM 정책 (지킴)
- 캡션(3B)과 일기(8B)는 절대 동시 호출 안 됨. 캡션 single-flight + 일기 버튼은 수동
- Ollama 서버가 모델 스왑 처리. 동시 적재 금지

## 검증
- `flutter analyze`: No issues
- `flutter test`: 7/7 통과
  - 해시/DB/GDI/위젯 4건 + ollama 3건 (모델 확인, VLM 캡션 ~14초, 8B 응답 ~13초)
- `flutter build windows --release`: 성공, 실행 스모크 통과 (기존 DB 마이그레이션 포함)

## 빌드물 (직접 테스트)
- `D:\idea_bank\vtt_app\build\windows\x64\runner\Release\vtt_app.exe`
- 테스트 순서:
  1. Ollama 실행 확인 (이미 켜져 있음)
  2. exe 실행 → "지금 캡처" → 10~20초 뒤 해당 행에 한줄 캡션 붙는지 확인
  3. 몇 건 쌓은 뒤 "오늘 일기 생성" → 1~2분 뒤 일기 다이얼로그 확인
  4. Ollama 끄고 캡처 → 캡션 없이 저장 + 상태바 경고 확인 (복원력)

## 다음 (Phase 4)
- Inno Setup 인스톨러 + 첫 실행 `ollama pull` 자동화
- `D:\flutter-sdk.zip`(1.8GB) 정리 (설치 완료 후 불필요)
