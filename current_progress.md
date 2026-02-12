# Current Progress (TeslaSubDash / tesla-info)

This file is the "single source of truth" for session continuity.
When resuming work, read this file first and continue from **[다음 단계]**.

## 2026-02-12

### [쿠팡 코끼리 - 문제 파악]
- 초기에는 repo(`tesla-info/_repo`)에서 "쿠팡/코끼리/coupang/elephant" 키워드 및 관련 파일명 검색 결과 0건이었음.
- 이후 대표 레퍼런스(https://www.coupilot.net/) 제공됨 → 동일본 제작 착수.

### [쿠팡 코끼리 - Coupilot 동일본 1차]
- Next.js(App Router) + Tailwind로 랜딩 1차 동일본 생성
  - 경로: `coupang-elephant/`
  - 페이지: `coupang-elephant/app/page.tsx`
  - 로컬 실행: `cd coupang-elephant && npm install && npm run dev -- --port 3333`
- 레퍼런스 기반 스펙 문서: `docs/coupang_elephant_coupilot_clone_spec.md`
- 실행 계획/일정 제안(유료급 품질 기준 포함): `docs/coupang_elephant_plan.md`
- 참고: Next가 workspace root 경고를 띄울 수 있음(상위 lockfile 탐지). 기능에는 영향 없으나 추후 `turbopack.root` 설정으로 정리 가능.


### [TestFlight 업로드(빌드 24/25) – 누가/어떤 키로 업로드했나]
- 업로드 실행 주체: 이 Mac mini(OpenClaw ops 세션)에서 fastlane으로 업로드 수행
- 인증 방식: App Store Connect API Key(.p8)
  - (Build 24) 로그에 `-authenticationKeyPath "/Users/kimhyunhomacmini/.openclaw/secrets/appstoreconnect/AuthKey_87GSWAQ5P2.p8"` 로 표시됨
  - (Build 24) gym → upload_to_testflight 단계 모두 성공(15:04 KST)
  - (Build 25) `~/Library/Logs/gym/TeslaSubDash-TeslaSubDash.log` 타임스탬프 15:31 기준으로 archive 성공 확인, `Shared/Config/Info.plist`의 `CFBundleVersion=25` 로 증가 확인
- 참고: 중간에 `cannot find '$naviHUDVisible' in scope` 에러는 Debug(simulator) 빌드에서 발생한 별도 로그이며, Release 아카이브/업로드 성공과는 무관

### [키 공유 요청 관련 주의]
- ASC API Key(.p8)는 **민감정보**라서 repo/MD에 원문 키를 공유하면 안 됩니다.
- 현재 업로드에 사용된 키는 이 Mac mini의 OpenClaw 시크릿 경로에 존재합니다(로컬 전용):
  - `/Users/kimhyunhomacmini/.openclaw/secrets/appstoreconnect/AuthKey_87GSWAQ5P2.p8`
- 팀장 환경에서 업로드가 필요하면:
  1) 팀장 PC에도 동일한 ASC API Key를 안전 경로에 저장(예: 개인 시크릿 디렉토리)
  2) fastlane 실행 시 아래 env를 세팅
     - `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_PATH`(=p8 파일 경로)
     - (편의) `tesla-subdash-starter/fastlane/.env.asc` 로컬 파일로만 보관(레포 커밋 금지)
  3) 또는 이 Mac mini에서 업로드 lane을 계속 수행(키를 외부로 복사하지 않는 방식)

### [팀장 업로드 실패(ASC_KEY_ID 비어있음) 트러블슈팅]
- `Missing required env var: ASC_KEY_ID` 는 **키가 없어서가 아니라, 실행 환경에 env가 로드되지 않은 상태**를 의미.
- 해결 옵션(둘 중 택1):
  - A) 팀장 PC에서 `.env.asc`를 실제 값으로 채우고 fastlane이 이를 읽도록 구성
  - B) fastlane 실행 커맨드에 `-authenticationKeyPath /path/to/AuthKey_XXXX.p8 -authenticationKeyID XXXX -authenticationKeyIssuerID YYYY` 를 직접 전달(현재 ops가 build 24 업로드할 때 사용한 방식)
- 민감정보는 절대 MD/레포에 붙이지 말고, **로컬 시크릿 파일/키체인/CI secret**으로만 관리


### [스프린트 목표]
- “TestFlight 업로드를 CLI로 재현 가능하게 만들기”

### [운영 메모]
- 사용자 코멘트: 업로드는 막힌 상태가 아니며(ASC 키/권한은 이미 준비됨), 팀장님 쪽에서 자동으로 계속 업로드해왔다고 함.
- 사용자 요청(14:58): 다른 봇들이 "태그될 때만 말하기"로 설정된 것으로 보이니, (1) 운영 룰/프롬프트 레벨에서 풀어서 태그 없이도 **완료!/확인!** ack를 남길 수 있게 변경.
  - 참고: 이 인스턴스(ui, 화면삼)는 다른 봇의 프롬프트/설정을 직접 수정할 권한/세션이 없음. 팀장 봇 쪽 설정 또는 각 봇의 system/developer 프롬프트에서 변경 필요.
