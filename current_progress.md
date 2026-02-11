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
- Added one more fallback strategy:
  - If `vehicle_data` with query params is sparse, perform a secondary plain `GET /vehicle_data` (no query) and pick the richer snapshot.
  - Added score-based selection between primary and plain fallback snapshots.
- Diagnostics now compare both request variants:
  - `response_keys(flagged)` / `raw_fallback(flagged)`
  - `response_keys(plain)` / `raw_fallback(plain)`
- Recompiled successfully after this fallback extension.
- Added wake diagnostics and clearer user guidance:
  - `wake_up` response is now parsed and surfaced (`Wake accepted`, `Vehicle is online`, `Vehicle is still asleep`, etc.).
  - Wake now performs short server-side polling and reports if location is still unavailable.
  - If diagnostics show all location values are nil while `drive_state` key exists, app now shows a clear Tesla-side permission hint.
- Recompiled successfully after wake/permission-hint patch.
- Session resume completed:
  - Read `current_progress.md` first.
  - Re-validated workspace inventory with `ls -R`.
  - Confirmed repo is clean and latest pushed commit is `e37f75b`.
- Implemented new location parsing fallback for Tesla payload variants:
  - Added support for `native_latitude` / `native_longitude` in both `drive_state` and `location_data`.
  - Snapshot mapping now uses resolved coordinates (`latitude/longitude` first, then native coordinates).
  - Raw JSON location fallback now also checks native coordinate keys.
- Vehicle identifier stability tweak:
  - Temporarily tested `id-first`, then reverted to `VIN-first` to match Fleet API canonical guidance.
- Expanded snapshot diagnostics (Account -> Test Snapshot):
  - Added `drive_state(native)` and `location_data(native)` output fields.
  - Updated "likely Tesla-side filter" detection to include native coordinate channels.
- Added new Fleet status diagnostics (Account panel):
  - New button: `Test Fleet Status`.
  - Calls Fleet API `POST /api/1/vehicles/fleet_status` and displays:
    - `vehicle_command_protocol_required`
    - `total_number_of_keys`
    - response/status key summaries
  - Purpose: quickly distinguish permission issue vs key-pairing/command-protocol requirement.
- Fleet status parser hardening:
  - Handles more response shapes (`response[vin]` as dict/array/wrapped list).
  - Added recursive key lookup for protocol/key-count fields when nested.
  - Status message now includes `raw_preview` so payload shape can be debugged from iPad without CLI.
- Snapshot diagnostics hardening:
  - Added explicit call to `data_request/location_data` inside diagnostics.
  - Snapshot message now shows either:
    - `location_endpoint: lat, lon` or
    - `location_endpoint_error: ...`
  - Purpose: distinguish "field missing in vehicle_data" vs "location_data endpoint itself denied/failing".
- Interpreted 404 from user screenshot:
  - `data_request/location_data` returns `HTTP 404` (Fleet API path not supported in this environment).
  - Updated UI text to render this as expected note (`not supported on Fleet API`) instead of noisy HTML error dump.
- Added access-level diagnostics:
  - Snapshot status now shows `access_type(flagged)` and `access_type(plain)` extracted from raw responses.
  - Purpose: verify whether account-level access type might explain location redaction.
- Recompiled successfully (`xcodebuild ... CODE_SIGNING_ALLOWED=NO`) after the above changes.
- Recompiled successfully again after VIN-first restore and updated hint copy.
- Recompiled successfully again after adding Fleet status diagnostics.
- Recompiled successfully again after fleet_status parser hardening.
- Recompiled successfully again after location endpoint diagnostics addition.
- Recompiled successfully again after 404 handling + access_type diagnostics.
- Local backend diagnostic attempts:
  - `npm run backend:check:tesla` -> `token expired (401)`.
  - `npm run tesla:oauth:refresh` -> DNS failure (`ENOTFOUND fleet-auth.prd.vn.cloud.tesla.com`) in this shell environment.

