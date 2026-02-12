# Architecture Notes

## Purpose
This document fixes architecture principles for productization and monetization readiness.
All future implementation and refactoring should conform to these rules.

## Core Principles

1. Separation of Concerns
- `Infrastructure`: external APIs (Tesla, Kakao, etc.), DB, file I/O adapters.
- `Domain`: pure business models/rules, no dependency on external tools.
- `Application`: orchestration layer connecting infrastructure adapters and domain logic.

2. Dependency Inversion
- Do not directly bind app flows to concrete providers.
- Define provider interfaces first (example: `VehicleProvider`) and implement concrete adapters (`FleetVehicleProvider`, `TeslaMateVehicleProvider`).

3. Multi-tenancy by Design
- Every request/session/storage operation must carry `userId`.
- Avoid global mutable singleton session state for user-scoped resources.
- Keep user-specific contexts isolated.

4. Resilience and Observability
- Wrap external API calls with timeout/retry and circuit-breaker style fail-open or fail-fast decisions.
- Emit audit logs for critical actions:
  - auth/token lifecycle
  - vehicle polling
  - command dispatch (lock/unlock/climate/wake)
  - provider switch and fallback behavior

5. Mandatory Self-review Before/After Changes
- Before coding: brief design check against these principles.
- After coding: update this file when architecture changes, and record operational notes in `current_progress.md`.

## Current Mapping (2026-02-11)

- Infrastructure (existing):
  - `backend/server.mjs`
  - `backend/teslamate_client.mjs`
  - `Sources/Tesla/TeslaFleetService.swift`
  - `Sources/Kakao/*`

- Domain (needs stronger extraction):
  - Vehicle snapshot model logic is currently mixed between backend and app layers.

- Application (existing, partial):
  - `Sources/Features/CarMode/CarModeViewModel.swift`
  - backend polling/command routes in `backend/server.mjs`

## Next Refactor Targets

1. Introduce shared provider interface:
- `VehicleProvider` methods:
  - `fetchSnapshot(userId)`
  - `sendCommand(userId, command)`
  - `health(userId)`

2. Add `ProviderContext`:
- includes `userId`, `providerType`, `vehicleIdOrVin`, request trace id.

3. Add audit log utility:
- JSON line log with timestamp, userId, provider, action, result, latency.

4. Add circuit-breaker wrapper for provider calls:
- open/half-open/closed states per provider+user key.


## Update 2026-02-11 (Stability / Setup UX)

- Application-layer resilience update:
  - Paused telemetry polling while account/setup sheet is open (`CarModeView`) to reduce UI contention on iPad mini.
- Infrastructure access UX update:
  - Added backend quick-select and auto-detect flow in `ConnectionGuideView` to lower manual typing friction during unstable sessions.
- Domain-safe performance update:
  - Reduced route polyline point cap (`KakaoAPIClient`) to reduce MapKit rendering load and prevent UI stalls.
- Default runtime mode update:
  - Switched default telemetry source to backend mode in `AppConfig` for more deterministic startup behavior during MVP testing.

## Update 2026-02-11 (Kakao Navi Rendering)

- Infrastructure adapter expansion:
  - Added `Sources/Features/Navi/KakaoWebRouteMapView.swift` as a rendering adapter that bridges SwiftUI and Kakao JS SDK via `WKWebView`.
  - Added Kakao JavaScript key persistence in `Sources/Kakao/KakaoConfigStore.swift`.
- Application layout orchestration update:
  - `KakaoNavigationPaneView` now prioritizes map canvas size and overlays compact search/result panels to maximize driving visibility.
  - `CarModeView` side panel width and control density were reduced to keep center map/media dominant.
- Compatibility strategy:
  - If Kakao JavaScript key is missing, runtime falls back to existing Apple Map renderer (`KakaoRouteMapView`) without breaking route search flow.

## Update 2026-02-11 (Backend API Token Auth)

- Infrastructure security alignment:
  - Added backend token config in `AppConfig` backed by Keychain (`backend.api.token`).
  - Added normalized auth header values for both:
    - `Authorization: Bearer <token>`
    - `X-Api-Key: <token>`
- Application integration:
  - `TelemetryService` now automatically injects backend auth headers for backend mode API calls (`/api/vehicle/latest`, `/api/vehicle/command`).
  - `ConnectionGuideView` adds backend token input/save UI and uses the same headers for backend health probe.
- Operational effect:
  - iPad app can now connect to hardened backend deployments that require token auth on `/api/*` routes.

## Update 2026-02-11 (Direct Fleet Diagnostics / Observability)