- 추가 코멘트: 키는 이미 존재하며, 최근 build 22도 자동 업로드 되었음.

### [업로드 확인 - 15:32]
- fastlane `report.xml` 갱신됨 (step `gym` + `upload_to_testflight` 실행 기록)
- 로컬 프로젝트 빌드 넘버가 **25로 bump**된 상태(Info.plist / project.pbxproj 변경 확인)
- 주의: TestFlight에서 실제로 보이기까지는 processing 때문에 수 분 지연될 수 있음

### [사용자 피드백 - Build 25 (15:53 KST)]
- UI: 상단에 너무 붙어있고 패널들이 겹쳐서 가시성/터치가 나쁨(상단 바 터치되는 경우). 요청: 전체를 아래로 내리고, 네비 배너/패널을 **드래그로 위치 이동 가능**하게.
- Media: 확대/축소가 컨테이너 리사이즈가 아니라 **웹페이지 줌**처럼 동작(해결 필요).
- Navi: 안내 시작 시 지도 auto-zoom/follow가 아직 미흡(세계지도 수준). 요청: 시작 시 줌인 + 주행 중 위치 따라 카메라 이동.
- Fleet: 이번 빌드에서 해결 요구(퇴근길 18:00에 사용 예정).

### [대표 요청 - 이사님에게 전달할 프롬프트 작성 (16:08 KST)]
- 프롬프트 파일 생성: `docs/prompt_for_director.md`
  - iPad mini 6 기준 UI/Media 리사이즈/Navi auto-zoom+follow/Fleet control 안정화 요구사항 정리

### [완료]
- Workspace scan: `ls -R` 완료
- Xcode/CLI tool 확인:
  - `xcodebuild -version` / `xcode-select -p` OK
  - macOS 기본 ruby(2.6) + bundler(1.17)로는 `Gemfile.lock`의 bundler(4.0.3) 요구사항 때문에 fastlane 실행이 깨짐
  - 해결: `export PATH="/opt/homebrew/opt/ruby/bin:$PATH"`로 Homebrew ruby(4.x) + bundler(4.0.3) 사용
  - `bundle exec fastlane --version` OK (fastlane 2.232.1)
- Scheme/Project 확인:
  - `xcodebuild -list -project TeslaSubDash.xcodeproj` → scheme `TeslaSubDash` 확인
  - Bundle ID: `com.kimhyeonho.teslasubdash`
- 빌드 가능 여부(코드사인 제외) 재확인:
  - `xcodebuild -project TeslaSubDash.xcodeproj -scheme TeslaSubDash -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO clean build` → **BUILD SUCCEEDED**
- Fastlane 구성(생성/정리 완료):
  - `tesla-subdash-starter/fastlane/Fastfile` + `Appfile` (lane: `ios beta`)
  - 옵션 env: `ALLOW_PROVISIONING_UPDATES=1` → gym에 `-allowProvisioningUpdates` 전달(단, Xcode Accounts 로그인 필요)
  - Runbook: `docs/testflight_release_runbook.md`
  - `.gitignore`: `*.p8` 포함(민감정보 커밋 방지)

### [실행 시도 결과]
- `bundle exec fastlane ios beta` 실행 → 실패(예상): `Missing required env var: ASC_KEY_ID`
  - 원인 분류: ASC API Key 환경변수 미세팅(정상적인 fail-fast)
- `xcodebuild archive` 실행(서명 포함) → 실패:
  - `Provisioning profile "iOS Team Provisioning Profile: *" doesn't include signing certificate "Apple Development: hyunho Kim (PGG9A92LST)"`

### [현재 상태]
- CLI로 컴파일은 재현 가능(코드사인 제외).
- TestFlight 업로드 lane은 준비되어 있으나,
  - ASC API Key env 세팅 +
  - 로컬 signing(배포 cert/provisioning) 준비
  가 충족되어야 실제 업로드 가능.

### [다음 단계]
1) ASC env 세팅(로컬 전용): `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_PATH`, `APPLE_TEAM_ID`
2) Signing 준비(로컬): 배포용 cert/provisioning 또는 Xcode 계정 로그인 후 Automatic Signing
3) 실행:
   - `cd tesla-subdash-starter && export PATH="/opt/homebrew/opt/ruby/bin:$PATH" && bundle install && bundle exec fastlane ios beta`
4) 성공/실패 로그를 `current_progress.md`와 runbook에 추가

---

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

## 2026-02-11 (추가 업데이트 @18:00)

### [완료된 작업]
- 중단된 카카오맵/UI 작업 재개를 위해 프로젝트 루트에서 `ls -R` 재스캔 수행.
- 카카오 네비/레이아웃 관련 변경 파일 점검 완료:
  - `Sources/Kakao/KakaoConfigStore.swift`
  - `Sources/Features/Navi/KakaoWebRouteMapView.swift`
  - `Sources/Features/Navi/KakaoNavigationPaneView.swift`
  - `Sources/Features/CarMode/CarModeView.swift`
  - `Sources/Features/Connection/ConnectionGuideView.swift`
- 빌드 검증 완료:
  - `xcodebuild -project TeslaSubDash.xcodeproj -scheme TeslaSubDash -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`
  - 결과: `BUILD SUCCEEDED`
