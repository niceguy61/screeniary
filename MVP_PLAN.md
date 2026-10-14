# VTT (Visual Time Travel) - MVP Plan

> 목표: 크롬 작업 화면 기반 자동 일기. 실시간 Vision API 무한호출 없이 RTX 3060 12GB 로컬로 돈 안 들고 돌리기.

## 원칙
1. 매 Phase마다 윈도우에서 실행/확인 가능한 빌드물을 남긴다.
2. 녹화(X) → 이벤트 캡처 + OCR + URL 로그(O).
3. VLM은 상시 호출 금지. 변화 있을 때만 `Qwen2.5-VL 3B`, 요약은 하루 1회 `Qwen3 8B`.
4. 모든 데이터 로컬 저장 (SQLite). 클라우드 전송 없음.

## 스택 (확정)
- UI: Flutter Windows (tray + timeline)
- 캡처: Flutter `screen_capturer` (MVP) → 추후 DXGI event-driven
- DB: SQLite (`drift`)
- AI: Ollama 외장 연동 `http://127.0.0.1:11434`
  - 캡션: `qwen2.5vl:3b` (~2-4GB)
  - 요약: `qwen3:8b` (이미 설치됨, 5.2GB)
- 패키징: Inno Setup (Phase 4)

## VRAM 예산 (12GB 중 실사용 ~11GB)
- 상시: OCR(CPU) + `qwen2.5vl:3b`만 GPU (~4.4GB). 나머지 비워둠.
- 배치: VLM 내리고 `qwen3:8b`(~6.5GB) 올려서 요약. 동시 적재 금지.

## Phase
### Phase 0 - 환경체크 [현재]
- 확인: `nvidia-smi` 12288MiB OK, `ollama list`에 qwen3:8b OK
- 미달: Flutter SDK 없음, `qwen2.5vl:3b` 없음
- Done 조건: `flutter doctor`, `ollama run qwen2.5vl:3b` 응답 확인
- 빌드물: 없음 (체크로그만)

### Phase 1 - Flutter 윈도우 쉘 + 타임라인 목업
- `flutter create vtt_app --platforms=windows`
- 트레이 상주 + “오늘 타임라인” 빈 UI (mock 데이터)
- Done 조건: `flutter run -d windows` 실행 + `flutter build windows`로 `build\windows\x64\runner\Release\vtt_app.exe` 생성, 더블클릭 실행 확인
- 빌드물: Release exe

### Phase 2 - 캡처 + SQLite 로그 (AI 없이)
- 10초 간격 스크린샷 + pHash 중복제거 + active window 제목 + SQLite 저장
- 타임라인에 실제 캡처 리스트 표시
- Done 조건: 10분 돌려서 DB에 20~60 row, 재실행해도 유지, 타임라인에 썸네일 표시
- 빌드물: Release exe + `timeline.db` 샘플

### Phase 3 - Ollama 연동 (캡션 + 일기요약)
- 변화 프레임만 `qwen2.5vl:3b` 한줄 캡션 → DB 저장
- “오늘 일기 생성” 버튼 → `qwen3:8b`로 3줄 요약 + 하이라이트
- Done 조건: 캡션 10개 생성, 일기 1개 생성, VRAM 피크 기록
- 빌드물: Release exe (Ollama 필요 안내 포함)

### Phase 4 - 패키징
- Inno Setup 인스톨러 + 첫 실행 모델 자동 `ollama pull`
- Done 조건: 새 폴더에 설치 → 실행 → 타임라인 → 일기까지 무외장 동작
- 빌드물: `VTT-Setup-0.1.0.exe`

## 다음 액션
1. Flutter SDK 설치 (winget)
2. `ollama pull qwen2.5vl:3b`
3. Phase 1 scaffold
