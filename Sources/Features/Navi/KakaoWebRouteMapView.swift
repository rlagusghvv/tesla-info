import CoreLocation
import SwiftUI
import WebKit

struct KakaoWebRouteMapView: UIViewRepresentable {
    let javaScriptKey: String
    let vehicleCoordinate: CLLocationCoordinate2D?
    let vehicleSpeedKph: Double
    let route: KakaoRoute?
    let followEnabled: Bool
    let routeRevision: Int
    let zoomOffset: Int
    let zoomRevision: Int
    let followPulse: Int

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.navigationDelegate = context.coordinator

        context.coordinator.loadMapIfNeeded(on: webView, appKey: javaScriptKey)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let key = javaScriptKey.trimmingCharacters(in: .whitespacesAndNewlines)
        context.coordinator.loadMapIfNeeded(on: webView, appKey: key)
        context.coordinator.pushState(
            to: webView,
            vehicleCoordinate: vehicleCoordinate,
            speedKph: vehicleSpeedKph,
            polyline: route?.polyline ?? [],
            followEnabled: followEnabled,
            routeRevision: routeRevision,
            zoomOffset: zoomOffset,
            zoomRevision: zoomRevision,
            followPulse: followPulse
        )
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        // Kakao JS map key is domain-scoped (web platform). Use app public host as document base.
        private static let mapDocumentBaseURL = URL(string: "https://tesla.splui.com")

        private var loadedKey: String = ""
        private var isPageReady = false
        private var pendingPayload: [String: Any]?
        private var lastPayloadSignature = ""

        func loadMapIfNeeded(on webView: WKWebView, appKey: String) {
            let key = appKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return }
            guard loadedKey != key else { return }
            loadedKey = key
            isPageReady = false
            pendingPayload = nil
            lastPayloadSignature = ""