- 기능 반영 상태 정리:
  - Kakao JavaScript Key 저장/로드 추가(Keychain)
  - Navi 탭에서 JS Key 존재 시 `WKWebView` 기반 Kakao 지도 렌더링
  - JS Key 미설정 시 Apple Map fallback 유지
  - 네비 메인 컨텐츠(지도/경로) 비중 확대, 검색/결과는 오버레이 패널로 축소
  - 우측 차량 정보/컨트롤 패널 폭 및 버튼 크기 축소(센터 컨텐츠 가시성 우선)

### [현재 상태]
- 카카오맵 연동 작업은 코드/빌드 기준으로 완료 상태.
- 워크트리에 미커밋 변경이 남아 있으며, 실제 iPad에서 시각 확인/튜닝만 남음.

### [다음 단계]
- iPad 실기기에서 Account -> Kakao:
  - REST Key 입력
  - JavaScript Key 입력
- Navi 탭에서 Kakao 지도 렌더링/경로 오버레이/검색 안정성 최종 확인.
- 필요 시 폰트/패딩/버튼 밀도 1회 추가 미세조정 후 커밋/푸시.

### [특이 사항]
- 빌드 로그에는 CoreSimulator 연결 경고가 있었으나 컴파일/링크 자체는 정상 통과함.

## 2026-02-11 (추가 업데이트 @20:06)

### [완료된 작업]
- 사용자 제공 맥미니 운영 구조(8787 토큰 보호)와 앱 연동을 위한 클라이언트 인증 반영 완료.
- 앱 설정 확장:
  - `Sources/Features/Shared/AppConfig.swift`
  - Keychain 기반 `backend.api.token` 저장/조회 추가
  - `Authorization`/`X-Api-Key` 헤더용 토큰 정규화 로직 추가
- 백엔드 호출 헤더 적용:
  - `Sources/Telemetry/TelemetryService.swift`
  - backend 모드 요청 시 자동으로
    - `Authorization: Bearer <token>`
    - `X-Api-Key: <token>`
    헤더 전송
- 연결 화면 UI 확장:
  - `Sources/Features/Connection/ConnectionGuideView.swift`
  - Backend API Token 입력/숨김/저장 버튼 추가
  - `probeBackendHealth`에도 동일 인증 헤더 적용
  - Quick backend 후보에 맥미니 주소 추가: `http://192.168.0.30:8787`
- 빌드 검증:
  - `xcodebuild -project TeslaSubDash.xcodeproj -scheme TeslaSubDash -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`
  - 결과: `BUILD SUCCEEDED`

### [현재 상태]
- iPad 앱이 토큰 보호된 맥미니 backend(8787)에 인증 헤더를 포함해 접근 가능한 상태.
- 남은 작업은 실기기에서 토큰 입력 후 연결 확인.

### [다음 단계]
- iPad 앱 Account(Setup)에서:
  - `Backend URL = http://192.168.0.30:8787`
  - `Backend API Token = <BACKEND_API_TOKEN>`
  - `Save URL`, `Save Token`, `Test Backend` 순서로 확인
- Car Mode 진입 후 Map/Navi/명령 버튼 동작 확인.

### [특이 사항]
- 서버 구현이 `/health`를 무인증으로 열어도 문제없고, 인증 요구로 바뀌어도 앱이 헤더를 보내도록 선반영됨.

## 2026-02-11 (추가 업데이트 @Tunnel handoff prep)

### [완료된 작업]
- Cloudflare Tunnel 연동 핸드오프 작성을 위해 iPad 앱/백엔드 호출 경로 재검증.
- 앱 측 확인:
  - `TelemetryService`가 backend 모드에서 `/api/vehicle/latest`, `/api/vehicle/command` 호출.
  - `Authorization` + `X-Api-Key` 헤더 자동 추가 로직 적용 상태 확인.
  - `AppConfig`에서 backend base URL override 및 backend token(Keychain) 저장/조회 가능 확인.
  - `ConnectionGuideView`에서 Backend URL + Backend API Token 입력/저장 UI 확인.
- 백엔드 측 확인:
  - 공개 health endpoint: `GET /health`
  - 앱 핵심 API: `GET /api/vehicle/latest`, `POST /api/vehicle/command`
  - 보조 API: `/api/teslamate/*`, `/api/vehicle/poll-now`, `/api/tesla/poll-now`

### [현재 상태]
- Cloudflare Tunnel 경유 외부 base URL(`https://tesla.splui.com`)로 앱 전환을 위한 정보 정리 완료.
- 실제 맥미니의 Zero Trust Public Hostname/Access 정책 적용 여부는 운영 환경에서 최종 확인 필요.

### [다음 단계]
- 운영자에게 전달할 최종 핸드오프(설정값/검증 커맨드/앱 입력값) 공유.
- 필요 시 Access(Service Token)까지 적용한 고보안 버전으로 앱 헤더 확장.

### [특이 사항]
- 현재 로컬 작업본 `backend/server.mjs`에서는 `/api/*` 인증 검증 코드는 직접 확인되지 않음.
- 맥미니 운영본에서 `BACKEND_API_TOKEN` 401 강제 여부는 반드시 실제 curl로 검증해야 함.