### [현재 상태]
- Repo: `tesla-subdash-starter`
- Latest pushed commit: `e37f75b` (pushed to `origin/main`)
- Local uncommitted changes:
  - `Sources/Tesla/TeslaFleetService.swift` (native lat/lon fallback + hardened fleet_status + location endpoint diagnostics)
  - `Sources/Features/Connection/ConnectionGuideView.swift` (`raw_preview` + location endpoint diagnostic line)
  - `current_progress.md`
- Known issue (not fixed yet):
  - iPad app still shows vehicle location as unknown / `(0,0)` in `Map` and `Navi` tabs.
  - Even with valid token and scopes, some accounts still return `drive_state/location_data` coordinates as nil.
  - Root cause is likely Tesla-side filtering/pairing/region behavior, but this must be confirmed with new native-field diagnostics.
  - This shell session currently cannot resolve Tesla auth host DNS, so CLI token-refresh diagnostics are temporarily blocked.

### [다음 단계]
- Run on iPad and execute `Account -> Test Snapshot` again.
- Run on iPad and execute `Account -> Test Fleet Status` first.
- Capture:
  - `vehicle_command_protocol_required`
  - `total_number_of_keys`
  - `status_keys` / `response_keys`
  - `raw_preview` (first response snippet)
- Then run `Test Snapshot` and capture the new line:
  - `location_endpoint: ...` or `location_endpoint_error: ...`
- Also capture:
  - `access_type(flagged)`
  - `access_type(plain)`

### [추가 진단 결론 - 14:27]
- User provided latest diagnostics screenshot:
  - `vehicle_command_protocol_required: false`
  - `total_number_of_keys: 6`
  - `access_type(flagged): DRIVER`
  - `access_type(plain): DRIVER`
  - `location_endpoint: not supported on Fleet API (404 expected)`
- Interpretation:
  - Virtual key pairing is already present and command protocol is not blocking.
  - iPad-side key pairing is not the required next action.
  - Remaining blocker is location redaction/missing from `vehicle_data` while access_type is `DRIVER` (non-owner privilege context likely).
- Immediate next verification:
  - Re-authorize with the vehicle OWNER Tesla account (not shared DRIVER account) and compare whether `access_type` changes to `OWNER`.
  - If still missing on OWNER, escalate to Tesla support with sanitized request details and `x-txid`.

### [지원 문의 경로 정리]
- As of 2026-02-11, Tesla Fleet API 공식 지원 채널은 Developer Dashboard 내 `Support Inquiry` 경로 사용.
- 문의 시 포함 권장:
  - `client_id`
  - 문제 재현 단계
  - 예시 요청/응답(민감정보 마스킹)
  - 서버 응답 헤더 `x-txid`
- 주의:
  - Access token / refresh token / 비밀번호는 절대 전달하지 않음.
- 법인/리스 차량의 OWNER/DRIVER 계정 권한 이슈는 Fleet API 지원과 별도로, 차량 계약/권한 주체(법인 관리자/리스사) 확인이 필요할 수 있음.

### [사용자 문의 대응 - "누구한테 물어보나?"]
- 안내 원칙:
  1) Fleet API 기술 이슈 -> Tesla Developer Dashboard `Support Inquiry`
  2) 법인/리스 권한(OWNER vs DRIVER) -> 법인 Tesla 관리자/리스사 차량 관리 담당자
  3) 일반 고객센터는 개발 API 세부 권한보다 계약/계정 주체 확인 용도로 사용

### [문서 검토 - 2026-02-11]
- Reviewed the user-shared Fleet API docs page (`What is Fleet API`) and adjacent official pages:
  - Third-Party Tokens
  - Third-Party Business Tokens
  - Vehicle Endpoints
- Practical takeaway for this project:
  - Current diagnostics (`access_type=DRIVER`) remain the strongest signal for location redaction risk.
  - Fleet docs emphasize permission scope + owner/consent model; business/lease environments may require org-owner route rather than shared-driver route.

### [문서 근거 정리 - 리스/법인]
- Fleet API Vehicle Endpoints 문서에 명시:
  - share invite로 앱 접근을 받은 계정은 `DRIVER` 권한이며 `OWNER` 전체 기능을 포함하지 않음.
- Third-Party Business Tokens 문서에 명시:
  - 비즈니스 동의 기반 토큰 발급 절차가 따로 있으며, user endpoints와 호환되지 않음(사용자 컨텍스트 없음).
