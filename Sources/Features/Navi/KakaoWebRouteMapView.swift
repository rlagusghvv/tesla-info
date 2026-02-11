import CoreLocation
import SwiftUI
import WebKit

struct KakaoWebRouteMapView: UIViewRepresentable {
    let javaScriptKey: String
    let vehicleCoordinate: CLLocationCoordinate2D?
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
            polyline: route?.polyline ?? []
        )
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
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
            webView.loadHTMLString(html, baseURL: URL(string: "https://dapi.kakao.com"))
        }

        func pushState(to webView: WKWebView, vehicleCoordinate: CLLocationCoordinate2D?, polyline: [CLLocationCoordinate2D]) {
            guard !loadedKey.isEmpty else { return }

            let payload: [String: Any] = [
                "vehicle": vehicleCoordinate.map { ["lat": $0.latitude, "lon": $0.longitude] } as Any,
                "polyline": polyline.map { ["lat": $0.latitude, "lon": $0.longitude] }
            ]
            let signature = payloadSignature(vehicleCoordinate: vehicleCoordinate, polyline: polyline)
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
                let polyline = (payload["polyline"] as? [[String: Any]] ?? []).compactMap { dict -> CLLocationCoordinate2D? in
                    guard
                        let lat = dict["lat"] as? Double,
                        let lon = dict["lon"] as? Double
                    else { return nil }
                    return CLLocationCoordinate2D(latitude: lat, longitude: lon)
                }
                let signature = payloadSignature(vehicleCoordinate: vehicle, polyline: polyline)
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
              </style>
              <script src="https://dapi.kakao.com/v2/maps/sdk.js?appkey=\(appKey)"></script>
            </head>
            <body>
              <div id="map"></div>
              <script>
                let map = null;
                let carMarker = null;
                let routeLine = null;

                function ensureMap() {
                  if (map) return;
                  const center = new kakao.maps.LatLng(37.5665, 126.9780);
                  map = new kakao.maps.Map(document.getElementById('map'), {
                    center: center,
                    level: 6
                  });
                }

                function toLatLng(p) {
                  return new kakao.maps.LatLng(p.lat, p.lon);
                }

                window.__updateRouteMap = function(payload) {
                  ensureMap();
                  if (!map) return;

                  const points = Array.isArray(payload?.polyline) ? payload.polyline : [];
                  const vehicle = payload?.vehicle || null;

                  if (routeLine) {
                    routeLine.setMap(null);
                    routeLine = null;
                  }

                  if (points.length > 1) {
                    const path = points.map(toLatLng);
                    routeLine = new kakao.maps.Polyline({
                      map: map,
                      path: path,
                      strokeWeight: 5,
                      strokeColor: '#3B82F6',
                      strokeOpacity: 0.95
                    });
                  }

                  if (carMarker) {
                    carMarker.setMap(null);
                    carMarker = null;
                  }

                  if (vehicle && Number.isFinite(vehicle.lat) && Number.isFinite(vehicle.lon)) {
                    const pos = toLatLng(vehicle);
                    carMarker = new kakao.maps.Marker({ position: pos });
                    carMarker.setMap(map);
                  }

                  const bounds = new kakao.maps.LatLngBounds();
                  let hasBounds = false;

                  if (points.length > 1) {
                    points.forEach((p) => {
                      if (Number.isFinite(p.lat) && Number.isFinite(p.lon)) {
                        bounds.extend(toLatLng(p));
                        hasBounds = true;
                      }
                    });
                  }

                  if (vehicle && Number.isFinite(vehicle.lat) && Number.isFinite(vehicle.lon)) {
                    bounds.extend(toLatLng(vehicle));
                    hasBounds = true;
                  }

                  if (hasBounds) {
                    map.setBounds(bounds, 48, 48, 48, 48);
                  }
                };
              </script>
            </body>
            </html>
            """
        }
    }
}