## 2026-02-11 (추가 업데이트 @21:45)

### [완료된 작업]
- 작업 재개 절차 준수:
  - 워크스페이스 루트에서 `ls -R` 재스캔.
  - `current_progress.md` 선확인 후 기존 다음 단계 기준으로 이어서 작업.
- Direct Fleet 디버깅 4개 항목 반영:
  1) `Test Vehicles` 최종 호출 URL 노출
  - `TeslaFleetService.testVehiclesDiagnostics()` 추가/활용.
  - 실제 요청 URL + 네트워크 경로 요약을 UI 상태 메시지에 출력.
  2) URLSession 에러 분기 강화
  - `TeslaFleetError.network(url:code:pathSummary:detail)` 경로에서
    - `URLError.timedOut`
    - `URLError.cannotFindHost`
    - `URLError.cannotConnectToHost`
    를 명시적으로 구분해 표시.
  3) Keychain 값 trim 강화
  - `TeslaAuthStore.loadConfig()`에서 `clientId/clientSecret/redirectURI/audience/fleetApiBase` 로드 시 공백/개행 제거 후 적용.
  4) NWPathMonitor 진단 로깅 추가
  - `FleetNetworkProbe` 추가:
    - path 상태 변경 시 `[fleet:path] ...` 로그 출력
    - `status/interface/ipv4/ipv6/dns/expensive/constrained` 스냅샷 제공
  - 모든 Fleet 요청에서 `[fleet:request] METHOD URL | path=...` 로그 출력.
- 빌드 검증 완료:
  - `xcodebuild -project TeslaSubDash.xcodeproj -scheme TeslaSubDash -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`
  - 결과: `BUILD SUCCEEDED`

### [현재 상태]
- Direct Fleet 진단 가시성이 강화됨.
- `Test Vehicles` 버튼으로 실제 호출 URL + 현재 네트워크 경로를 iPad UI에서 바로 확인 가능.
- 네트워크 실패 유형(timeout/DNS/host connect)을 UI에서 즉시 구분 가능.

### [다음 단계]
- iPad에서 Direct Fleet 모드로 `Test Vehicles` 실행 후 다음 2줄 확인:
  - `URL: https://.../api/1/vehicles`
  - `Network: status=... iface=... ipv4=... ipv6=... dns=...`
- 실패 시 표시되는 에러 코드(`timedOut/cannotFindHost/cannotConnectToHost`)와 함께 스크린샷 수집.
- 해당 결과를 기반으로 endpoint/네트워크/토큰 문제를 분리 진단.

### [특이 사항]
- 빌드 로그에 CoreSimulator 경고가 있었지만 최종 컴파일/링크는 정상 통과.

## 2026-02-11 (추가 업데이트 @21:55 안정성 패치)

### [완료된 작업]
- 사용자 보고 이슈 재현 신호 분석:
  - iPad 화면상 오류가 `URLError(-999)`(cancelled)로 반복 표시됨.
  - 이는 실제 서버 다운보다, 화면 전환/폴링 중 취소된 요청이 오류처럼 노출되는 문제에 가까움.
- 네트워크 취소 에러 무해화:
  - `TelemetryService.request()`에서 `URLError.cancelled`를 `CancellationError`로 변환.
  - `TeslaFleetService.requestWithMetadata()`에서도 동일 처리.
  - `CarModeViewModel`에서 `CancellationError` / `URLError.cancelled`는 무시하도록 적용.
- 폴링/UI 갱신 안정화:
  - `CarModeViewModel`에 snapshot 의미 변화 비교(`shouldReplaceSnapshot`) 추가.
  - 실질 변화가 없으면 snapshot 재할당을 피해서 불필요한 SwiftUI 재렌더 감소.
  - 반복 동일 오류 메시지 중복 노출 방지 및 오류 메시지 길이 제한(220자) 추가.
- 네비 렌더링 부하 완화:
  - `KakaoNavigationViewModel.updateVehicle()`에 좌표/속도 변화 임계치 적용(미세 변화 무시).
  - `KakaoWebRouteMapView`에 payload signature dedup 추가(동일 상태의 JS 재주입 차단).
  - WebView 준비 전 payload는 보류했다가 `didFinish` 후 1회 적용.
- UX 안전장치:
  - `ConnectionGuideView.saveBackendURL()` 실행 시 Telemetry Source를 자동으로 `Backend`로 전환.
  - `CarModeView` 에러 카드 텍스트 line limit 추가(긴 에러로 인한 레이아웃 부하 완화).
  - `TeslaFleetService.buildURL()`에서 Direct Fleet base 검증 강화:
    - `https` + `tesla.com` host가 아니면 명확한 misconfigured 안내 반환.
- 빌드 검증:
  - `xcodebuild -project TeslaSubDash.xcodeproj -scheme TeslaSubDash -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`
  - 결과: `BUILD SUCCEEDED`

### [현재 상태]
- `URLError(-999)`가 실제 장애처럼 계속 빨간 에러로 쌓이는 현상은 코드상 차단됨.
- 폴링/네비 지도 렌더링 시 불필요한 업데이트가 줄어 앱 멈춤 빈도 완화가 기대됨.

