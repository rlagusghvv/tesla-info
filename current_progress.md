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

### [현재 상태]
- Repo: `tesla-subdash-starter`
- Latest pushed commit: `aef17c7` (pushed to `origin/main`)
- Working tree: clean (no local code changes)
- Known issue (not fixed yet):
  - iPad app still shows vehicle location as unknown / `(0,0)` in `Map` and `Navi` tabs.
  - Pressing `Wake` now shows "Waking up..." but location still doesn't appear.

### [다음 단계]
- Add a debug button to show which location fields are present in the raw `vehicle_data` response (sanitized).
- If location is still missing after the above:
  - verify Tesla account/app has location sharing enabled for this OAuth client (Tesla-side setting),
  - and consider using a backend proxy to inspect raw JSON during debugging.

### [특이 사항]
- Xcode Simulator tooling on this machine is currently broken (`CoreSimulatorService connection invalid`), so CLI simulator builds are unreliable.
- CLI `xcodebuild` for device builds can fail due to provisioning profiles when run headless.
- Testing should be done by building/running from Xcode UI onto the physical iPad.