- Contact Us 문서에 명시:
  - 지원 문의는 Dashboard의 `Support Inquiry`로 제출하고, `client_id`, 재현 내용, curl/log, `x-txid`를 포함할 것.

### [외부 커뮤니티 리서치 - 2026-02-11]
- Reddit/해외 커뮤니티 유사 사례 검색 결과:
  - 리스 차량에서 "lease company is owner"로 인해 앱 권한 제약을 겪는 사례 다수 확인.
  - 2025-07 Tesla 앱 업데이트 이후 Owner가 Driver별 `Restrict Location Visibility`를 제어 가능하다는 다수 사례 확인.
  - 일부 사례에서 비-Owner(공유 드라이버)는 위치/드라이버 관리 기능 접근이 제한됨.
- 공식 문서와의 정합성:
  - Vehicle Endpoints의 "share invite -> DRIVER privileges" 문구와 커뮤니티 체감 증상이 일치.
  - 법인/리스 구조에서는 Third-Party Business Token/Consent Management 경로 검토가 필요하다는 점 확인.
- Capture and compare these fields:
  - `drive_state`, `drive_state(native)`
  - `location_data`, `location_data(native)`
  - `raw_fallback`, `raw_fallback(plain)`
- If all coordinates are still nil:
  - confirm Tesla app Third Party permission is saved for this exact client ID (toggle off/on once),
  - then test a fresh re-login in app (`Sign Out -> Connect`) to force new token issuance.
- If still nil after re-login:
  - add one more diagnostic path (raw nested key dump per block) or backend raw-response probe to verify whether Tesla is redacting coordinates server-side.
  - Once DNS is normal in shell, rerun CLI diagnostics to capture sanitized raw payload outside the app runtime.

### [특이 사항]
- Xcode Simulator tooling on this machine is currently broken (`CoreSimulatorService connection invalid`), so CLI simulator builds are unreliable.
- CLI `xcodebuild` for device builds can fail due to provisioning profiles when run headless.
- Testing should be done by building/running from Xcode UI onto the physical iPad.

## 2026-02-11 (TeslaMate 우회 연동)

### [완료된 작업]
- Workspace full scan executed via `ls -R` before edits.
- Added TeslaMate backend client:
  - new file: `backend/teslamate_client.mjs`
  - flexible endpoint probing (`cars`, `status`, `command`, `wake_up`) with fallback paths
  - tolerant payload mapping for location/battery/speed/lock/climate fields
- Extended backend mode handling:
  - `backend/server.mjs` now supports `teslamate` mode (`USE_TESLAMATE=1` or `DATA_SOURCE=teslamate`)
  - new diagnostics endpoints:
    - `GET /api/teslamate/cars`
    - `GET /api/teslamate/status`
  - generic poll endpoint:
    - `POST /api/vehicle/poll-now`
  - existing `POST /api/tesla/poll-now` now works for both fleet/teslamate modes
  - command routing now branches by mode (`simulator` / `fleet` / `teslamate`)
- Added npm scripts:
  - `backend:start:teslamate`
  - `backend:start:teslamate:lan`
- iPad app telemetry source switch implemented:
  - `AppConfig` now stores `TelemetrySource` (`direct_fleet` / `backend`)
  - `TelemetryService` now routes to:
    - direct Tesla Fleet API
    - or backend endpoints (`/api/vehicle/latest`, `/api/vehicle/command`)
  - `ConnectionGuideView` now includes:
    - `Telemetry Source` selector
    - backend URL save/test UI
    - backend mode allows `Start Car Mode` without Tesla direct login
- UI style update:
  - `SecondaryCarButtonStyle` now supports custom fill/stroke colors for selected source buttons.
- Docs updated:
  - `README.md` now includes TeslaMate fallback setup and updated API contract.
  - `backend/.env.example` now includes TeslaMate env variables.
- Verification:
  - `node --check backend/server.mjs` passed.
  - `node --check backend/teslamate_client.mjs` passed.
  - `xcodebuild ... CODE_SIGNING_ALLOWED=NO build` passed (warnings about CoreSimulatorService remain, build succeeded).
  - backend teslamate startup smoke test passed under escalated execution (`mode=teslamate` log confirmed).