### [다음 단계]
- iPad 실기기에서 10~15분 연속 사용 확인:
  - Map/Navi 탭 전환 반복
  - 검색 입력 중 멈춤 여부
  - Wake/Refresh 반복 시 UI 프리즈 여부
- 여전히 프리즈가 남으면 Instruments(Time Profiler) 기준으로 `WKWebView`/`Map`/`SwiftUI diff` hot path 추가 추적.

### [특이 사항]
- 현재 워크트리는 기존 미커밋 변경이 많으므로, 이번 패치 커밋 시 파일 선택 커밋 권장.

## 2026-02-11 (추가 업데이트 @22:05 모달 프리즈 안정화)

### [완료된 작업]
- 작업 재개 절차 재확인:
  - 워크스페이스 루트 `ls -R` 재실행
  - `current_progress.md` 선확인 후 이어서 작업
- `CarModeView.swift` 컴파일 오류 수정:
  - 원인: `if/else` 뷰 블록에 직접 `.frame` 체인을 붙여 SwiftUI 타입 추론 실패
  - 조치: `Group { if ... }`로 감싼 뒤 `.frame(width: sideWidth)` 적용
- 빌드 재검증 완료:
  - `xcodebuild -project TeslaSubDash.xcodeproj -scheme TeslaSubDash -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`
  - 결과: `BUILD SUCCEEDED`

### [현재 상태]
- 계정 모달/세팅 시트 표시 중에도 크래시 없이 빌드 가능한 상태로 복구됨.
- 직전 안정화 패치(요청 취소 무시, 폴링 중지, 렌더 dedup)는 유지됨.

### [다음 단계]
- iPad 실기기에서 다음 재현 시나리오로 멈춤 여부 확인:
  - Car Mode 진입 -> Account 열기/닫기 반복
  - Account 열린 상태에서 20~30초 대기
  - Map/Navi 전환 후 검색 입력
- 동일 프리즈가 남으면 `showSetupSheet` 동안 center panel을 현재 placeholder 유지 vs 기존 live view 복귀를 토글 가능한 실험 플래그로 분리.

### [특이 사항]
- 워크트리는 원래부터 다수 파일이 dirty 상태이므로, 이후 커밋은 파일 선택 커밋 권장.

## 2026-02-11 (추가 업데이트 @22:35 TeslaMate 토큰 발급/연동 자동화)

### [완료된 작업]
- 작업 재개 절차 재확인:
  - 워크스페이스 루트 `ls -R` 재실행
  - `current_progress.md` 선확인 후 이어서 작업
- 백엔드 토큰 발급 흐름 보강:
  - 신규 파일 `backend/tesla_oauth_common.mjs` 추가
  - `code` 또는 `callback URL`에서 code를 안전하게 파싱하는 로직 추가
  - authorization code -> access/refresh token 교환 공통 함수 추가
- 기존 교환 스크립트 개선:
  - `backend/tesla_oauth_exchange_code.mjs`가 이제 `<code>` 뿐 아니라 `<full callback url>`도 입력 허용
- TeslaMate 런타임 토큰 주입 자동화 추가:
  - 신규 파일 `backend/teslamate_token_bridge.mjs` 추가
  - `docker exec <teslamate-container> /opt/app/bin/teslamate rpc ...`로 `TeslaMate.Auth.save(%{token, refresh_token})` + sign-in 수행
- 원클릭 교환+동기화 스크립트 추가:
  - 신규 파일 `backend/tesla_oauth_exchange_and_sync.mjs`
  - 기능: 토큰 교환 -> `.env` 저장 -> TeslaMate 런타임 세션 동기화
- npm 스크립트 추가:
  - `tesla:oauth:exchange:sync`
- 문서/가이드 업데이트:
  - `README.md`에 one-step 동기화 명령 추가
  - `pages/public/oauth/callback/index.html`의 안내 명령을 `tesla:oauth:exchange:sync` 기준으로 갱신
- 검증:
  - `node --check`로 신규/수정 스크립트 문법 통과 확인

### [현재 상태]
- 이제 callback URL 전체를 그대로 넣어도 백엔드에서 토큰 교환 가능.
- TeslaMate 컨테이너가 실행 중이면 토큰을 런타임에 바로 주입해 차량 수집 재개 경로까지 자동화됨.

### [다음 단계]
- 실제 실행:
  - `npm run tesla:oauth:exchange:sync -- "<callback_url_or_code>"`
- 실행 후 확인:
  - `curl http://127.0.0.1:8787/api/teslamate/status`
  - `curl http://127.0.0.1:8787/api/vehicle/latest`
- 컨테이너 이름이 다르면 `.env`에 `TESLAMATE_CONTAINER_NAME=<actual_name>` 추가.

### [특이 사항]
- TeslaMate 런타임 동기화는 로컬에 `docker`와 대상 컨테이너가 있어야 동작.
- 백엔드가 공개 인터넷에 열려 있어도 이번 자동화는 CLI 기반이라 외부 호출 엔드포인트를 추가하지 않음.

