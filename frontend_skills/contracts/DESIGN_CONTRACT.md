# Design Contract (공통: Web + Flutter)

목표: UI를 '개인 취향'이 아니라 **팀 표준**으로 만들고, Codex가 항상 그 표준 안에서만 작업하게 한다.

## 0) 원칙
- **기능 변경 금지**: UI/UX 품질 개선은 하되 비즈니스 로직/동작은 바꾸지 않는다.
- **토큰 우선**: 임의 숫자/색을 만들지 말고 토큰/변수/상수로 수렴한다.
- **컴포넌트 우선**: 버튼/입력/카드/모달/토스트는 단일 소스로 통일한다.

## 1) Spacing / Layout
- 기준: **8pt grid** (4/8/12/16/24/32 …)를 기본 단위로 사용
- 섹션 max-width를 설정하고(웹: 960~1200px 권장) 좌우 여백을 일관되게 유지
- 정렬 규칙: 제목/본문/CTA 정렬을 통일(왼쪽 정렬 기본, 필요한 경우만 센터)

## 2) Typography
- 계층: H1/H2/H3/body/caption 최소 5단 구성
- 줄간격(line-height)과 굵기(weight)는 계층별로 고정
- 긴 텍스트는 line-clamp/ellipsis 규칙을 명시

## 3) Color / Theme
- 색은 **토큰만 사용** (예: primary/surface/text/muted/danger)
- 상태 색: success/warn/danger/info를 토큰으로
- 대비(contrast) 충족(특히 본문 텍스트)

## 4) Components (단일 소스)
- Button: variants(primary/secondary/ghost/destructive) + sizes(sm/md/lg)
- Input: label/helper/error/disabled/focus
- Modal/Sheet: focus trap + ESC close + overlay click 정책 통일
- Toast: 성공/실패/정보 메시지 톤 통일

## 5) States (필수)
- 모든 데이터 의존 UI는 아래 상태를 갖는다:
  - loading (skeleton 또는 spinner)
  - empty (설명 + CTA)
  - error (원인 설명 + retry)
  - disabled (이유 설명 가능)

## 6) Accessibility
- 키보드 탐색 가능(탭/시프트탭)
- focus ring 명확
- aria-label/role 필요 요소에 추가
- 폼 에러는 스크린리더가 읽을 수 있게 연결

## 7) Microcopy
- 버튼은 동사로 시작(예: "저장", "추가", "다시 시도")
- 에러는 "무엇이/왜/어떻게"를 최소로 포함
- 한국어 톤 통일(존댓말/반말 한쪽으로)