- Self-review (before coding):
  - SoC: Fleet 통신/진단은 `TeslaFleetService`(Infrastructure)에서 처리, UI는 진단 표시만 담당.
  - DIP: 기존 provider 구조를 깨지 않고 Fleet adapter 내부 진단만 확장.
  - Multi-tenancy: 사용자 토큰/설정은 기존 Keychain 스코프 유지, 전역 세션 추가 없음.
  - Resilience/Observability: 네트워크 상태/요청 URL/실패 유형 가시성 강화를 우선 적용.
- Infrastructure observability expansion:
  - Added `FleetNetworkProbe` (`NWPathMonitor`) for path snapshots:
    - `status`, `iface`, `ipv4`, `ipv6`, `dns`, `expensive`, `constrained`
  - Every Fleet request now logs:
    - request method + final URL
    - current path summary
- Error taxonomy hardening:
  - `TeslaFleetError.network` now carries `url`, `URLError.Code`, `pathSummary`, and raw detail.
  - UI-visible messages explicitly distinguish:
    - `URLError.timedOut`
    - `URLError.cannotFindHost`
    - `URLError.cannotConnectToHost`
- Config hygiene:
  - `TeslaAuthStore.loadConfig()` now trims whitespace/newline on keychain-loaded values
    (`clientId`, `clientSecret`, `redirectURI`, `audience`, `fleetApiBase`).
- Application-layer diagnostics UX:
  - `ConnectionGuideView` `Test Vehicles` now surfaces:
    - vehicle count
    - final request URL (`/api/1/vehicles`)
    - network path summary

## Update 2026-02-11 (Runtime Stability Hardening)

- Self-review (before coding):
  - SoC: cancellation/transport handling은 service layer, 화면 부담 완화는 feature/viewmodel layer로 분리.
  - DIP: provider 전환 구조(`directFleet` vs `backend`)는 유지하고 adapter 내부 안정성만 보강.
  - Multi-tenancy: 기존 사용자별 Keychain/설정 범위를 변경하지 않음.
  - Resilience/Observability: 취소성 오류 노이즈 제거와 불필요 재요청/재렌더 축소에 집중.
- Infrastructure resilience update:
  - `TelemetryService` / `TeslaFleetService` transport에서 `URLError.cancelled`를 `CancellationError`로 승격.
  - Direct Fleet base URL을 `https + tesla.com`으로 검증해 잘못된 로컬 URL 혼입 시 즉시 명확한 에러 반환.
- Application runtime update:
  - `CarModeViewModel`:
    - snapshot 의미 변화 비교 후 변경 시에만 재할당
    - 취소성 에러 무시
    - 오류 메시지 dedup + 길이 제한
  - `ConnectionGuideView`:
    - backend URL 저장 시 telemetry source를 자동 backend 전환
- Navi rendering update:
  - `KakaoNavigationViewModel.updateVehicle`에 좌표/속도 임계치 적용.
  - `KakaoWebRouteMapView`에 payload signature dedup 적용.
  - WebView 준비 전 payload는 pending 보관 후 `didFinish`에서 단 1회 반영.

## Update 2026-02-11 (Setup Modal Freeze Guard)

- Self-review (before coding):
  - SoC: 모달 표시 중 부하 제어는 `CarModeView` 뷰 계층에서 처리하고, 네트워크 취소/폴링 제어는 service/viewmodel 계층에 유지.
  - DIP: provider 전환 구조에는 손대지 않고 UI 합성 레이어만 조정.
  - Multi-tenancy: 사용자 데이터/세션 스코프 변경 없음.
  - Resilience: 모달 표시 중 무거운 뷰(Map/WebView) 동시 갱신을 피하는 안전 경로를 우선 적용.
- Application composition update:
  - `CarModeView`에서 setup sheet가 열릴 때 center/side 패널을 lightweight placeholder로 전환.
  - 목적: 계정 모달 입력 중 백그라운드 뷰 재렌더 경쟁을 줄여 UI 멈춤 빈도 완화.
- Verification:
  - 타입 오류를 수정한 뒤 `xcodebuild ... build` 재실행하여 `BUILD SUCCEEDED` 확인.

## Update 2026-02-11 (Backend Token Bootstrap for TeslaMate)

- Self-review (before coding):
  - SoC: OAuth code parsing/exchange 로직을 `tesla_oauth_common`으로 분리, TeslaMate 런타임 주입은 별도 bridge 모듈로 격리.
  - DIP: 기존 telemetry provider(`fleet`/`teslamate`) 흐름은 유지하고, bootstrap 유틸만 추가.
  - Multi-tenancy: 기존 단일 사용자 `.env` 구조를 유지(향후 `userId` 분리 필요 포인트로 기록).
  - Resilience/Observability: callback URL 입력 실수 방지(코드 파싱), 실패 시 단계별 오류 메시지 명시.