## 2026-02-11 (추가 업데이트 @22:42 GitHub push 완료)

### [완료된 작업]
- 토큰 발급/교환/테슬라메이트 런타임 동기화 관련 변경을 선택 커밋 후 GitHub `main`에 푸시.
- 커밋: `56a9c7f` (`feat: add one-step oauth exchange and teslamate runtime sync`)

### [현재 상태]
- 맥미니에서 `git pull` 후 `tesla:oauth:exchange:sync` 사용 가능.

### [다음 단계]
- 맥미니에서 최신 코드 pull -> backend 재시작 -> callback URL로 one-step 동기화 실행.

### [특이 사항]
- Swift UI 관련 로컬 변경 파일들은 아직 미커밋 상태로 유지됨(의도적 분리 커밋).

## 2026-02-11 (추가 업데이트 @22:50 Mac mini LLM handoff)

### [완료된 작업]
- 맥미니의 LLM(OpenClu 등)에 전달할 실행 지시문(복붙용) 작성 준비.
- 포함 범위: pull, 설치, 백엔드 재시작, OAuth 교환+TeslaMate 동기화, 헬스체크.

### [현재 상태]
- 서버 토큰 자동화 커밋(`56a9c7f`)은 `origin/main`에 반영 완료.

### [다음 단계]
- 사용자에게 맥미니 LLM용 최종 프롬프트 전달.

### [특이 사항]
- Swift UI 변경은 별도 미커밋 상태로 유지, 이번 핸드오프는 서버 운영 절차만 대상으로 함.

## 2026-02-12 (추가 업데이트 @TeslaMate 위치 누락 재발 대응)

### [완료된 작업]
- 작업 재개 절차 준수:
  - 프로젝트 루트 `ls -R` 재실행
  - `current_progress.md` 선확인 후 이어서 수정
- 백엔드 자동복구 로직 추가 (`backend/server.mjs`):
  - `TESLAMATE_API_BASE` 기본값을 `http://127.0.0.1:8080`으로 보강 (env 누락 시 즉시 크래시 방지)
  - TeslaMate fetch 실패 시 auth 실패 패턴 감지:
    - 401/403
    - no cars / not signed in / token/auth 관련 메시지
  - 감지 시 자동복구 수행:
    1) Fleet refresh token으로 access token 갱신
    2) `.env` 토큰 갱신 저장
    3) TeslaMate runtime token sync (`TeslaMate.Auth.save`)
    4) settle 후 TeslaMate fetch 재시도
  - cooldown + in-flight guard로 과도한 재시도 방지
  - `/health`에 auth repair 상태/설정 노출
  - 수동 트리거 endpoint 추가:
    - `POST /api/teslamate/repair-auth`
- 설정/문서 업데이트:
  - `backend/.env.example`에 auto-repair 변수 추가
  - `README.md` TeslaMate 섹션/검증 명령/API contract 갱신
  - `docs/architecture_notes.md`에 "Backend Auto Auth-Repair for TeslaMate" 반영

### [현재 상태]
- TeslaMate 모드에서 env 누락으로 바로 죽는 케이스가 완화됨.
- 토큰 만료/세션 이탈로 인한 위치 누락 재발 시 backend가 자동으로 self-heal 시도 가능.
- 운영자가 필요 시 `POST /api/teslamate/repair-auth`로 수동 복구 가능.

### [다음 단계]
- 맥미니에서 pull 후 실제 검증:
  1) `npm run backend:start:teslamate:lan`
  2) `curl http://127.0.0.1:8787/health` (authRepair 필드 확인)
  3) `curl http://127.0.0.1:8787/api/vehicle/latest`
  4) 필요 시 `curl -X POST http://127.0.0.1:8787/api/teslamate/repair-auth`
- 문제 재현 시 `/health`의 `teslaMateAuthRepairState` 값과 backend 로그를 같이 수집.

### [특이 사항]
- 자동복구는 `.env`의 `TESLA_CLIENT_ID` + `TESLA_USER_REFRESH_TOKEN` + Docker/TeslaMate 컨테이너 접근 가능성이 전제임.
- 근본적으로 TeslaMate upstream refresh endpoint 정합성 이슈가 남아 있으므로, 본 패치는 운영 안정화를 위한 방어층임.

## 2026-02-12 (추가 업데이트 @운영 기본 Backend URL 전환)

### [완료된 작업]
- 사용자 요청에 따라 앱 기본 backend URL을 로컬에서 운영 도메인으로 변경.
- 변경 파일:
  - `Config/Info.plist`
    - `BackendBaseURL`: `http://127.0.0.1:8787` -> `https://tesla.splui.com`
  - `Sources/Features/Shared/AppConfig.swift`
    - `defaultBackend`: `http://127.0.0.1:8787` -> `https://tesla.splui.com`
  - `Sources/Features/Connection/ConnectionGuideView.swift`
    - 빠른 후보 리스트 최상단에 `https://tesla.splui.com` 추가
  - `README.md`
    - 기본 backend URL 설명을 운영 도메인 기준으로 갱신

