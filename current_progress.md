# Current Progress (TeslaSubDash / tesla-info)

This file is the "single source of truth" for session continuity.
When resuming work, read this file first and continue from **[다음 단계]**.

## 2026-02-11

### [완료된 작업]
- Workspace full scan executed via `ls -R` (very large output; confirms current file inventory).
- Investigated why Tesla Fleet API returns vehicle location as `(0,0)` even though the official Tesla app shows correct location.
- Updated Fleet API requests to:
  - request `location_data` as part of the `vehicle_data` query (2023.38+ firmware behavior)
  - call `wake_up` using the correct endpoint (`/wake_up`, not `/command/wake_up`)
  - prefer VIN if available (Fleet API docs are VIN-centric)
- Added/updated handoff notes for the above changes.
- Committed and pushed to GitHub.
- Additional location fixes:
  - `vehicle_data` now sends `location_data=true` query param (in addition to `endpoints=...`).
  - Decode + map `location_data` object when present (previously ignored).
  - Added fallback request: `data_request/location_data` if location is still missing after `drive_state`.
- Verified the project still compiles via `xcodebuild ... CODE_SIGNING_ALLOWED=NO`.
- Committed + pushed additional fixes:
  - commit: `aef17c7`
  - branch: `main`
  - remote: `origin/main`
- New diagnostics and wake behavior updates:
  - Added `testSnapshotDiagnostics()` to inspect `drive_state` vs `location_data` coordinates directly.
  - `Test Snapshot` now displays both sources (`drive_state`, `location_data`) when location is missing.
  - Wake flow in Car Mode now auto-retries refresh multiple times (instead of one delayed refresh).
- Compiled again successfully after the above changes.
- Added raw-response diagnostics for location parsing:
  - `Test Snapshot` now shows `response_keys` and `raw_fallback` coordinates extracted from raw JSON.
  - Added robust raw JSON location extraction paths:
    - `response.drive_state`
    - `response.location_data`
    - `response.vehicle_data.drive_state`
    - `response.vehicle_data.location_data`
    - `response.vehicle_data_combo.drive_state`
    - `response.vehicle_data_combo.location_data`
  - If typed decoding misses location, snapshot mapping now applies this raw fallback patch.
- Recompiled successfully after the raw fallback patch.

### [현재 상태]
- Repo: `tesla-subdash-starter`
- Latest pushed commit: `0135e29` (pushed to `origin/main`)
- Local uncommitted changes:
  - `Sources/Tesla/TeslaFleetService.swift` (raw location fallback + response key diagnostics)
  - `Sources/Features/Connection/ConnectionGuideView.swift` (status text with response key/raw fallback)
  - `current_progress.md`
- Known issue (not fixed yet):
  - iPad app still shows vehicle location as unknown / `(0,0)` in `Map` and `Navi` tabs.
  - Pressing `Wake` now shows "Waking up..." but location still doesn't appear.

### [다음 단계]
- Commit + push the raw-response diagnostics patch.
- Rebuild on iPad and run `Test Snapshot` to check:
  - `drive_state` coordinates
  - `location_data` coordinates
  - `raw_fallback` coordinates
  - `response_keys`
- If both are nil/0.0 even after wake:
  - verify Tesla-side location sharing for this OAuth client,
  - then capture a sanitized raw Fleet response via backend proxy for final root-cause isolation.
- If location is still missing after the above:
  - verify Tesla account/app has location sharing enabled for this OAuth client (Tesla-side setting),
  - and consider using a backend proxy to inspect raw JSON during debugging.

### [특이 사항]
- Xcode Simulator tooling on this machine is currently broken (`CoreSimulatorService connection invalid`), so CLI simulator builds are unreliable.
- CLI `xcodebuild` for device builds can fail due to provisioning profiles when run headless.
- Testing should be done by building/running from Xcode UI onto the physical iPad.