- Infrastructure update:
  - `backend/tesla_oauth_common.mjs`: code/callback parsing + token exchange 공통화.
  - `backend/teslamate_token_bridge.mjs`: docker rpc를 통한 TeslaMate runtime token sync.
  - `backend/tesla_oauth_exchange_and_sync.mjs`: exchange + env save + runtime sync one-shot workflow.
- Application/ops integration:
  - npm script `tesla:oauth:exchange:sync` 추가.
  - callback 안내 페이지/README를 one-step 명령 기준으로 업데이트.

## Update 2026-02-11 (TeslaMate Refresh Resilience)

- Self-review (before coding):
  - SoC: Fleet refresh는 OAuth utility 레이어, TeslaMate 주입은 bridge 레이어로 분리 유지.
  - DIP: 기존 provider(`fleet`/`teslamate`) 실행 경로는 변경하지 않고 운영 유틸만 추가.
  - Multi-tenancy: 기존 단일 `.env` 운영 모델 유지(차후 userId 분리 대상).
  - Resilience/Observability: TeslaMate 내부 refresh 실패(`.../nts/token`) 시 외부 refresh+sync 우회 경로 제공.
- Infrastructure update:
  - Added `backend/tesla_oauth_refresh_and_sync.mjs`:
    - Fleet auth token refresh (`/oauth2/v3/token`)
    - `.env` token persistence
    - TeslaMate runtime token sync (`docker exec ... TeslaMate.Auth.save + sign_in`)
- Application/ops integration:
  - Added npm script `tesla:oauth:refresh:sync`.
  - README에 장기 운영용 주기 refresh 안내 추가.

## Update 2026-02-12 (Backend Auto Auth-Repair for TeslaMate)

- Self-review (before coding):
  - SoC: TeslaMate fetch/command path는 유지하고, auth recovery는 backend orchestration helper로 분리.
  - DIP: `teslamate_client`의 API contract는 변경하지 않고 server application layer에서 실패 복구를 조합.
  - Multi-tenancy: 현재 단일 사용자 `.env` 기반 유지(추후 userId별 token vault 분리 필요).
  - Resilience/Observability: 무인 운영 중 token 만료/세션 이탈을 자동 복구하고 health로 상태 노출.
- Infrastructure update:
  - `backend/server.mjs`
    - `TESLAMATE_API_BASE` 기본값을 `http://127.0.0.1:8080`으로 설정.
    - TeslaMate auth failure(401/403/no cars/not signed in/token 관련) 감지 시:
      1) Fleet refresh token으로 access 갱신
      2) `.env` 토큰 갱신 저장
      3) TeslaMate runtime token sync (`TeslaMate.Auth.save`)
      4) 짧은 settle 후 재시도
    - cooldown/in-flight guard를 둬 과도한 재시도 방지.
    - `runtime.authRepair` 상태를 `/health`에 노출.
    - 수동 복구 endpoint 추가: `POST /api/teslamate/repair-auth`
- Ops integration:
  - `.env.example`에 auto-repair 관련 변수 추가:
    - `TESLAMATE_CONTAINER_NAME`
    - `TESLAMATE_AUTO_AUTH_REPAIR`
    - `TESLAMATE_AUTH_REPAIR_COOLDOWN_MS`
    - `TESLAMATE_AUTH_REPAIR_SETTLE_MS`

## Update 2026-02-12 (Kakao Web Domain + TeslaMate Command Alias Hardening)

- Self-review (before coding):
  - SoC: 지도 렌더링 안정화는 Navi web adapter, 명령 호환성은 backend application layer에서 처리.
  - DIP: Kakao API client contract 및 telemetry service contract는 변경하지 않음.
  - Multi-tenancy: user-scoped key storage 흐름 유지.
  - Resilience/Observability: 지도 blank 및 명령 404를 즉시 완화하는 runtime fallback 경로 추가.
- Infrastructure/application update:
  - `KakaoWebRouteMapView`:
    - `WKWebView.loadHTMLString` baseURL을 `https://tesla.splui.com`로 고정해 Kakao JS key의 웹 도메인 제한과 정합.
  - `backend/server.mjs`:
    - TeslaMate command 호출 시 alias 후보 자동 시도:
      - `door_lock <-> lock`
      - `door_unlock <-> unlock`
      - `auto_conditioning_start <-> climate_on`
      - `auto_conditioning_stop <-> climate_off`
    - 404/unsupported 계열 실패에서만 alias 재시도.
- UX/docs update:
  - `ConnectionGuideView`와 `README`에 Kakao JS key의 Web platform domain(`tesla.splui.com`) 요구사항 명시.