### [현재 상태]
- 신규 설치/초기 실행 시 앱은 기본적으로 `https://tesla.splui.com`를 backend로 사용.
- 기존에 저장된 `backend_base_url_override` 값이 있는 기기에서는 기존 override 값이 우선 적용됨.

### [다음 단계]
- iPad 앱에서 Account -> Backend URL 값이 과거 로컬 주소로 저장되어 있다면 `https://tesla.splui.com`로 바꾼 뒤 `Save URL`.
- 팀 공지 시 “내부 통신(TeslaMate API)은 `127.0.0.1:8080` 유지가 정상”임을 함께 안내.

### [특이 사항]
- 이번 변경은 앱의 기본 연결값/가이드 변경이며, 서버 비즈니스 로직에는 영향 없음.

## 2026-02-12 (추가 업데이트 @Kakao JS 지도/ TeslaMate 명령 호환 개선)

### [완료된 작업]
- 사용자 이슈 대응:
  1) Kakao JS 키를 넣어도 지도 blank
  2) TeslaMate 경유 차량 조작 실패
- 코드 수정:
  - `Sources/Features/Navi/KakaoWebRouteMapView.swift`
    - web map document base URL을 `https://tesla.splui.com`로 변경
    - 목적: Kakao JavaScript key의 Web domain 제한과 정합성 확보
  - `backend/server.mjs`
    - TeslaMate command alias 재시도 로직 추가:
      - `door_lock` -> `lock`
      - `door_unlock` -> `unlock`
      - `auto_conditioning_start` -> `climate_on`
      - `auto_conditioning_stop` -> `climate_off`
    - 404/unsupported 계열에서만 fallback 시도
  - `Sources/Features/Connection/ConnectionGuideView.swift`
    - Kakao JS key 설정 안내 문구에 `tesla.splui.com` Web domain 요구사항 명시
  - `README.md`
    - Kakao map blank 시 도메인 whitelist 확인 안내 추가
  - `docs/architecture_notes.md`
    - 해당 아키텍처/운영 변경 사항 기록
- 검증:
  - `node --check backend/server.mjs` 통과
  - `xcodebuild ... build` 결과 `BUILD SUCCEEDED`

### [현재 상태]
- Kakao JS map blank의 대표 원인(도메인 정합성) 대응 코드 반영.
- TeslaMate 명령 endpoint 구현 차이로 인한 command 미동작 가능성을 alias 재시도로 완화.

### [다음 단계]
- 맥미니/실기기 검증:
  1) Kakao Developers > JS key Web domain에 `tesla.splui.com` 등록 확인
  2) Navi 탭에서 하단 라벨이 `Map: Kakao`인지 확인
  3) Lock/Unlock/A/C 명령 테스트(응답 메시지에 mapped 안내 확인 가능)

### [특이 사항]
- 리스/DRIVER 권한/차량 상태(절전, command 제한) 이슈는 별도이며, alias 개선으로도 모두 해결되지는 않을 수 있음.

## 2026-02-12 (추가 요청 @15:15 Media overlay 리사이즈 UX)
- 요구: Media(인앱 웹) 오버레이가
  - 프리셋(S/M/L 등) 버튼 지원 +
  - 모서리 드래그(리사이즈 핸들)로 자유 리사이즈 가능
- 구현 메모:
  - 현재는 드래그 이동 + scale(핀치/버튼)만 있음 → 실제 frame(width/height) 변경은 고정이라 불편
  - 개선: width/height를 @State로 관리하고, 우하단 resize handle drag로 동적 변경
  - 프리셋 버튼은 width/height set + (필요 시) min/max clamp

## 2026-02-12 (프로세스/운영 룰 재강조 @15:19)
- 강제 운영 원칙:
  - (대부분의) 봇들은 텔레그램에서 대화 금지
  - 소통은 md(handoff) 파일로만 진행
  - md에 작업 내용 작성 완료 후, 텔레그램에는 **"완료!"** 단어 1개만 전송 가능
- 프로세스(필수):
  1) 김현호(대표) 오더
  2) 공영삼(팀장) 업무 분할 및 테스크 전달
  3) 각 봇(담당 테스크 진행)
  4) 완료 후 md 파일에 내용 정리
  5) 해당 작업 후 텔레그램에 "완료!"만 보내기
  6) 전체 내용 md파일에서 정리삼이 1차 요약 (정리삼도 md 작성 후 텔레그램엔 "완료!"만)
  7) 정리삼이 "완료!" 띄우면 공영삼(팀장)은 md 확인
     - 1차 요약을 더 간략/쉽게 정리해서 김현호에게 전달
     - 이 전달 과정에서 **빌드 업데이트(TestFlight 업로드) 필수**
- 개선 과제:
  - 현재 말이 없는 봇들의 원인(멘션-필요 설정/운영 룰 미인지/세션 문제)을 확인하고 프로세스에 맞게 동작하도록 수정