            let html = Self.htmlTemplate(appKey: key)
            // Kakao Maps JS SDK applies domain restrictions.
            webView.loadHTMLString(html, baseURL: Self.mapDocumentBaseURL)
        }

        func pushState(
            to webView: WKWebView,
            vehicleCoordinate: CLLocationCoordinate2D?,
            speedKph: Double,
            polyline: [CLLocationCoordinate2D],
            followEnabled: Bool,
            routeRevision: Int,
            zoomOffset: Int,
            zoomRevision: Int,
            followPulse: Int
        ) {
            guard !loadedKey.isEmpty else { return }

            let payload: [String: Any] = [
                "vehicle": vehicleCoordinate.map { ["lat": $0.latitude, "lon": $0.longitude] } as Any,
                "speedKph": speedKph,
                "polyline": polyline.map { ["lat": $0.latitude, "lon": $0.longitude] },
                "follow": followEnabled,
                "routeRevision": routeRevision,
                "zoomOffset": zoomOffset,
                "zoomRevision": zoomRevision,
                "followPulse": followPulse
            ]

            let signature = payloadSignature(
                vehicleCoordinate: vehicleCoordinate,
                speedKph: speedKph,
                polyline: polyline,
                followEnabled: followEnabled,
                routeRevision: routeRevision,
                zoomOffset: zoomOffset,
                zoomRevision: zoomRevision,
                followPulse: followPulse
            )
            guard signature != lastPayloadSignature else { return }

            if !isPageReady {
                pendingPayload = payload
                return
            }

            push(payload: payload, signature: signature, to: webView)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isPageReady = true
            guard let payload = pendingPayload else { return }
            pendingPayload = nil

            let vehicle = (payload["vehicle"] as? [String: Any]).flatMap { dict -> CLLocationCoordinate2D? in
                guard
                    let lat = dict["lat"] as? Double,
                    let lon = dict["lon"] as? Double
                else { return nil }
                return CLLocationCoordinate2D(latitude: lat, longitude: lon)
            }

            let speedKph = payload["speedKph"] as? Double ?? 0
            let polyline = (payload["polyline"] as? [[String: Any]] ?? []).compactMap { dict -> CLLocationCoordinate2D? in
                guard
                    let lat = dict["lat"] as? Double,
                    let lon = dict["lon"] as? Double
                else { return nil }
                return CLLocationCoordinate2D(latitude: lat, longitude: lon)
            }

            let follow = payload["follow"] as? Bool ?? true
            let routeRevision = payload["routeRevision"] as? Int ?? 0
            let zoomOffset = payload["zoomOffset"] as? Int ?? 0
            let zoomRevision = payload["zoomRevision"] as? Int ?? 0
            let followPulse = payload["followPulse"] as? Int ?? 0
            let signature = payloadSignature(
                vehicleCoordinate: vehicle,
                speedKph: speedKph,
                polyline: polyline,
                followEnabled: follow,
                routeRevision: routeRevision,
                zoomOffset: zoomOffset,
                zoomRevision: zoomRevision,
                followPulse: followPulse
            )
            push(payload: payload, signature: signature, to: webView)
        }

        private func push(payload: [String: Any], signature: String, to webView: WKWebView) {
            guard
                let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
                let json = String(data: data, encoding: .utf8)
            else {
                return
            }

            let script = "window.__updateRouteMap(\(json));"
            webView.evaluateJavaScript(script) { _, _ in
                // Ignore occasional timing errors while Kakao SDK is still loading.
            }
            lastPayloadSignature = signature
        }

        private func payloadSignature(
            vehicleCoordinate: CLLocationCoordinate2D?,
            speedKph: Double,
            polyline: [CLLocationCoordinate2D],
            followEnabled: Bool,
            routeRevision: Int,
            zoomOffset: Int,
            zoomRevision: Int,
            followPulse: Int
        ) -> String {
            let vLat = vehicleCoordinate.map { String(format: "%.5f", $0.latitude) } ?? "nil"
            let vLon = vehicleCoordinate.map { String(format: "%.5f", $0.longitude) } ?? "nil"

            let first = polyline.first
            let middle = polyline.isEmpty ? nil : polyline[polyline.count / 2]
            let last = polyline.last

            let firstSig = pointSignature(first)
            let middleSig = pointSignature(middle)
            let lastSig = pointSignature(last)
            let speedSig = String(format: "%.1f", speedKph)

            return "\(vLat),\(vLon)|\(speedSig)|\(polyline.count)|\(firstSig)|\(middleSig)|\(lastSig)|f=\(followEnabled)|r=\(routeRevision)|z=\(zoomOffset)|zr=\(zoomRevision)|p=\(followPulse)"
        }

        private func pointSignature(_ point: CLLocationCoordinate2D?) -> String {
            guard let point else { return "nil" }
            return String(format: "%.5f,%.5f", point.latitude, point.longitude)
        }

        private static func htmlTemplate(appKey: String) -> String {
            """
            <!doctype html>
            <html>
            <head>
              <meta charset="utf-8" />
              <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0" />
              <style>
                html, body, #map { margin:0; padding:0; width:100%; height:100%; background:#0d1320; }
                #status {
                  position: fixed;
                  left: 12px;
                  bottom: 12px;
                  right: 12px;
                  padding: 10px 12px;
                  border-radius: 12px;
                  background: rgba(0,0,0,0.45);
                  color: rgba(255,255,255,0.85);
                  font: 12px -apple-system, system-ui, sans-serif;
                  z-index: 9999;
                }
              </style>
              <script>
                window.__setStatus = function(msg) {
                  const el = document.getElementById('status');
                  if (el) el.textContent = msg;
                }
              </script>
              <script src="https://dapi.kakao.com/v2/maps/sdk.js?appkey=\(appKey)" onerror="window.__setStatus('Failed to load Kakao Maps SDK (check JS key + allowed domains)');"></script>
            </head>
            <body>
              <div id="map"></div>
              <div id="status">Loading Kakao map…</div>
              <script>
                let mapState = {
                  map: null,
                  carMarker: null,
                  routeLine: null,
                  lastVehicle: null,
                  lastFollowPulse: -1,
                  fittedRouteRevision: -1,
                  lastRouteSig: ''
                };

                const NAV_LEVEL = 3;
                const CRUISE_LEVEL = 4;
                const IDLE_LEVEL = 6;
                const RECENTER_METERS = 6;
                const MIN_LEVEL = 1;
                const MAX_LEVEL = 9;

                function isValidPoint(p) {
                  return Number.isFinite(p?.lat)
                    && Number.isFinite(p?.lon)
                    && Math.abs(p.lat) <= 90
                    && Math.abs(p.lon) <= 180;
                }

                function ensureMap() {
                  if (mapState.map) return;
                  if (!(window.kakao && kakao.maps && kakao.maps.Map)) {
                    window.__setStatus('Kakao SDK not ready. Check JS key and tesla.splui.com domain registration.');
                    return;
                  }

                  const center = new kakao.maps.LatLng(37.5665, 126.9780);
                  mapState.map = new kakao.maps.Map(document.getElementById('map'), {
                    center: center,
                    level: IDLE_LEVEL
                  });
                  window.__setStatus('Kakao map loaded');
                }

                window.addEventListener('load', () => {
                  try { ensureMap(); } catch (_) {}
                });

                function toLatLng(p) {
                  return new kakao.maps.LatLng(p.lat, p.lon);
                }

                function distanceMeters(a, b) {
                  const R = 6371000.0;
                  const toRad = Math.PI / 180.0;
                  const dLat = (b.lat - a.lat) * toRad;
                  const dLon = (b.lon - a.lon) * toRad;
                  const lat1 = a.lat * toRad;
                  const lat2 = b.lat * toRad;
                  const s1 = Math.sin(dLat / 2);
                  const s2 = Math.sin(dLon / 2);
                  const h = (s1 * s1) + (Math.cos(lat1) * Math.cos(lat2) * s2 * s2);
                  return 2 * R * Math.asin(Math.min(1, Math.sqrt(h)));
                }

                function routeSignature(points) {
                  if (!Array.isArray(points) || points.length < 2) return 'none';
                  const a = points[0];
                  const b = points[Math.floor(points.length / 2)];
                  const c = points[points.length - 1];
                  return [
                    points.length,
                    a?.lat?.toFixed?.(5), a?.lon?.toFixed?.(5),
                    b?.lat?.toFixed?.(5), b?.lon?.toFixed?.(5),
                    c?.lat?.toFixed?.(5), c?.lon?.toFixed?.(5)
                  ].join('|');
                }

                window.__updateRouteMap = function(payload) {
                  ensureMap();
                  if (!mapState.map) return;

                  const rawPoints = Array.isArray(payload?.polyline) ? payload.polyline : [];
                  const points = rawPoints.filter(isValidPoint);
                  const vehicle = isValidPoint(payload?.vehicle) ? payload.vehicle : null;
                  const speedKph = Number.isFinite(payload?.speedKph) ? payload.speedKph : 0;
                  const follow = payload?.follow !== false;
                  const routeRevision = Number.isFinite(payload?.routeRevision) ? payload.routeRevision : 0;
                  const zoomOffset = Number.isFinite(payload?.zoomOffset) ? payload.zoomOffset : 0;
                  const followPulse = Number.isFinite(payload?.followPulse) ? payload.followPulse : 0;
                  const hasRoute = points.length > 1;

                  const sig = routeSignature(points);
                  const routeChanged = sig !== mapState.lastRouteSig;

                  if (routeChanged) {
                    mapState.lastRouteSig = sig;

                    if (mapState.routeLine) {
                      mapState.routeLine.setMap(null);
                      mapState.routeLine = null;
                    }

                    if (hasRoute) {
                      mapState.routeLine = new kakao.maps.Polyline({
                        map: mapState.map,
                        path: points.map(toLatLng),
                        strokeWeight: 5,
                        strokeColor: '#3B82F6',
                        strokeOpacity: 0.95
                      });
                    } else {
                      mapState.fittedRouteRevision = -1;
                    }
                  }

                  if (vehicle) {
                    const pos = toLatLng(vehicle);
                    if (!mapState.carMarker) {
                      mapState.carMarker = new kakao.maps.Marker({ position: pos });
                      mapState.carMarker.setMap(mapState.map);
                    } else {
                      mapState.carMarker.setPosition(pos);
                    }
                  } else if (mapState.carMarker) {
                    mapState.carMarker.setMap(null);
                    mapState.carMarker = null;
                  }

                  if (hasRoute && mapState.routeLine && mapState.fittedRouteRevision !== routeRevision) {
                    const bounds = new kakao.maps.LatLngBounds();
                    points.forEach((p) => bounds.extend(toLatLng(p)));
                    if (vehicle) {
                      bounds.extend(toLatLng(vehicle));
                    }
                    mapState.map.setBounds(bounds, 56, 56, 56, 56);
                    mapState.fittedRouteRevision = routeRevision;
                  }

                  if (follow && vehicle) {
                    const target = toLatLng(vehicle);
                    const baseLevel = hasRoute ? NAV_LEVEL : CRUISE_LEVEL;
                    const level = Math.max(MIN_LEVEL, Math.min(MAX_LEVEL, baseLevel + zoomOffset));
                    const pulseChanged = followPulse !== mapState.lastFollowPulse;
                    if (mapState.map.getLevel() !== level) {
                      mapState.map.setLevel(level, { animate: { duration: 220 } });
                    }

                    if (!mapState.lastVehicle || pulseChanged) {
                      mapState.map.setCenter(target);
                    } else {
                      const moved = distanceMeters(mapState.lastVehicle, vehicle);
                      const recenterThreshold = speedKph > 30 ? RECENTER_METERS : 4;
                      if (moved >= recenterThreshold) {
                        mapState.map.panTo(target);
                      }
                    }
                    mapState.lastVehicle = { lat: vehicle.lat, lon: vehicle.lon };
                    mapState.lastFollowPulse = followPulse;
                  } else if (!vehicle) {
                    mapState.lastVehicle = null;
                    mapState.lastFollowPulse = -1;
                  }

                  const mode = follow ? 'FOLLOW' : 'FREE';
                  if (hasRoute) {
                    window.__setStatus(`Route ${points.length}pts · ${mode} · ${Math.round(speedKph)}km/h`);
                  } else {
                    window.__setStatus(`Map ready · ${mode} · ${Math.round(speedKph)}km/h`);
                  }
                };
              </script>
            </body>
            </html>
            """
        }
    }
}