### [현재 상태]
- New TeslaMate fallback path is implemented in code and build-verified.
- Modified files:
  - `backend/teslamate_client.mjs` (new)
  - `backend/server.mjs`
  - `backend/.env.example`
  - `package.json`
  - `Sources/Features/Shared/AppConfig.swift`
  - `Sources/Telemetry/TelemetryService.swift`
  - `Sources/Features/Connection/ConnectionGuideView.swift`
  - `Sources/Features/Common/ButtonStyles.swift`
  - `README.md`
  - `current_progress.md`
- Also still present from previous session (not reverted):
  - `Sources/Tesla/TeslaFleetService.swift`

### [다음 단계]
- On Mac:
  1) Set `.env` with TeslaMate values (`TESLAMATE_API_BASE`, optional token/id)
  2) Run `npm run backend:start:teslamate:lan`
  3) Confirm `curl http://<LAN_IP>:8787/health` -> `mode=teslamate`
- On iPad:
  1) Open `Connection Guide`
  2) Set `Telemetry Source = Backend`
  3) Save/Test backend URL (`http://<LAN_IP>:8787`)
  4) Enter Car Mode and verify map location updates
- If TeslaMate endpoint auth fails:
  - set `TESLAMATE_AUTH_HEADER` or `TESLAMATE_TOKEN_QUERY_KEY` and retry.

### [특이 사항]
- Sandbox environment blocks local port listen without escalation (`EPERM`), so backend runtime check required escalated execution in this session.
- CoreSimulator warnings continue, but app build completes successfully.

## 2026-02-11 (TeslaMate 접속 확인 요청 대응)

### [완료된 작업]
- Workspace scan (`ls -R`) executed before diagnostics.
- Local runtime probes executed:
  - `docker ps` -> `docker` command not found in this environment.
  - `curl http://127.0.0.1:8080/api/v1/cars` -> connection refused.
  - `lsof` probe for common ports showed no active TeslaMate API listener.

### [현재 상태]
- This machine/session cannot directly discover a running TeslaMate API endpoint.
- Therefore, user must first provide a reachable TeslaMate API base URL (local/LAN/remote) and token style.

### [다음 단계]
- Provide the user a very simple, step-by-step "how to access TeslaMate API" checklist.
- Ask for two values only:
  - `TESLAMATE_API_BASE`
  - `TESLAMATE_API_TOKEN` (or query-token key style)
- After receiving values, run backend in `teslamate` mode and verify live endpoint path.

### [특이 사항]
- No local Docker binary available in this shell.
- No local TeslaMate API listening on `127.0.0.1:8080`.

## 2026-02-11 (Docker/Colima 설치 진행)

### [완료된 작업]
- Workspace scan executed first (`ls -R` from `/Users/kimhyeonho`).
- Attempted `brew install --cask docker`:
  - failed due non-interactive `sudo` password prompt in cask postflight.
- Diagnosed Homebrew write issues under sandbox:
  - standard (non-escalated) brew install cannot write `/opt/homebrew`.
- Performed permission-recovery commands for Homebrew paths under escalated execution.
- Installed Docker tooling under escalated execution:
  - `brew install docker docker-compose colima` succeeded.
- Configured Docker CLI plugin path:
  - wrote `~/.docker/config.json` with `cliPluginsExtraDirs`.
- Verified binaries:
  - `docker --version` -> OK
  - `docker compose version` -> OK
  - `docker-compose version` -> OK
- Started Colima (Docker runtime) under escalated execution and verified:
  - `colima status` -> running (`runtime: docker`)
  - `docker ps` -> empty list (daemon reachable)

### [현재 상태]
- Docker CLI + Compose + Colima are installed and working when invoked under escalated execution in this environment.
- Host now has a usable Docker runtime for launching TeslaMate stack.

### [다음 단계]
- Create/prepare TeslaMate `docker-compose.yml` (or use existing one if user already has).
- Launch TeslaMate + TeslaMateApi containers.
- Verify API endpoints:
  - `/api/healthz`
  - `/api/v1/cars` (with token)