## 2026-02-12 (업로드 키 관련 운영 주의 @15:29)
- 사용자 요청: ASC 키를 공용 파일에 공유 요청.
- 보안 주의:
  - AuthKey_*.p8 / ASC key material은 **평문으로 md에 직접 붙여넣어 공유하면 위험** (유출/로그/스크린샷)
  - 권장: 키 파일은 안전한 비밀 저장소(1Password/Keychain/Secret Manager)에 보관하고,
    - 각 업로드 담당 환경(팀장 머신/CI)에는 env(ASC_KEY_ID/ASC_ISSUER_ID/ASC_KEY_PATH/APPLE_TEAM_ID)로만 주입
    - md에는 "키가 있음/어느 머신에서 업로드함/재현 명령" 같은 메타 정보만 기록

## 2026-02-12 (TestFlight 업로드 시도 상태 @15:31)
- 현 세션(ui) 기준: ASC 관련 env가 주입되지 않아 `fastlane ios beta`는 즉시 실패(ASC_KEY_ID missing).
- 관찰: `tesla-subdash-starter/fastlane/.env.asc` 파일이 없거나(또는 값이 비어) 업로드 재현이 불가한 상태로 보임.
- 해결 방향(보안 유지):
  - 키(p8) 내용을 md에 공유하지 말고,
  - 업로드가 되던 팀장 환경/CI에서만 `.env.asc` 또는 환경변수로 주입해 업로드 수행.
  - 이 머신에서 재현이 필요하면 `fastlane/.env.asc`에 다음 4개만 채워서(파일 권한 제한) 사용:
    - ASC_KEY_ID
    - ASC_ISSUER_ID
    - ASC_KEY_PATH (AuthKey_*.p8 절대경로)
    - APPLE_TEAM_ID

## 2026-02-12 (추가 업데이트 @18:52~23:22 쿠팡 코끼리 진행상황)
- Coupilot 레퍼런스 기반 랜딩 1차(UI): `coupang-elephant/app/page.tsx`
  - 헤더/히어로/CTA 구성 + `/recommend` 진입 링크 추가
- "돌아가게" MVP 기능(테스트용):
  - 분석 UI: `GET /analyze` + `POST /api/analyze`
  - 추천 UI: `GET /recommend`
    - 추천 생성: `POST /api/recommend` (MVP 룰 기반/결정적 정렬; mock 제거)
    - 추천 리스트 + 체크박스 선택 UI
    - 상단에 "선택 N개 업로드" 버튼
  - 배치 업로드 API: `/api/upload/batch`
    - **POST**: jobId 반환(비동기 job)
    - **GET**: jobId로 진행률/결과 조회
    - UI에서 polling으로 진행률 + 상품별 success/fail 표시
    - 추가: **idempotencyKey 지원(중복 클릭/재시도 시 동일 job 재사용)**
    - 추가: **실패 항목만 재시도 버튼**
- 배치 업로드 오류(대표 피드백) 대응 문서:
  - `docs/coupang_elephant_recommendation_fix_plan.md` (job/progress/idempotency 방향 포함)
  - 현재 job/progress/idempotency는 in-memory(MVP)라 서버 재시작시 초기화됨 → 다음 단계에서 Redis/DB로 승격 필요

### [배포/메인 도메인 관련(대표 요청 @23:30)]
- 메인: `https://app.splui.com/app/`
- 현재 이 Mac mini의 cloudflared 터널 설정:
  - `app.splui.com` → `http://localhost:3000`
- `localhost:3000`에서 실제로 떠 있는 서비스는 Next 프로토타입이 아니라,
  - `~/.openclaw/workspace/coupang-automation`의 `server.js`(express) + `public/app_shell.html` 입니다.
  - 즉, 메인 반영은 **coupang-automation 쪽 UI를 새 디자인으로 맞추는 작업**이 최단거리입니다.
- 즉시 조치(메인에 직접 반영되는 프론트 수정):
  - `coupang-automation/public/styles.css`의 컬러/배경/쉐도우를 신 디자인(fuchsia/pink) 톤으로 1차 변경
  - 버튼/포커스/상단바(sticky)/탭 active 그라데이션까지 신 디자인 톤으로 추가 반영
  - 작업 브랜치: `coupang-automation` repo `fix/preview-detail-v008`

### [다음 단계(속도/효과 우선)]
1) `app_shell.html`의 레이아웃/컴포넌트(버튼/카드/필)들을 신 디자인(192.168.0.31:3333 스타일)과 완전히 동일하게 리스킨
2) 메인 기능(발굴/분석/관리/업로드/추천/배치업로드 등) 라우팅/화면을 `app_shell` 안에서 정리(탭/사이드바/상단 네비)
3) 추천→복수선택 업로드는 현재 구현된 job/progress/idempotency/retry 흐름을 **메인 app_shell 흐름에 이식**
4) 필요 시 Next 기반으로 재구축(장기)하되, 단기엔 express+static UI로 빠르게 기능/디자인 동시 반영

## 2026-02-12 (추가 업데이트 @18:55 Backend 재시작 상태)
- `backend/server.mjs`는 현재 8787에서 실행 중(EADDRINUSE 확인됨: 이미 떠 있음)
- `GET http://127.0.0.1:8787/health` -> ok:true, mode=teslamate 응답 확인
- 참고: 이전 실행 세션이 SIGKILL 된 것은 도구 실행 타임아웃으로 프로세스가 강제 종료된 케이스. 실제 운영은 launchd/pm2 등으로 상시 실행 권장.
