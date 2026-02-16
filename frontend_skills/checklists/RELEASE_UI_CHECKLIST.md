# Release UI Checklist

## 1) Design Contract
- [ ] `contracts/DESIGN_CONTRACT.md` 기준으로 spacing/typography/color/컴포넌트 점검 완료
- [ ] 임의 값 대신 토큰/변수/상수 사용
- [ ] 기능/비즈니스 로직 변경 없음

## 2) State Coverage
- [ ] loading 상태 UI 존재
- [ ] empty 상태 UI + CTA 존재
- [ ] error 상태 UI + retry 존재
- [ ] disabled 상태 + 이유 설명 존재

## 3) Accessibility
- [ ] 키보드 탐색 가능(tab/shift+tab)
- [ ] focus ring 명확
- [ ] aria-label/role 또는 Semantics 적절히 적용
- [ ] 폼 에러가 스크린리더에서 읽힘

## 4) Copy Quality
- [ ] 버튼 문구가 동사로 시작
- [ ] 에러 문구가 원인/대응 포함
- [ ] 한국어 톤 일관

## 5) Platform Pass
- [ ] 웹: `prompts/WEB_NEXTJS_SHADCN_PASS.md` 적용
- [ ] Flutter: `prompts/FLUTTER_UI_PASS.md` 적용
- [ ] 공통: `prompts/UI_POLISH_PASS.md` + `prompts/STATE_COVERAGE_PASS.md` 적용