- Feed `TESLAMATE_API_BASE` + token into `tesla-subdash-starter` backend `.env` and run live test.

### [특이 사항]
- `docker` and `colima` commands may require escalated execution in this tool environment due sandbox restrictions, even though host installation is complete.

## 2026-02-11 (추가 업데이트 @16:10)

### [완료된 작업]
- 전체 워크스페이스 스캔 재실행: `ls -R` 수행 후 결과 저장 (`/tmp/workspace_tree_20260211.txt`, 약 2,282,785 lines).
- Docker/Colima 기반 실행환경 구축 완료:
  - `brew install docker docker-compose colima`
  - `colima start -f`
  - `docker run --rm hello-world` 성공
- TeslaMate 로컬 스택 구성 파일 생성:
  - `~/teslamate-stack/docker-compose.yml`
  - `~/teslamate-stack/.env`
  - `~/teslamate-stack/.env.example`
  - `~/teslamate-stack/mosquitto/config/mosquitto.conf`
- TeslaMate 스택 기동 완료:
  - `docker compose up -d`
  - `docker compose ps` 기준 핵심 서비스 모두 `Up` 상태 확인
    - `database`, `mosquitto`, `teslamate`, `grafana`, `teslamateapi`

### [현재 상태]
- TeslaMate 접근 엔드포인트(로컬):
  - `http://localhost:4000` (TeslaMate)
  - `http://localhost:3000` (Grafana)
  - `http://localhost:8080` (TeslaMate API)
- 현재 앱(Fleet API 경로) 이슈는 별개로 남아있고, 병행 우회안으로 TeslaMate 경로를 준비한 상태.
- `teslamateapi`는 초기 DB 준비 타이밍에 일시 connect refused 로그가 있었으나 현재 컨테이너 상태는 `Up`.

### [다음 단계]
- TeslaMate 웹(`localhost:4000`)에서 Tesla OAuth 로그인 완료.
- 차량 데이터가 TeslaMate에 쌓이는지 확인(위치/속도/주행).
- `localhost:8080` API 토큰 기반 호출 테스트 후, 기존 iPad 앱 백엔드를 Fleet API 대신 TeslaMate API로 스위치하는 어댑터 추가.
- iPad 실기기에서 지도/내비 탭 고정성(멈춤 이슈) 재검증 및 UI 비중(지도/미디어 중심) 재조정.

### [특이 사항]
- Docker Desktop(cask)은 비대화형 sudo 제약으로 자동 설치 실패. 현재는 Docker CLI + Colima 조합으로 정상 대체 운용.
- macOS 권한 제한 디렉터리(예: 일부 `~/Library/*`)는 `ls -R` 중 `Operation not permitted` 메시지가 발생했으나, 사용자 워크스페이스 작업에는 영향 없음.

## 2026-02-11 (추가 업데이트 @16:16)

### [완료된 작업]
- `tesla-subdash-starter/.env`를 TeslaMate 모드로 설정:
  - `USE_TESLAMATE=1`
  - `DATA_SOURCE=teslamate`
  - `TESLAMATE_API_BASE=http://127.0.0.1:8080`
  - `TESLAMATE_API_TOKEN` 주입 완료
- 앱 백엔드(TeslaSubDash) 실행 확인:
  - `npm run backend:start:teslamate:lan`
  - 리슨 주소: `http://0.0.0.0:8787`
  - LAN 후보: `http://172.20.10.5:8787`, `http://172.20.10.3:8787`
- 백엔드 엔드포인트 검증:
  - `/health` -> `mode=teslamate`, token/base set
  - `/api/teslamate/status` -> `TeslaMate API returned no cars.`
  - `/api/teslamate/cars` -> 빈 배열

### [현재 상태]
- 인프라/연결 자체는 정상 (Docker/Colima/TeslaMate/TeslaMateApi/앱 백엔드 모두 기동 가능).
- 현재 막힌 지점은 "TeslaMate에 차량 데이터가 아직 적재되지 않음" 하나.
- 즉, Fleet API 권한 이슈와 별개로, TeslaMate 웹에서 Tesla 로그인 완료 후 첫 동기화가 필요.

