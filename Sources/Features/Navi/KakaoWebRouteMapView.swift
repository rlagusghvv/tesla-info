import CoreLocation
import SwiftUI
import WebKit

struct KakaoWebRouteMapView: UIViewRepresentable {
    let javaScriptKey: String
    let vehicleCoordinate: CLLocationCoordinate2D?
    let vehicleSpeedKph: Double
    let route: KakaoRoute?

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
            polyline: route?.polyline ?? []
        )
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        // Kakao JS map key is domain-scoped (web platform). Use the app's public host as document base.
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
            // IMPORTANT: Kakao Maps JS SDK applies domain restrictions. Use our public host as document base.
            webView.loadHTMLString(html, baseURL: Self.mapDocumentBaseURL)
        }

        func pushState(to webView: WKWebView, vehicleCoordinate: CLLocationCoordinate2D?, speedKph: Double, polyline: [CLLocationCoordinate2D]) {
            guard !loadedKey.isEmpty else { return }

            let payload: [String: Any] = [
                "vehicle": vehicleCoordinate.map { ["lat": $0.latitude, "lon": $0.longitude] } as Any,
                "speedKph": speedKph,
                "polyline": polyline.map { ["lat": $0.latitude, "lon": $0.longitude] }
            ]
            let signature = payloadSignature(vehicleCoordinate: vehicleCoordinate, speedKph: speedKph, polyline: polyline)
            guard signature != lastPayloadSignature else { return }

            if !isPageReady {
                pendingPayload = payload
                return
            }

            push(payload: payload, signature: signature, to: webView)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isPageReady = true
            if let payload = pendingPayload {
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
                let signature = payloadSignature(vehicleCoordinate: vehicle, speedKph: speedKph, polyline: polyline)
                push(payload: payload, signature: signature, to: webView)
            }
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
            polyline: [CLLocationCoordinate2D]
        ) -> String {
            let vLat = vehicleCoordinate.map { String(format: "%.5f", $0.latitude) } ?? "nil"
            let vLon = vehicleCoordinate.map { String(format: "%.5f", $0.longitude) } ?? "nil"

            let first = polyline.first
            let middle = polyline.isEmpty ? nil : polyline[polyline.count / 2]
            let last = polyline.last

            let firstSig = pointSignature(first)
            let middleSig = pointSignature(middle)
            let lastSig = pointSignature(last)

            return "\(vLat),\(vLon)|\(polyline.count)|\(firstSig)|\(middleSig)|\(lastSig)"
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
                #status { position: fixed; left: 12px; bottom: 12px; right: 12px; padding: 10px 12px; border-radius: 12px; background: rgba(0,0,0,0.45); color: rgba(255,255,255,0.85); font: 12px -apple-system, system-ui, sans-serif; z-index: 9999; }
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
                let map = null;
                let carMarker = null;
                let routeLine = null;

                function ensureMap() {
                  if (map) return;
                  if (!(window.kakao && kakao.maps && kakao.maps.Map)) {
                    window.__setStatus('Kakao SDK not ready. Check: JS key is correct, domain tesla.splui.com is registered (Web platform), and the key is JavaScript key.');
                    return;
                  }
                  const center = new kakao.maps.LatLng(37.5665, 126.9780);
                  map = new kakao.maps.Map(document.getElementById('map'), {
                    center: center,
                    level: 6
                  });
                  window.__setStatus('Kakao map loaded');
                }

                // Render base map ASAP even before native state push.
                // This prevents a blank canvas when route/vehicle payload is delayed.
                window.addEventListener('load', () => {
                  try { ensureMap(); } catch (e) {}
                });

                function toLatLng(p) {
                  return new kakao.maps.LatLng(p.lat, p.lon);
                }

                let lastRouteSig = '';

                function routeSignature(points) {
                  if (!Array.isArray(points) || points.length < 2) return 'none';
                  const a = points[0];
                  const b = points[Math.floor(points.length / 2)];
                  const c = points[points.length - 1];
                  return [points.length,
                    a?.lat?.toFixed?.(5), a?.lon?.toFixed?.(5),
                    b?.lat?.toFixed?.(5), b?.lon?.toFixed?.(5),
                    c?.lat?.toFixed?.(5), c?.lon?.toFixed?.(5)
                  ].join('|');
                }

                window.__updateRouteMap = function(payload) {
                  ensureMap();
                  if (!map) return;

                  const points = Array.isArray(payload?.polyline) ? payload.polyline : [];
                  const vehicle = payload?.vehicle || null;

                  // Re-render route only when it actually changes.
                  const sig = routeSignature(points);
                  const routeChanged = sig !== lastRouteSig;

                  if (routeChanged) {
                    lastRouteSig = sig;
                    if (routeLine) {
                      routeLine.setMap(null);
                      routeLine = null;
                    }
                    if (points.length > 1) {
                      const path = points
                        .filter((p) => Number.isFinite(p.lat) && Number.isFinite(p.lon) && Math.abs(p.lat) <= 90 && Math.abs(p.lon) <= 180)
                        .map(toLatLng);
                      if (path.length > 1) {
                        routeLine = new kakao.maps.Polyline({
                          map: map,
                          path: path,
                          strokeWeight: 5,
                          strokeColor: '#3B82F6',
                          strokeOpacity: 0.95
                        });
                      }
                    }
                  }

                  // Update marker without recreating it every tick.
                  if (vehicle && Number.isFinite(vehicle.lat) && Number.isFinite(vehicle.lon)) {
                    const pos = toLatLng(vehicle);
                    if (!carMarker) {
                      carMarker = new kakao.maps.Marker({ position: pos });
                      carMarker.setMap(map);
                    } else {
                      carMarker.setPosition(pos);
                    }

                    // Follow vehicle (navigation-like). Keep a tighter zoom when guidance is active.
                    map.panTo(pos);
                    if (points.length > 1) {
                      map.setLevel(4); // zoom in
                    } else {
                      map.setLevel(6);
                    }
                  }

                  // On first route render, fit bounds once (then follow vehicle afterwards).
                  if (routeChanged && points.length > 1) {
                    const bounds = new kakao.maps.LatLngBounds();
                    let hasBounds = false;
                    points.forEach((p) => {
                      if (Number.isFinite(p.lat) && Number.isFinite(p.lon) && Math.abs(p.lat) <= 90 && Math.abs(p.lon) <= 180) {
                        bounds.extend(toLatLng(p));
                        hasBounds = true;
                      }
                    });
                    if (hasBounds) {
                      map.setBounds(bounds, 48, 48, 48, 48);
                    }
                  }
                };
              </script>
            </body>
            </html>
            """
        }
    }
}
