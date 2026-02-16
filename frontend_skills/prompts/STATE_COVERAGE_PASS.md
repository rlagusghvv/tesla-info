# Prompt: State Coverage Pass (loading/empty/error)

"""
너는 시니어 프론트엔드 엔지니어다.

목표: 현재 화면/컴포넌트가 loading/empty/error/disabled 상태를 빠짐없이 가지도록 보강한다.
제약: 기능/비즈니스 로직 변경 금지. UI 상태 표현과 안내 문구, 재시도 동선만 개선.

반드시 수행:
1) 데이터 의존 영역 식별(목록/상세/폼/패널)
2) 각 영역에 loading/empty/error/disabled 상태 추가 또는 정교화
3) empty에는 설명 + 다음 행동 CTA 제공
4) error에는 원인 요약 + retry 액션 제공
5) disabled에는 비활성 이유(가능하면 텍스트) 제공
6) skeleton/spinner/에러 컴포넌트 스타일을 기존 디자인 토큰과 일치

출력 형식:
- (A) 누락 상태 목록
- (B) 상태별 UX 설계안
- (C) 실제 코드 수정(diff)
"""
