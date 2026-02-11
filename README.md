# TeslaSubDash MVP (iPad + Telemetry Backend)

This MVP is designed for your current hardware:
- iPad mini 6 (Wi-Fi)
- iPhone hotspot for internet
- no additional paid SDK

It includes:
- iPad SwiftUI dashboard with **one side panel + center pane**
- local backend for telemetry snapshot + command endpoints
- simulator mode (no Tesla credential needed)
- Tesla Fleet poll mode (optional)

## MVP: iPad-only (no Mac backend)

This mode lets the iPad app talk to Tesla Fleet API directly (no local backend needed).

1) Ensure your OAuth callback page is deployed (Cloudflare Pages)

- Callback page file: `pages/public/oauth/callback/index.html`
- Tesla dashboard Redirect URI:
  - `https://www.splui.com/oauth/callback`

2) On iPad (one-time)

- Open the app > `Tesla Account`
- Paste `Client ID` + `Client Secret` (from Tesla Developer Dashboard)
- Keep `Redirect URI` as `https://www.splui.com/oauth/callback`
- Tap `Save` > `Connect`
- After login, Safari should prompt to open the app (deep link).
- If deep link fails, expand `Manual Finish` and paste `code` + `state` from the callback page, then tap `Exchange Code`.

3) Daily use

- Turn on iPhone Personal Hotspot (Auto-Join Hotspot: Automatic on iPad)
- Open the app (or run the Shortcut)
- If internet is connected, it auto-enters Car Mode.

Security note: this MVP stores your Tesla client secret and tokens in iOS Keychain (not suitable for public distribution).
Navigation note: in-app destination search/routing uses a Kakao REST API key stored in iOS Keychain (also not suitable for public distribution).

## Folder tree

```text
tesla-subdash-starter/
├─ backend/
│  ├─ .env.example
│  └─ server.mjs
├─ Config/
│  └─ Info.plist
├─ Sources/
│  ├─ App/
│  │  ├─ AppRouter.swift
│  │  ├─ LaunchFlags.swift
│  │  ├─ RootRouterView.swift
│  │  └─ TeslaSubDashApp.swift
│  ├─ Core/
│  │  └─ NetworkMonitor.swift
│  ├─ Features/
│  │  ├─ CarMode/
│  │  │  ├─ CarModeView.swift
│  │  │  ├─ CarModeViewModel.swift
│  │  │  └─ TelemetryMapView.swift
│  │  ├─ Navi/
│  │  │  ├─ KakaoNavigationPaneView.swift
│  │  │  ├─ KakaoNavigationViewModel.swift
│  │  │  └─ KakaoRouteMapView.swift
│  │  ├─ Common/
│  │  │  └─ ButtonStyles.swift
│  │  ├─ Connection/
│  │  │  └─ ConnectionGuideView.swift
│  │  └─ Shared/
│  │     ├─ AppConfig.swift
│  │     └─ InAppBrowserView.swift
│  ├─ Intents/
│  │  └─ StartCarModeIntent.swift
│  ├─ Kakao/
│  │  ├─ KakaoAPIClient.swift
│  │  ├─ KakaoConfigStore.swift
│  │  └─ KakaoModels.swift
│  └─ Telemetry/
│     ├─ TelemetryModels.swift
│     └─ TelemetryService.swift
├─ POLICY_AND_UX_REPORT.md
├─ package.json
└─ README.md
```

## 1) Run backend (simulator mode)

```bash
cd "/Users/kimhyeonho/tesla info/tesla-subdash-starter"
npm run backend:start:sim
```

Check health:

```bash
curl http://127.0.0.1:8787/health
curl http://127.0.0.1:8787/api/vehicle/latest
```

## 2) Run backend (Tesla mode, optional)

You need a **Tesla user token** (authorization code flow) to access your personal vehicle.

Set env values first:

```bash
cd "/Users/kimhyeonho/tesla info/tesla-subdash-starter"
npm run backend:setup:tesla
```

### 2.1) Host the public key + callback page

- Public key path required by Tesla:
  - `/.well-known/appspecific/com.tesla.3p.public-key.pem`
- This repo includes a ready-to-host folder:
  - `pages/public/`

You must host `pages/public/` on an HTTPS domain you control, then set:

- `TESLA_DOMAIN` to that domain host (example: `subdash.example.com`)
- `TESLA_REDIRECT_URI` to `https://<TESLA_DOMAIN>/oauth/callback`

### 2.2) Register partner domain (one-time)

```bash
npm run tesla:partner:register
```

### 2.3) Generate a user token (login + code exchange)

Start OAuth and open the printed URL:

```bash
npm run tesla:oauth:start
```

