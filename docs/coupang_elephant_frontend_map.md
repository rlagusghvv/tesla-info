# Coupang Elephant Frontend Map (어디가 프론트인가?)

## TL;DR
현재 “프론트”는 2개 계열이 공존합니다.
1) **신규 디자인(Next.js, 3333)**: `tesla-info/_repo/coupang-elephant/`
2) **기존 기능(Express 정적+Flutter/Web 번들, 3000)**: `coupang-automation/` 레포의 `public/`

우리가 원하는 방향: `https://app.splui.com/app/`에서 **신규 디자인(Next.js)** 를 메인으로 쓰되,
기존 기능(API/콘솔/업로드/추천 등)은 당장은 프록시/임베드로 붙이고, 점진적으로 Next UI로 이식.

---

## 1) 신규 디자인 (Next.js)
- 위치: `/Users/kimhyunhomacmini/tesla-info/_repo/coupang-elephant/`
- 실행(개발): `npm run dev -- --port 3333 --hostname 0.0.0.0`
- 외부 도메인: `https://app.splui.com/app/` (Cloudflare tunnel → localhost:3333)
- 핵심 설정:
  - `coupang-elephant/next.config.ts`
    - `basePath: "/app"`
    - rewrites로 `/api/*`, `/console/*` 등을 **basePath 없이** 기존 서버(3000)로 프록시

## 2) 기존 기능 UI (Express static + console.html)
- 위치: `/Users/kimhyunhomacmini/.openclaw/workspace/coupang-automation/public/`
  - `public/console.html` : 기존 콘솔(업로드/추천/큐/설정 등)
  - `public/app/` : Flutter Web 번들(레거시)
- 실행: launchd `com.splui.coupelephant-server` → `node server.js` (port 3000)
- 외부 도메인: `https://app.splui.com/` (Cloudflare tunnel → localhost:3333로 바뀌었음)
  - 단, Next가 `/api/*`를 3000으로 프록시하므로 기능은 유지됨.

## 3) 지금 사용자(현호님)가 보는 URL
- 메인: `https://app.splui.com/app/` → Next 랜딩/새 디자인
- 기능(콘솔): `https://app.splui.com/app/console` → Next UI 안에 레거시 콘솔(`/console`) iframe 임베드

## 이식 우선순위(제안)
1) /recommend(추천 리스트 + 멀티선택 업로드)부터 Next로 네이티브 구현
2) /upload (URL 입력 → preview → 큐) Next로 구현
3) 설정/프리셋/히스토리 순으로 이식

