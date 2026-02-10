# Step 1) Feasibility Report (Apple Policy + Technical Constraints)

Assumed environment from your answers:
- iPad mini 6 (update to latest iPadOS)
- iPhone + iPad are on the same Apple ID
- iPhone Personal Hotspot is already enabled
- iPhone is always connected to Tesla Bluetooth

## A-D yes/no verdicts

| Item | Verdict | Why | Practical workaround |
|---|---|---|---|
| A) Can a third-party app turn Wi-Fi on/off? | **No** | Apple provides no public API for general Wi-Fi radio control. Wi-Fi control remains a system-level user action. | Keep Wi-Fi always on. Optimize the flow so users do not need to touch Wi-Fi controls in-car. |
| B) Can a third-party app force-connect to a specific Wi-Fi (including iPhone hotspot)? | **No** (force) / **Partial** (guided join) | `Wi-Fi Configuration API` can apply known SSID configs, but this is not unrestricted force-join and requires user authorization flow. For iPhone hotspot, the stable path is Apple Continuity (`Instant Hotspot` + Auto-Join settings), not app-forced connection. | Use **Instant Hotspot + Auto-Join Hotspot** in iPad settings as the default. Provide one-tap shortcut fallback when needed. |
| C) Can the app auto-run in background triggered by network state changes? | **No** (app auto-launch) | iPadOS does not provide a general "network changed -> launch this third-party app" trigger for arbitrary apps. | Use Shortcuts automation trigger (Wi-Fi/Bluetooth/CarPlay) where available and set to run immediately, then open deep link `myapp://car`. |
| D) Can CarPlay be auto-executed/auto-switched for this app? | **No** (for this use-case) | CarPlay apps require Apple-approved categories and entitlements. A generic Tesla sub-cluster dashboard app does not fit standard CarPlay app categories. Auto-switch by app code is not available. | Use iPad standalone car mode UI with large controls, plus shortcut automation on iPad/iPhone. |

## Source references (official/primary)

1. Apple Technote, iOS Wi-Fi API overview (no general-purpose Wi-Fi control):
   - https://developer.apple.com/documentation/technotes/tn3111-ios-wifi-api-overview
2. Apple NetworkExtension, Wi-Fi Configuration API (known SSID config and user authorization behavior):
   - https://developer.apple.com/documentation/networkextension/wifi-configuration-api
3. Apple Support, Instant Hotspot:
   - https://support.apple.com/guide/iphone/use-instant-hotspot-iph3d039b3c/ios
4. Apple Support, Join a Personal Hotspot:
   - https://support.apple.com/guide/iphone/iph45447ca6/ios
5. Apple Support, Personal Automations in Shortcuts:
   - https://support.apple.com/guide/shortcuts/about-personal-automations-apd690170742/ios
6. Apple Support, Intro to CarPlay:
   - https://support.apple.com/guide/iphone/iph6860e6b53/ios
7. Apple Developer, CarPlay overview and entitlement categories:
   - https://developer.apple.com/carplay/

Notes:
- C/D include a small amount of engineering inference from Apple platform behavior and entitlement boundaries, based on the above references.

---

# Step 2) Recommended UX (0-1 tap goal)

## All candidate options reviewed

- **A) iPadOS settings-based auto-connect**
  - Strength: lowest friction, most stable, no extra app permissions.
  - Weakness: depends on Continuity conditions and hotspot discoverability timing.
- **B) Shortcuts-based launcher**
  - Strength: can feel automatic after one-time setup, gives deterministic fallback.
  - Weakness: automation behavior can vary by trigger and OS policy.
- **C) In-app network monitor + auto-routing**
  - Strength: once app is opened, transition to Car Mode is immediate and deterministic.
  - Weakness: cannot wake app from fully terminated state by network event alone.
- **D) CarPlay-native extension**
  - Strength: native in-car UX if category-entitled.
  - Weakness: not suitable for this product category and not a practical path here.

## Recommended single approach

**Recommendation: A + C as the primary path, with B as fallback (best real-world 0-1 tap).**

Why this is best for your setup:
- You already satisfy key prerequisites (same Apple ID, hotspot enabled, car Bluetooth usage).
- A handles near-zero-touch connectivity.
- C gives immediate auto-switch to Car Mode when network becomes available.
- B provides low-friction recovery if A timing fails in edge cases.

## Primary user flow

1. User enters vehicle.
2. iPad auto-joins iPhone hotspot via Instant Hotspot/Auto-Join.
3. App opens (manually once, or via shortcut) and detects network via `NWPathMonitor`.
4. App auto-routes to **Car Mode** screen with large controls.

## Alternative 1

- **B-heavy flow**: Home-screen shortcut "Start Car Mode" opens `myapp://car` directly.
- Good when user wants deterministic one-tap start every time.

## Alternative 2

- **C-only flow**: App pinned on dock, user taps app icon once.
- App either jumps straight to Car Mode (connected) or shows 3-step hotspot guide.

