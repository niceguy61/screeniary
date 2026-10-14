# Phase 5 - 완료 로그 (2026-10-14)

## 요구 → 구현
1. 요청시 일기 만들기 → 기존 버튼 유지 + 일기 기록(히스토리) 페이지 추가 (`DiaryPage`, 상단 책 아이콘)
2. 기본 시간 지정하기 → 설정에서 자동 일기 on/off + 시간 선택. 30초 스케줄러가 시간 되면 1회 자동 생성 (앱 실행 중에만 동작, 명시)
3. UI/UX 강화 → 상단바에 일기/설정 진입, 설정 페이지 섹션화, 연결 테스트 결과 인라인 표시, 썸네일 미리보기 유지
4. LLM 설정 → 제공자별 캡션/일기 모델명 변경 가능
5. Ollama 외 키 연결 → OpenAI / OpenRouter(OpenAI 호환) / Anthropic Claude / AWS Bedrock(Converse+SigV4 직접 서명)

## 파일
- `lib/settings.dart` (new): 제공자 5종 + JSON 저장(`settings.json`, 손상시 기본값)
- `lib/llm.dart` (new): 통합 `LlmClient` + 순수 빌더/파서 (테스트 가능) + Bedrock SigV4
- `lib/settings_page.dart` (new): 제공자 드롭다운 + 동적 필드 + 연결 테스트 + 캡처간격 + 자동일기
- `lib/diary_page.dart` (new): 일기 목록 + 상세 보기
- `lib/ollama.dart`: http.Client 주입 가능하게 변경 (테스트/Mock용)
- `lib/capture_service.dart`: `LlmClient`+설정 기반 캡션, 간격 설정 반영, `reloadSettings()`
- `lib/db.dart`: `diaries()` 목록 조회 추가
- `lib/main.dart`: 30초 자동일기 스케줄러, 상단바 내비게이션

## 보안 메모
- 키는 `%APPDATA%/com.vtt/vtt_app/settings.json` 평문 저장 (MVP). 다음 단계에서 Windows Credential Manager 또는 DPAPI 암호화 권장
- Bedrock은 AK/SK 직접 서명, 토스큰(세션) 미지원 (필요시 추가)

## 검증
- `flutter analyze`: No issues
- `flutter test`: 17/17 (settings 3, llm mock 7, pipeline 3+db, widget 1, ollama 실모델 3)
- 릴리즈 빌드 + 포터블 실행 스모크 통과
- `VTT-Portable-0.2.0.zip` (13.6MB) 재생성, 압축풀기→실행 검증済

## 수동 테스트 순서
1. exe 실행 → 우상단 톱니 → Ollama 선택 → 연결 테스트 → "성공" 확인 → 저장
2. OpenAI/Claude 키 있으면 제공자 바꿔 테스트 (과금 주의: 캡션 1건당 vision 1회)
3. 자동 일기 켜고 시간을 1분 뒤로 → 가만히 두면 일기 다이얼로그 뜨는지
4. 책 아이콘 → 지난 일기 목록/상세 확인
