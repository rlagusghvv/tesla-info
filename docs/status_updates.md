# Status Updates (Internal)

> 목적: 텔레그램 메시지 중복을 막기 위해, 모든 봇/작업자는 진행상황을 이 파일에만 기록합니다.
> 사용자에게 전달되는 최종 요약은 팀장(youngsam)이 이 파일을 읽고 정리합니다.

## 규칙
- 새 업데이트는 **항상 맨 위**에 추가 (최신이 위)
- 한 업데이트는 5~12줄 내로 간결하게
- 형식:
  - 날짜/시간(KST)
  - 담당(봇/이름)
  - 변경점(무엇을)
  - 영향/테스트(어디에 영향)
  - 다음 액션(무엇을 할지)

---

## 2026-02-12

### 13:46 KST — ops
- TestFlight 업로드: Build 22 (processing)
- 변경: Navi 풀스크린(탭 시 크롬 표시 후 자동 숨김), 오버레이 크기 버튼(-/+ S/M/L), HUD 관련 UX 조정
- 변경: FleetStatus UI 프리즈 완화(디버그 출력 축소/timeout)
- 남은: FleetStatus 실패 원인(HTTP/timeout/unauthorized) 진단 강화, HUD 자동숨김 12~15초 + 인터랙션 시 타이머 리셋, Turn-by-turn 고도화

### 13:35 KST — ops
- TestFlight 업로드: Build 20 (processing)
- 변경: HUD 토글/미디어 오버레이 지속(WKWebView 공유), 핀치 리사이즈, LaunchScreen 로고 추가
- 변경: 카카오 검색 결과 1차 재랭킹(역/카테고리 가중)
- 남은: 차량 커맨드(락/언락) 원인 확정(Fleet VCP/키 페어링/권한), Turn-by-turn 고도화
