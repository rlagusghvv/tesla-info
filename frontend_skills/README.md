# frontend_skills (Codex/Claude Code 공용)

이 폴더는 **UI 결과물 퀄리티를 올리는 '스킬(규칙/프롬프트/체크리스트)'** 모음입니다.

- 도구 종속 없음: Codex CLI / Claude Code / Cursor / ChatGPT 등 어디서든 그대로 사용
- 목적: **일관성(Design Contract) + 완성도(Polish Pass) + 상태/접근성**

## 사용법(권장 루틴)
1) 새 UI 만들기 전: `contracts/DESIGN_CONTRACT.md`를 컨텍스트로 로드
2) 구현 후: `prompts/UI_POLISH_PASS.md` 프롬프트로 2차 리팩토링
3) 릴리즈 전: `checklists/RELEASE_UI_CHECKLIST.md`로 누락 점검

## 파일 목록
- contracts/DESIGN_CONTRACT.md
- prompts/UI_POLISH_PASS.md
- prompts/STATE_COVERAGE_PASS.md
- prompts/WEB_NEXTJS_SHADCN_PASS.md
- prompts/FLUTTER_UI_PASS.md
- checklists/RELEASE_UI_CHECKLIST.md