### [다음 단계]
- 브라우저에서 `http://localhost:4000` 접속.
- TeslaMate 초기 로그인(테슬라 OAuth) 완료.
- `http://127.0.0.1:8787/api/teslamate/status` 재호출해 `ok:true` + car 정보 확인.
- 이후 iPad 앱에서 기존 백엔드 URL(`http://<맥북IP>:8787`) 유지한 채 지도/내비 동작 점검.

### [특이 사항]
- 백엔드가 `0.0.0.0:8787` 바인딩일 때 이 실행환경에서는 권한 제한이 있어, 검증 명령은 escalated 실행이 필요함.
- 현 시점 기준 `no cars`는 인증 실패가 아니라 TeslaMate 수집 미완료 상태일 가능성이 높음.

## 2026-02-11 (추가 업데이트 @16:20)

### [완료된 작업]
- TeslaMate 로그인 화면 원인 확인: 해당 화면은 "Tesla OAuth 자동 리다이렉트"가 아닌 "수동 토큰 입력 방식"임.
- 사용자 앱 설정 기준으로 새 OAuth URL 생성 완료 (`npm run tesla:oauth:start`).
  - redirect_uri: `https://www.splui.com/oauth/callback`
  - scope: `openid offline_access vehicle_device_data vehicle_cmds vehicle_charging_cmds`

### [현재 상태]
- 사용자 토큰(Access/Refresh)만 확보하면 TeslaMate 로그인 카드에 붙여넣어 로그인 가능.
- 인프라 문제 아님. 로그인 재료(토큰)만 필요한 단계.

### [다음 단계]
- 생성된 authorize URL 접속 -> Tesla 로그인 -> callback URL에서 `code` 획득.
- `npm run tesla:oauth:exchange -- "<code>"` 실행해 access/refresh 발급.
- 발급 토큰을 TeslaMate 웹 로그인 폼 2칸에 붙여넣고 `로그인`.
- 성공 후 `api/v1/cars` 재확인.

### [특이 사항]
- TeslaMate 로그인 카드에는 `client_id/client_secret`가 아니라 `user access token / refresh token`을 넣어야 함.

## 2026-02-11 (추가 업데이트 @16:29)

### [완료된 작업]
- 사용자 제공 callback code 교환 시도:
  - 실패 원인 확인: `.env`의 `TESLA_CODE_VERIFIER`가 비어 있어 PKCE 검증 불가.
- 새 OAuth 시작 재실행:
  - 새 state/verifier 발급 완료 (`TESLA_OAUTH_STATE`, `TESLA_CODE_VERIFIER` 갱신됨).
- 아키텍처 원칙 고정 문서 추가:
  - `docs/architecture_notes.md` 생성
  - 계층 분리/DI/멀티테넌시/복구탄력성/관측성/자가검토 원칙 기록
- TeslaMate 자동 로그인 가능성 확인:
  - `/sign_in`은 단순 POST 엔드포인트가 아니며 LiveView 기반.
  - 대신 런타임 `TeslaMate.Auth` 모듈 접근 가능 확인.
  - `TeslaMate.Auth.change_tokens/1` + `save/1` 경로 확인 완료(유효 토큰 필요).

### [현재 상태]
- 새 PKCE 세션은 준비 완료.
- 사용자의 새 callback `code`만 받으면:
  1) 토큰 교환
  2) TeslaMate 내부 Auth 저장(자동 로그인)
  3) `api/v1/cars` 재검증
  까지 즉시 진행 가능.

### [다음 단계]
- 새 authorize URL로 Tesla 로그인 후 callback URL 전달 받기.
- 전달받은 `code`로 `tesla:oauth:exchange` 실행.
- 발급된 토큰을 TeslaMate에 런타임 저장(수동 복붙 없이 처리).
- `/api/teslamate/status` 확인 후 iPad 앱 연결 검증.

### [특이 사항]
- 기존 callback code(state=GG...)는 현재 verifier(state=JAN...)와 세트가 달라 재사용 불가.

## 2026-02-11 (추가 업데이트 @16:56)

