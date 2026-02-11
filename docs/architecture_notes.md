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
