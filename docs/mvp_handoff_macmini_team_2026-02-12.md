# TeslaSubDash MVP Handoff (Mac mini Team)

Last updated: 2026-02-12  
Repo: `rlagusghvv/tesla-info`  
Branch: `main`  
Latest checkpoint commit: `5be988b`

## 1) MVP 목표 대비 현재 상태

### 목표 A: iPad 차량 보조 대시보드 (지도/미디어 중심 UI)
- 상태: `완료 (MVP 수준)`
- 구현:
  - Car Mode 3탭: `Map / Navi / Media`
  - 우측 패널: 차량 상태 + 명령 버튼 (밀도 축소, 중앙 콘텐츠 영역 확대)
  - Account 시트 열릴 때 지도/폴링 일시 중지로 프리즈 완화
- 관련 파일:
  - `Sources/Features/CarMode/CarModeView.swift`
  - `Sources/Features/CarMode/CarModeViewModel.swift`
  - `Sources/Features/Navi/KakaoNavigationPaneView.swift`

### 목표 B: 차량 데이터 수집 + 제어 (Lock/Unlock/Climate/Wake)
- 상태: `부분 완료`
- 구현:
  - Backend 모드 연동 (`/api/vehicle/latest`, `/api/vehicle/command`)
  - Fleet direct + TeslaMate fallback 두 경로 지원
  - Backend API 토큰 헤더 지원 (`Authorization`, `X-Api-Key`)
- 관련 파일:
  - `Sources/Telemetry/TelemetryService.swift`
  - `Sources/Features/Shared/AppConfig.swift`
  - `backend/server.mjs`
  - `backend/teslamate_client.mjs`

### 목표 C: 인앱 내비게이션 (카카오)
- 상태: `완료 (MVP)`
- 구현:
  - Kakao REST 키로 장소 검색 + 경로 API
  - Kakao JS 키가 있으면 웹뷰 카카오맵 렌더링
  - JS 키 없으면 Apple Map fallback
- 관련 파일:
  - `Sources/Kakao/KakaoAPIClient.swift`
  - `Sources/Kakao/KakaoConfigStore.swift`
  - `Sources/Features/Navi/KakaoWebRouteMapView.swift`
  - `Sources/Features/Navi/KakaoRouteMapView.swift`

### 목표 D: 연결/로그인 UX 간소화
- 상태: `완료 (MVP)`
- 구현:
  - Connection Guide에서 backend URL, backend token, Kakao 키, Fleet 계정 설정 가능
  - Start Car Mode App Intent/Shortcut 제공
  - 딥링크 및 수동 코드 교환 경로 지원
- 관련 파일:
  - `Sources/Features/Connection/ConnectionGuideView.swift`
  - `Sources/Intents/StartCarModeIntent.swift`
  - `Sources/Tesla/TeslaAuthStore.swift`

## 2) 현재 핵심 이슈/리스크

### 이슈 1: Fleet direct 위치 데이터 불안정
- 증상:
  - 리스/법인/DRIVER 권한 계정에서 위치값 누락 가능
  - `Test Snapshot`에서 차량 데이터는 오지만 location nil 발생 케이스 존재
- 판단:
  - 앱 버그라기보다 Tesla 권한/계정 컨텍스트 영향 가능성이 큼

### 이슈 2: TeslaMate 내부 refresh endpoint 불일치
- 증상:
  - TeslaMate refresh가 `.../oauth2/v3/nts/token`으로 가며 404 발생 사례
- 현재 우회:
  - `tesla:oauth:exchange:sync` (교환 + 런타임 sync)
  - `tesla:oauth:refresh:sync` (refresh + 런타임 sync) 추가됨
- 관련 파일:
  - `backend/tesla_oauth_exchange_and_sync.mjs`
  - `backend/tesla_oauth_refresh_and_sync.mjs`
  - `backend/teslamate_token_bridge.mjs`

## 3) Mac mini 팀 운영 런북

## 3.1 기본 업데이트
```bash
cd /Users/kimhyunhomacmini/tesla-info/_repo
git pull origin main
npm install
```

## 3.2 Backend 실행 (TeslaMate 모드)
```bash
npm run backend:start:teslamate:lan
```

헬스체크:
```bash
curl http://127.0.0.1:8787/health
curl http://127.0.0.1:8787/api/vehicle/latest
```

## 3.3 OAuth 토큰 동기화
1) 최초 교환 + sync
```bash
npm run tesla:oauth:exchange:sync -- "<callback_url_or_code>"
```

2) 주기 refresh + sync
```bash
npm run tesla:oauth:refresh:sync
```

권장: 30~60분 간격으로 launchd/cron 등록

## 3.4 iPad 앱 설정
- Telemetry Source: `Backend`
- Backend URL: `https://tesla.splui.com` 또는 LAN URL
- Backend Token: `BACKEND_API_TOKEN` 값 입력
- Navi 키:
  - Kakao REST API Key 필수
  - Kakao JavaScript Key는 지도 렌더 품질 향상용

## 4) 원격 운영 기준 배포 전략 (TestFlight)

맥미니 원격 운영에서는 로컬 케이블 설치보다 TestFlight 기준이 맞음.

### 권장 흐름
1) 개발/핫픽스: 로컬 브랜치 -> `main` PR 머지
2) 릴리스 태그 생성: 예 `v0.2.0-mvp`
3) 맥미니에서 Release 빌드/업로드 자동화 (Fastlane 또는 xcodebuild + App Store Connect API Key)
4) TestFlight Internal 그룹에 자동 배포
5) iPad 실차 검증 후 External 배포 여부 결정

### 팀 TODO (아직 미구현)
- `fastlane/` 파이프라인 추가:
  - `beta` lane (build + upload + changelog)
- App Store Connect API Key 기반 비대화형 업로드 정착
- 릴리스 노트 템플릿 및 rollback 절차 문서화

## 5) OpenClaw 팀에 바로 넘길 작업 목록

1) 운영 안정화
- `tesla:oauth:refresh:sync`를 launchd로 주기 실행
- 실패 알림(로그/Slack) 연결

2) 앱 안정화
- iPad 장시간 사용(30~60분) 시 프리즈 재현 테스트 자동화
- Account 시트/키보드/탭 전환 스트레스 테스트

3) 배포 자동화
- TestFlight CI/CD 구축 (Fastlane 권장)
- 빌드 번호 자동 증가 및 릴리스 노트 자동 생성

4) 데이터 경로 정책
- Fleet direct vs TeslaMate fallback 자동 전환 기준 정의
- DRIVER 권한 계정에서 location nil일 때 UX 메시지 표준화

## 6) 참고 문서
- `README.md`
- `current_progress.md`
- `docs/architecture_notes.md`
- `POLICY_AND_UX_REPORT.md`