### [완료된 작업]
- 원인 규명 완료:
  - TeslaMate가 Owner API 스타일 refresh 경로(`/oauth2/v3/nts/token`)를 사용해 401/404 발생.
  - 결과적으로 토큰은 저장돼도 차량 수집(`cars`)이 시작되지 않던 상태.
- TeslaMate Fleet 모드 설정 반영:
  - `~/teslamate-stack/docker-compose.yml`의 `teslamate` 서비스 env에 추가:
    - `TESLA_API_HOST=${TM_TESLA_API_HOST}`
    - `TESLA_AUTH_HOST=${TM_TESLA_AUTH_HOST}`
    - `TESLA_AUTH_PATH=${TM_TESLA_AUTH_PATH}`
    - `TESLA_AUTH_CLIENT_ID=${TM_TESLA_AUTH_CLIENT_ID}`
  - `~/teslamate-stack/.env`, `.env.example`에 위 변수값 추가.
- TeslaMate 토큰 저장 성공:
  - `TeslaMate.Auth.save(%{token: ..., refresh_token: ...})` 형식으로 저장해야 함(키 이름 중요).
- TeslaMate 차량 수집 복구 확인:
  - `GET /api/v1/cars` -> 실제 차량 1대 반환 확인.
- 앱 백엔드 파서 버그 수정:
  - 파일: `tesla-subdash-starter/backend/teslamate_client.mjs`
  - 수정: `asArrayPayload()`가 `parsed.data.cars` 형태를 읽지 못해 항상 "no cars"로 판단하던 문제 해결.
  - 추가 파싱 경로:
    - `parsed.data.cars`
    - `parsed.data.items`
    - `parsed.response.data.cars`
- 엔드투엔드 확인 성공:
  - `http://127.0.0.1:8787/health` -> `mode=teslamate`, `resolvedTeslaMateCarId=1`
  - `http://127.0.0.1:8787/api/teslamate/status` -> `carsCount=1`
  - `http://127.0.0.1:8787/api/vehicle/latest` -> 실제 위치/배터리/상태 데이터 반환

### [현재 상태]
- 핵심 블로커(차량 null)는 해소됨.
- TeslaMate -> backend -> iPad 경로로 실데이터 공급 가능 상태.

### [다음 단계]
- iPad 앱에서 backend URL을 `http://172.20.10.5:8787`(또는 동일 네트워크의 현재 LAN IP)로 설정.
- 앱에서 `Refresh` 후 지도/내비의 차량 위치 반영 확인.
- 그 다음 UI 작업(지도/미디어 비중 확대, 버튼/정보 패널 축소) 진행.

### [특이 사항]
- 사용자 제공 OAuth code는 PKCE 쌍(state/verifier)이 정확히 일치해야 교환 성공.
- 현재 백엔드는 실행 세션(`npm run backend:start:teslamate:lan`)이 살아있는 동안 정상 동작.

## 2026-02-11 (추가 업데이트 @17:10)

### [완료된 작업]
- 사용자 보고 이슈 대응: "앱 멈춤으로 Account에서 주소 수정 불가".
- 안정화 패치 적용:
  - `CarModeView`: Account/Setup 시트가 열리면 폴링 중지, 닫히면 재시작 (UI hitch 완화).
  - `ConnectionGuideView`: 백엔드 URL 빠른 선택 버튼 추가 (`172.20.10.5`, `172.20.10.3`, `127.0.0.1`).
  - `ConnectionGuideView`: `Auto Detect Backend` 추가 (health endpoint 탐지 후 자동 저장).
  - `ConnectionGuideView`: 백엔드 테스트 로직을 짧은 timeout 기반 probe 함수로 정리.
  - `AppConfig`: telemetry 기본값을 backend로 변경(직접 Fleet 기본 진입으로 인한 불안정 완화).
  - `KakaoAPIClient`: 경로 폴리라인 최대 포인트 900 -> 450 축소(MapKit 렌더링 부담 감소).
- 빌드 검증:
  - `xcodebuild ... TeslaSubDash ... build` 성공.

### [현재 상태]
- 코드 레벨에서 "주소 입력 시 버벅임/멈춤" 완화 장치가 반영됨.
- 사용자는 타이핑 없이 원탭으로 백엔드 URL 적용/탐지 가능.

