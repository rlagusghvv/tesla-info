import CoreLocation
import Foundation

@MainActor
final class KakaoNavigationViewModel: ObservableObject {
    enum FavoriteSlot: String {
        case home
        case work

        var title: String {
            switch self {
            case .home:
                return "집"
            case .work:
                return "직장"
            }
        }
    }

    struct SavedDestination: Codable {
        let name: String
        let address: String
        let lat: Double
        let lon: Double

        var coordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
    }

    @Published var query: String = ""
    @Published private(set) var results: [KakaoPlace] = []
    @Published private(set) var route: KakaoRoute?
    @Published private(set) var isSearching = false
    @Published private(set) var isRouting = false
    @Published var errorMessage: String?
    @Published var isFollowModeEnabled: Bool = true

    @Published private(set) var vehicleCoordinate: CLLocationCoordinate2D?
    @Published private(set) var vehicleSpeedKph: Double = 0
    @Published private(set) var routeRevision: Int = 0
    @Published private(set) var followPulse: Int = 0
    @Published private(set) var zoomOffset: Int = 0
    @Published private(set) var zoomRevision: Int = 0
    @Published private(set) var homeDestination: SavedDestination?
    @Published private(set) var workDestination: SavedDestination?

    private static let favoriteHomeKey = "kakao.favorite.home"
    private static let favoriteWorkKey = "kakao.favorite.work"

    private var cachedKey: String = ""
    private var cachedClient: KakaoAPIClient?

    init() {
        loadFavorites()
    }

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
        routeRevision += 1
        errorMessage = nil
    }

    func saveFavorite(_ slot: FavoriteSlot, place: KakaoPlace) {
        let saved = SavedDestination(
            name: place.name,
            address: place.address,
            lat: place.coordinate.latitude,
            lon: place.coordinate.longitude
        )
        assignFavorite(slot, destination: saved)
        persistFavorite(slot, destination: saved)
    }

    func clearFavorite(_ slot: FavoriteSlot) {
        assignFavorite(slot, destination: nil)
        persistFavorite(slot, destination: nil)
    }

    func favorite(for slot: FavoriteSlot) -> SavedDestination? {
        switch slot {
        case .home:
            return homeDestination
        case .work:
            return workDestination
        }
    }

    func zoomIn() {
        zoomOffset = max(-3, zoomOffset - 1)
        zoomRevision += 1
        followPulse += 1
    }

    func zoomOut() {
        zoomOffset = min(4, zoomOffset + 1)
        zoomRevision += 1
        followPulse += 1
    }

    func resetZoom() {
        zoomOffset = 0
        zoomRevision += 1
        followPulse += 1
    }

    func bumpFollowPulse() {
        followPulse += 1
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
            routeRevision += 1
            isFollowModeEnabled = true
            followPulse += 1
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

    private func loadFavorites() {
        homeDestination = decodeFavorite(for: .home)
        workDestination = decodeFavorite(for: .work)
    }

    private func assignFavorite(_ slot: FavoriteSlot, destination: SavedDestination?) {
        switch slot {
        case .home:
            homeDestination = destination
        case .work:
            workDestination = destination
        }
    }

    private func persistFavorite(_ slot: FavoriteSlot, destination: SavedDestination?) {
        let key = favoriteKey(for: slot)
        if let destination, let data = try? JSONEncoder().encode(destination) {
            UserDefaults.standard.set(data, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private func decodeFavorite(for slot: FavoriteSlot) -> SavedDestination? {
        let key = favoriteKey(for: slot)
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(SavedDestination.self, from: data)
    }

    private func favoriteKey(for slot: FavoriteSlot) -> String {
        switch slot {
        case .home:
            return Self.favoriteHomeKey
        case .work:
            return Self.favoriteWorkKey
        }
    }
}
