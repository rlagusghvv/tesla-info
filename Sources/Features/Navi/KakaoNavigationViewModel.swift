import CoreLocation
import Foundation

@MainActor
final class KakaoNavigationViewModel: ObservableObject {
    @Published var query: String = ""
    @Published private(set) var results: [KakaoPlace] = []
    @Published private(set) var route: KakaoRoute?
    @Published private(set) var isSearching = false
    @Published private(set) var isRouting = false
    @Published var errorMessage: String?

    @Published private(set) var vehicleCoordinate: CLLocationCoordinate2D?
    @Published private(set) var vehicleSpeedKph: Double = 0

    private var cachedKey: String = ""
    private var cachedClient: KakaoAPIClient?

    func updateVehicle(location: VehicleLocation, speedKph: Double) {
        let nextCoordinate = location.isValid ? location.coordinate : nil
        let coordinateChanged = hasCoordinateChanged(current: vehicleCoordinate, next: nextCoordinate)
        let speedChanged = abs(vehicleSpeedKph - speedKph) >= 0.3
        guard coordinateChanged || speedChanged else { return }

        vehicleCoordinate = nextCoordinate
        vehicleSpeedKph = speedKph
    }

    func clearRoute() {
        route = nil
        errorMessage = nil
    }

    func searchPlaces(restAPIKey: String, near: CLLocationCoordinate2D?) async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            results = []
            return
        }

        isSearching = true
        errorMessage = nil
        defer { isSearching = false }

        do {
            let places = try await client(restAPIKey: restAPIKey).searchPlaces(query: q, near: near)
            results = rankPlaces(places, query: q, near: near)
        } catch {
            results = []
            errorMessage = error.localizedDescription
        }
    }

    func startRoute(restAPIKey: String, origin: CLLocationCoordinate2D, destination: CLLocationCoordinate2D) async {
        isRouting = true
        errorMessage = nil
        defer { isRouting = false }

        do {
            let r = try await client(restAPIKey: restAPIKey).fetchRoute(origin: origin, destination: destination)
            route = r
        } catch {
            route = nil
            errorMessage = error.localizedDescription
        }
    }

    var nextGuide: KakaoGuide? {
        guard let route else { return nil }
        guard let vehicleCoordinate else { return route.guides.first }

        var bestAny: KakaoGuide?
        var bestAnyDistance = Double.greatestFiniteMagnitude

        var bestAhead: KakaoGuide?
        var bestAheadDistance = Double.greatestFiniteMagnitude

        for g in route.guides {
            let d = distanceMeters(vehicleCoordinate, g.coordinate)
            if d < bestAnyDistance {
                bestAnyDistance = d
                bestAny = g
            }

            // Simple heuristic: ignore guides that are basically "already passed".
            if d > 25, d < bestAheadDistance {
                bestAheadDistance = d
                bestAhead = g
            }
        }

        return bestAhead ?? bestAny ?? route.guides.first
    }

    func distanceToNextGuideMeters() -> Int? {
        guard let vehicleCoordinate, let guide = nextGuide else { return nil }
        return Int(distanceMeters(vehicleCoordinate, guide.coordinate).rounded())
    }

    private func rankPlaces(_ places: [KakaoPlace], query: String, near: CLLocationCoordinate2D?) -> [KakaoPlace] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return places }

        // Heuristic re-ranking on top of Kakao's API results.
        // Primary goal: "강남역" should prefer actual station/POI over unrelated businesses.
        func score(_ p: KakaoPlace) -> Int {
            var s = 0
            let name = p.name.trimmingCharacters(in: .whitespacesAndNewlines)

            if name == q { s += 400 }
            if name.hasPrefix(q) { s += 180 }

            // If the query looks like a station, boost subway/transport category results.
            let looksLikeStation = q.hasSuffix("역") || q.contains("역")
            if looksLikeStation {
                // Kakao category group codes (commonly): SW8=subway station.
                if p.categoryGroupCode == "SW8" { s += 260 }
                if (p.categoryName ?? "").contains("지하철") || (p.categoryName ?? "").contains("역") {
                    s += 90
                }
            }

            // If near is available, prefer closer results in a coarse way.
            if let near {
                let d = distanceMeters(near, p.coordinate)
                if d < 500 { s += 80 }
                else if d < 1_500 { s += 55 }
                else if d < 5_000 { s += 25 }
            }

            return s
        }

        return places.sorted { a, b in
            let sa = score(a)
            let sb = score(b)
            if sa != sb { return sa > sb }
            // Tie-breaker: if near exists, closer first.
            if let near {
                return distanceMeters(near, a.coordinate) < distanceMeters(near, b.coordinate)
            }
            return a.name < b.name
        }
    }

    private func client(restAPIKey: String) -> KakaoAPIClient {
        let key = restAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if let cachedClient, cachedKey == key {
            return cachedClient
        }
        let created = KakaoAPIClient(restAPIKey: key)
        cachedClient = created
        cachedKey = key
        return created
    }

    private func distanceMeters(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        // Fast-ish distance to avoid allocating many CLLocation objects while SwiftUI recomputes views.
        let r = 6_371_000.0
        let lat1 = a.latitude * Double.pi / 180.0
        let lat2 = b.latitude * Double.pi / 180.0
        let dLat = lat2 - lat1
        let dLon = (b.longitude - a.longitude) * Double.pi / 180.0

        let s1 = sin(dLat / 2.0)
        let s2 = sin(dLon / 2.0)
        let h = (s1 * s1) + (cos(lat1) * cos(lat2) * s2 * s2)
        return 2.0 * r * asin(min(1.0, sqrt(h)))
    }

    private func hasCoordinateChanged(
        current: CLLocationCoordinate2D?,
        next: CLLocationCoordinate2D?
    ) -> Bool {
        switch (current, next) {
        case (nil, nil):
            return false
        case (nil, .some), (.some, nil):
            return true
        case let (.some(a), .some(b)):
            let delta = abs(a.latitude - b.latitude) + abs(a.longitude - b.longitude)
            return delta >= 0.00002
        }
    }
}