### [다음 단계]
- iPad 실기기에서 Account 진입 -> `Auto Detect Backend` 1회 실행.
- 감지 성공 후 Car Mode에서 지도/내비 갱신 확인.
- 여전히 멈춤이 있으면(재현 스텝 확보 후) 해당 뷰 트리 기준 추가 프로파일링.

### [특이 사항]
- 워크트리는 사용자의 기존 변경(README, Tesla/Fleet 관련 파일 등)이 이미 존재하는 상태로 유지.

## 2026-02-11 (추가 업데이트 @17:17)

### [완료된 작업]
- 사용자 보고 "Could not connect to the server" 원인 점검.
- 확인 결과:
  - TeslaMate 컨테이너는 정상 실행 중.
  - 앱 백엔드(8787)가 내려가 있어 iPad 연결 실패.
- 백엔드 재기동 및 라이브 검증:
  - `npm run backend:start:teslamate:lan` 실행(활성 세션 유지 중).
  - `/health` 정상 (`mode=teslamate`, `resolvedTeslaMateCarId=1`).
  - `/api/teslamate/status` 정상 (`carsCount=1`).
  - `/api/vehicle/latest` 정상 (실데이터 위치/배터리 포함).

### [현재 상태]
- 서버는 현재 정상 동작 중이며, iPad에서 접근 가능한 상태.
- 유효 접속 주소: `http://172.20.10.5:8787` (동일 네트워크 기준)

### [다음 단계]
- iPad 앱 강제 종료 후 재실행.
- Account에서 backend URL 확인/자동감지 후 Refresh.
- 재현 시 스크린샷 + 시간 기준으로 추가 추적.

### [특이 사항]
- 백엔드는 실행 세션이 종료되면 내려갈 수 있으므로, 맥북에서 서버 세션 유지 필요.

## 2026-02-11 (추가 업데이트 @17:30)

### [완료된 작업]
- 사용자 피드백 반영: TeslaMate 경유 시 주행가능거리/주행거리 값 비정상 문제 수정.
- 원인:
  - TeslaMate status payload는 `units.unit_of_length=km`를 제공하지만,
  - 백엔드(`backend/teslamate_client.mjs`)가 `battery_range/odometer/speed`를 miles로 가정해 재변환함.
- 수정 내용:
  - 길이 단위 판별 함수 추가: `resolveLengthUnit(payload)`.
  - `resolveRangeKm`가 단위(`km/mi`) 기반으로 변환하도록 수정.
  - `resolveOdometerKm`가 단위 기반으로 변환하도록 수정.
  - `speed` 필드도 단위 기반(`km`면 그대로, `mi`면 변환)으로 처리.
- 검증:
  - `GET /api/vehicle/latest` 결과 정상화:
    - `estimatedRangeKm: 294.75`
    - `odometerKm: 71177.27`

### [현재 상태]
- 위치/배터리/거리/주행거리 단위 매핑이 TeslaMate payload 기준으로 정상.
- 백엔드 세션은 현재 실행 중(`backend:start:teslamate:lan`).

### [다음 단계]
- iPad 앱에서 Range/주행거리 표시값 재확인.
- 상시 사용 목적이면 맥미니로 스택(TeslaMate + backend) 이전 및 자동시작(launchd) 구성.

### [특이 사항]
- macOS 네트워크/세션 종료 시 백엔드가 내려갈 수 있으므로, 상시운영은 별도 호스트(맥미니)로 이관 권장.

## 2026-02-11 (추가 업데이트 @17:33)

### [완료된 작업]
- 사용자 요청에 따라 최신 로컬 변경사항을 GitHub 공유 대상으로 정리 시작.
- 변경 파일 대상 민감정보 패턴 점검(토큰/secret 문자열) 수행 -> 노출 패턴 미검출.

### [현재 상태]
- 커밋/푸시 직전 상태.

### [다음 단계]
- 변경분 커밋.
- `origin/main` 푸시.
- 푸시된 커밋 해시 공유.

### [특이 사항]
- 기존 워크트리 변경사항을 그대로 보존한 채 일괄 커밋 예정.