After Tesla login, you will land on `/oauth/callback` and see a `code`.
Exchange the code:

```bash
npm run tesla:oauth:exchange -- <PASTE_CODE_HERE>
```

If you are using TeslaMate and want one-step runtime sync too:

```bash
npm run tesla:oauth:exchange:sync -- "<FULL_CALLBACK_URL_OR_CODE>"
```

Verify token and vehicle list:

```bash
npm run backend:check:tesla
```

Run:

```bash
USE_SIMULATOR=0 POLL_TESLA=1 npm run backend:start:tesla
```

Optional checks:

```bash
curl http://127.0.0.1:8787/api/tesla/vehicles
curl -X POST http://127.0.0.1:8787/api/tesla/poll-now
```

### 2.4) Run backend (TeslaMate fallback mode)

If Fleet location is blocked (for example `DRIVER` access), use TeslaMate as a temporary location source.

Set env values in `.env`:

```bash
TESLAMATE_API_BASE=https://<your-teslamate-api-base>
TESLAMATE_API_TOKEN=<optional-token>
TESLAMATE_CAR_ID=<optional-car-id>
# Optional auth customization:
# TESLAMATE_AUTH_HEADER=Authorization
# TESLAMATE_TOKEN_QUERY_KEY=api_key
```

Run:

```bash
npm run backend:start:teslamate
```

LAN mode (for physical iPad):

```bash
npm run backend:start:teslamate:lan
```

Quick checks:

```bash
curl http://127.0.0.1:8787/health
curl http://127.0.0.1:8787/api/teslamate/cars
curl http://127.0.0.1:8787/api/vehicle/latest
```

## 3) Connect iPad app to backend

- In `Config/Info.plist`, `BackendBaseURL` is defaulted to `http://127.0.0.1:8787`.
- For physical iPad testing, start backend in LAN mode so it can accept connections:
  - `npm run backend:start:tesla:lan` (Fleet)
  - `npm run backend:start:teslamate:lan` (TeslaMate fallback)
  - It will print `http://<LAN_IP>:8787` candidates. Use the one that matches your current network (home Wi-Fi or iPhone hotspot).
- You can also change backend URL in-app:
  - Open `Connection Guide` screen
  - Set `Telemetry Source` to `Backend`
  - Use `Backend URL` field
  - Tap `Save URL` and `Test Backend`, then re-enter Car Mode
 - If prompted, allow `Local Network` access on iPad (Settings > TeslaSubDash > Local Network).

## 4) Build app in Xcode

1. Open `TeslaSubDash.xcodeproj`.
2. Select your simulator or iPad.
3. Build and run.

## Implemented UX in Car Mode

- Side panel: speed/battery/range/lock/climate/location + command buttons
- Center panel:
  - `Map` mode: vehicle location marker (Fleet API)
  - `Navi` mode: in-app destination search + route overlay (Kakao APIs)
  - `Media` mode: YouTube/CHZZK in-app browser
- Command result/error message shown inline

## API contract (MVP)

- `GET /health`
- `GET /api/vehicle/latest`
- `GET /api/tesla/vehicles` (fleet token required)
- `GET /api/teslamate/cars` (teslamate mode only)
- `GET /api/teslamate/status` (teslamate mode only)
- `POST /api/vehicle/command` body: `{ "command": "door_lock" }`
- `POST /api/telemetry/ingest` body: partial vehicle telemetry patch
- `POST /api/tesla/poll-now` (fleet/teslamate mode)
- `POST /api/vehicle/poll-now` (fleet/teslamate mode, generic)

## Quick ingest test

```bash
curl -X POST http://127.0.0.1:8787/api/telemetry/ingest \
  -H "Content-Type: application/json" \
  -d '{
    "vehicle": {
      "speedKph": 88,
      "batteryLevel": 74,
      "location": {"lat": 37.5665, "lon": 126.9780}
    }
  }'
```

## Test checklist

- [ ] Backend simulator starts and returns `/api/vehicle/latest`
- [ ] App opens Car Mode when network connected
- [ ] Map marker moves when simulator ticks or ingest payload arrives
- [ ] Command buttons return success in simulator mode
- [ ] Switching to Tesla mode still serves latest snapshot
- [ ] `GET /api/tesla/vehicles` works with your token
- [ ] Shortcuts `Start Car Mode` action opens app and enters Car Mode

## Notes

- ATS is relaxed (`NSAllowsArbitraryLoads=true`) for local HTTP MVP only.
- Backend auto-loads `.env` from project root if present.
- Never commit `.env` (contains private Tesla token).
- For production, migrate backend to HTTPS and tighten ATS policy.
- Some Tesla commands may require additional signing/proxy setup depending on account and endpoint policy.
