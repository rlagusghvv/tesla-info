import CoreLocation
import Foundation

fileprivate struct LatLonBounds: Sendable {
    let minLat: Double
    let maxLat: Double
    let minLon: Double
    let maxLon: Double

    func contains(lat: Double, lon: Double) -> Bool {
        lat >= minLat && lat <= maxLat && lon >= minLon && lon <= maxLon
    }
}

private func boundsForPolyline(_ polyline: [CLLocationCoordinate2D], marginMeters: Double) -> LatLonBounds? {
    guard !polyline.isEmpty else { return nil }

    var minLat = Double.greatestFiniteMagnitude
    var maxLat = -Double.greatestFiniteMagnitude
    var minLon = Double.greatestFiniteMagnitude
    var maxLon = -Double.greatestFiniteMagnitude

    for p in polyline {
        minLat = min(minLat, p.latitude)
        maxLat = max(maxLat, p.latitude)
        minLon = min(minLon, p.longitude)
        maxLon = max(maxLon, p.longitude)
    }

    let centerLat = (minLat + maxLat) * 0.5
    let metersPerLat = 111_000.0
    let metersPerLon = max(1.0, metersPerLat * cos(centerLat * Double.pi / 180.0))
    let padLat = marginMeters / metersPerLat
    let padLon = marginMeters / metersPerLon

    return LatLonBounds(
        minLat: minLat - padLat,
        maxLat: maxLat + padLat,
        minLon: minLon - padLon,
        maxLon: maxLon + padLon
    )
}

private func haversineMeters(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
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

private func minDistanceToPolylineSegmentsMeters(point: CLLocationCoordinate2D, polyline: [CLLocationCoordinate2D]) -> Double? {
    guard polyline.count >= 2 else { return nil }

    // Equirectangular projection is good enough at < few hundred meters in KR.
    let refLat = point.latitude * Double.pi / 180.0
    let metersPerLat = 111_000.0
    let metersPerLon = max(1.0, metersPerLat * cos(refLat))

    func toXY(_ c: CLLocationCoordinate2D) -> (x: Double, y: Double) {
        (c.longitude * metersPerLon, c.latitude * metersPerLat)
    }

    let p = toXY(point)
    var best = Double.greatestFiniteMagnitude

    var prev = polyline[0]
    for next in polyline.dropFirst() {
        let a = toXY(prev)
        let b = toXY(next)
        let abx = b.x - a.x
        let aby = b.y - a.y
        let apx = p.x - a.x
        let apy = p.y - a.y
        let denom = (abx * abx) + (aby * aby)
        let t = denom > 0 ? max(0, min(1, (apx * abx + apy * aby) / denom)) : 0
        let cx = a.x + abx * t
        let cy = a.y + aby * t
        let dx = p.x - cx
        let dy = p.y - cy
        best = min(best, sqrt(dx * dx + dy * dy))
        prev = next
    }

    return best.isFinite ? best : nil
}

private func nearestPolylineIndex(point: CLLocationCoordinate2D, polyline: [CLLocationCoordinate2D]) -> Int? {
    guard !polyline.isEmpty else { return nil }
    var bestIdx = 0
    var best = Double.greatestFiniteMagnitude
    for (i, p) in polyline.enumerated() {
        let d = haversineMeters(point, p)
        if d < best {
            best = d
            bestIdx = i
        }
    }
    return best.isFinite ? bestIdx : nil
}

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
    @Published private(set) var speedCameraRevision: Int = 0
    @Published private(set) var followPulse: Int = 0
    @Published private(set) var zoomOffset: Int = 0
    @Published private(set) var zoomRevision: Int = 0
    @Published private(set) var nextSpeedCameraLimitKph: Int?
    @Published private(set) var speedCameraGuideCount: Int = 0
    @Published private(set) var isIndexingSpeedCameras: Bool = false
    @Published private(set) var homeDestination: SavedDestination?
    @Published private(set) var workDestination: SavedDestination?

    private static let favoriteHomeKey = "kakao.favorite.home"
    private static let favoriteWorkKey = "kakao.favorite.work"

    private var cachedKey: String = ""
    private var cachedClient: KakaoAPIClient?
    private var speedCameraPOIGuides: [KakaoGuide] = []
    private var publicSpeedCameraGuides: [KakaoGuide] = []
    private var speedCameraGuideRouteIndex: [String: Int] = [:]
    private var isRefreshingSpeedCameras = false
    private var lastSpeedCameraRefreshAt: Date = .distantPast
    private var lastSpeedCameraRefreshCoordinate: CLLocationCoordinate2D?
    private var lastNextSpeedCameraGuideIDForLimit: String?
    private var nextSpeedCameraLimitTask: Task<Void, Never>?

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
        updateNextSpeedCameraLimitIfNeeded()
    }

    func clearRoute() {
        route = nil
        speedCameraPOIGuides = []
        publicSpeedCameraGuides = []
        speedCameraGuideRouteIndex = [:]
        speedCameraGuideCount = 0
        isIndexingSpeedCameras = false
        speedCameraRevision += 1
        routeRevision += 1
        errorMessage = nil
        nextSpeedCameraLimitKph = nil
        lastNextSpeedCameraGuideIDForLimit = nil
        nextSpeedCameraLimitTask?.cancel()
        nextSpeedCameraLimitTask = nil
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
            if vehicleCoordinate == nil {
                vehicleCoordinate = origin
            }
            let r = try await client(restAPIKey: restAPIKey).fetchRoute(origin: origin, destination: destination)
            route = r
            routeRevision += 1
            isFollowModeEnabled = true
            followPulse += 1
            isIndexingSpeedCameras = true
            schedulePublicSpeedCameraIndexing(route: r, expectedRouteRevision: routeRevision)
            await refreshSpeedCameraPOIsIfNeeded(restAPIKey: restAPIKey, force: true)
            refreshSpeedCameraGuideCount()
            updateNextSpeedCameraLimitIfNeeded()
        } catch {
            route = nil
            speedCameraPOIGuides = []
            publicSpeedCameraGuides = []
            speedCameraGuideRouteIndex = [:]
            speedCameraGuideCount = 0
            isIndexingSpeedCameras = false
            speedCameraRevision += 1
            errorMessage = error.localizedDescription
            nextSpeedCameraLimitKph = nil
            lastNextSpeedCameraGuideIDForLimit = nil
            nextSpeedCameraLimitTask?.cancel()
            nextSpeedCameraLimitTask = nil
        }
    }

    private func updateNextSpeedCameraLimitIfNeeded() {
        guard let guide = nextSpeedCameraGuide else {
            nextSpeedCameraLimitKph = nil
            lastNextSpeedCameraGuideIDForLimit = nil
            nextSpeedCameraLimitTask?.cancel()
            nextSpeedCameraLimitTask = nil
            return
        }

        if lastNextSpeedCameraGuideIDForLimit == guide.id {
            return
        }
        lastNextSpeedCameraGuideIDForLimit = guide.id
        nextSpeedCameraLimitKph = nil

        nextSpeedCameraLimitTask?.cancel()
        nextSpeedCameraLimitTask = Task(priority: .utility) { [guideID = guide.id, coordinate = guide.coordinate] in
            let limit = await PublicSpeedCameraStore.shared.lookupLimit(near: coordinate, withinMeters: 90)
            if Task.isCancelled { return }
            // Guard against stale async update if the "next" camera changed mid-await.
            if self.lastNextSpeedCameraGuideIDForLimit != guideID { return }
            self.nextSpeedCameraLimitKph = limit
        }
    }

    func refreshSpeedCameraPOIsIfNeeded(restAPIKey: String, force: Bool = false) async {
        let key = restAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        guard route != nil else {
            if !speedCameraPOIGuides.isEmpty {
                speedCameraPOIGuides = []
                refreshSpeedCameraGuideCount()
                speedCameraRevision += 1
            }
            return
        }
        guard let near = vehicleCoordinate else { return }
        guard !isRefreshingSpeedCameras else { return }

        let movedEnough: Bool = {
            guard let last = lastSpeedCameraRefreshCoordinate else { return true }
            return distanceMeters(last, near) >= 1_500
        }()
        let stale = Date().timeIntervalSince(lastSpeedCameraRefreshAt) >= 180

        if !force && !movedEnough && !stale && !speedCameraPOIGuides.isEmpty {
            return
        }

        isRefreshingSpeedCameras = true
        defer { isRefreshingSpeedCameras = false }

        do {
            let places = try await client(restAPIKey: key).searchSpeedCameraPOIs(near: near)
            let filtered = filterSpeedCameraPOIs(places, route: route)
            speedCameraPOIGuides = filtered
            if let polyline = route?.polyline, !polyline.isEmpty {
                for g in filtered {
                    if speedCameraGuideRouteIndex[g.id] == nil {
                        speedCameraGuideRouteIndex[g.id] = nearestPolylineIndex(point: g.coordinate, polyline: polyline) ?? 0
                    }
                }
            }
            lastSpeedCameraRefreshCoordinate = near
            lastSpeedCameraRefreshAt = Date()
            refreshSpeedCameraGuideCount()
            speedCameraRevision += 1
        } catch {
            // Non-fatal: keep route guidance running even if camera POI fetch fails.
            if force && speedCameraPOIGuides.isEmpty {
                errorMessage = "Speed camera POI refresh failed: \(error.localizedDescription)"
            }
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

    var nextSpeedCameraGuide: KakaoGuide? {
        guard let route else { return nil }
        let cameraGuides = mergedSpeedCameraGuides()
        guard !cameraGuides.isEmpty else { return nil }
        guard let vehicleCoordinate else { return cameraGuides.first }

        if !route.polyline.isEmpty, let vehicleIndex = nearestPolylineIndex(point: vehicleCoordinate, polyline: route.polyline) {
            var best: KakaoGuide?
            var bestIdx = Int.max
            var bestDistance = Double.greatestFiniteMagnitude

            for g in cameraGuides {
                let idx = speedCameraGuideRouteIndex[g.id] ?? nearestPolylineIndex(point: g.coordinate, polyline: route.polyline) ?? 0
                speedCameraGuideRouteIndex[g.id] = idx

                // Allow a small slack because GPS can jitter around the polyline.
                guard idx + 2 >= vehicleIndex else { continue }

                if idx < bestIdx {
                    bestIdx = idx
                    bestDistance = distanceMeters(vehicleCoordinate, g.coordinate)
                    best = g
                    continue
                }
                if idx == bestIdx {
                    let d = distanceMeters(vehicleCoordinate, g.coordinate)
                    if d < bestDistance {
                        bestDistance = d
                        best = g
                    }
                }
            }

            if let best {
                return best
            }
        }

        var bestAny: KakaoGuide?
        var bestAnyDistance = Double.greatestFiniteMagnitude

        var bestAhead: KakaoGuide?
        var bestAheadDistance = Double.greatestFiniteMagnitude

        for g in cameraGuides {
            let d = distanceMeters(vehicleCoordinate, g.coordinate)
            if d < bestAnyDistance {
                bestAnyDistance = d
                bestAny = g
            }

            if d > 20, d < bestAheadDistance {
                bestAheadDistance = d
                bestAhead = g
            }
        }

        return bestAhead ?? bestAny ?? cameraGuides.first
    }

    func distanceToNextGuideMeters() -> Int? {
        guard let vehicleCoordinate, let guide = nextGuide else { return nil }
        return Int(distanceMeters(vehicleCoordinate, guide.coordinate).rounded())
    }

    func distanceToNextSpeedCameraMeters() -> Int? {
        guard let vehicleCoordinate, let guide = nextSpeedCameraGuide else { return nil }
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

    private func mergedSpeedCameraGuides() -> [KakaoGuide] {
        let routeGuides = route?.guides.filter(isSpeedCameraGuide(_:)) ?? []
        let incoming = routeGuides + publicSpeedCameraGuides + speedCameraPOIGuides
        guard !incoming.isEmpty else { return [] }

        var merged: [KakaoGuide] = []
        func precedence(of guide: KakaoGuide) -> Int {
            if guide.id.hasPrefix("poi:") { return 2 }
            if guide.id.hasPrefix("public:") { return 1 }
            return 0 // Kakao route-native guide
        }

        for guide in incoming {
            if let index = merged.firstIndex(where: { distanceMeters($0.coordinate, guide.coordinate) <= 35 }) {
                let existing = merged[index]
                // Prefer route-native > public dataset > POI when they overlap.
                if precedence(of: guide) < precedence(of: existing) {
                    merged[index] = guide
                }
                continue
            }
            merged.append(guide)
        }
        return merged
    }

    private func filterSpeedCameraPOIs(_ places: [KakaoPlace], route: KakaoRoute?) -> [KakaoGuide] {
        guard !places.isEmpty else { return [] }
        let polyline = route?.polyline ?? []

        return places.compactMap { place in
            if !looksLikeSpeedCamera(place.name) {
                return nil
            }

            if !polyline.isEmpty {
                guard let minDistance = minDistanceToPolyline(point: place.coordinate, polyline: polyline) else {
                    return nil
                }
                // Route polyline is downsampled for performance, so use a generous corridor.
                guard minDistance <= 220 else { return nil }
            }

            return KakaoGuide(
                id: "poi:\(place.id)",
                name: "과속 카메라",
                guidance: place.name,
                coordinate: place.coordinate,
                distanceMeters: nil,
                durationSeconds: nil,
                type: 9901
            )
        }
    }

    private func minDistanceToPolyline(point: CLLocationCoordinate2D, polyline: [CLLocationCoordinate2D]) -> Double? {
        guard !polyline.isEmpty else { return nil }
        var minValue = Double.greatestFiniteMagnitude
        for p in polyline {
            minValue = min(minValue, distanceMeters(point, p))
        }
        return minValue.isFinite ? minValue : nil
    }

    private func looksLikeSpeedCamera(_ text: String) -> Bool {
        let normalized = text.lowercased()
        let keywords = [
            "과속",
            "단속",
            "무인",
            "카메라",
            "camera",
            "cctv",
            "구간단속",
            "신호과속"
        ]
        return keywords.contains { normalized.contains($0) }
    }

    private func isSpeedCameraGuide(_ guide: KakaoGuide) -> Bool {
        let text = "\(guide.name) \(guide.guidance)".lowercased()
        let keywords = [
            "과속",
            "단속",
            "무인",
            "카메라",
            "camera",
            "cctv",
            "구간단속",
            "신호과속"
        ]
        if keywords.contains(where: { text.contains($0) }) {
            return true
        }

        // Kakao directions may omit textual hints for some camera-related maneuvers.
        if let type = guide.type {
            let knownCameraishTypes: Set<Int> = [53, 54, 55, 71, 72]
            if knownCameraishTypes.contains(type) {
                return true
            }
        }
        return false
    }

    private func refreshSpeedCameraGuideCount() {
        speedCameraGuideCount = mergedSpeedCameraGuides().count
    }

    private func schedulePublicSpeedCameraIndexing(route: KakaoRoute, expectedRouteRevision: Int) {
        let polyline = route.polyline
        guard !polyline.isEmpty else {
            publicSpeedCameraGuides = []
            isIndexingSpeedCameras = false
            refreshSpeedCameraGuideCount()
            speedCameraRevision += 1
            return
        }

        let corridorMeters = 180.0
        let boundsMarginMeters = 320.0

        Task.detached(priority: .utility) {
            let store = PublicSpeedCameraStore.shared
            await store.prewarm()
            if await store.cameraCount() == 0 {
                _ = try? await store.refreshFromBackendIfNeeded(force: true)
            }

            guard let bounds = boundsForPolyline(polyline, marginMeters: boundsMarginMeters) else {
                await MainActor.run {
                    if self.routeRevision != expectedRouteRevision { return }
                    self.publicSpeedCameraGuides = []
                    self.isIndexingSpeedCameras = false
                    self.refreshSpeedCameraGuideCount()
                    self.speedCameraRevision += 1
                }
                return
            }

            let candidates = await store.cameras(in: bounds)
            if candidates.isEmpty {
                await MainActor.run {
                    if self.routeRevision != expectedRouteRevision { return }
                    self.publicSpeedCameraGuides = []
                    self.isIndexingSpeedCameras = false
                    self.refreshSpeedCameraGuideCount()
                    self.speedCameraRevision += 1
                    self.updateNextSpeedCameraLimitIfNeeded()
                }
                return
            }

            var indexed: [(guide: KakaoGuide, idx: Int)] = []
            indexed.reserveCapacity(min(512, candidates.count / 4))

            for camera in candidates {
                let coord = camera.coordinate
                guard let minD = minDistanceToPolylineSegmentsMeters(point: coord, polyline: polyline) else { continue }
                guard minD <= corridorMeters else { continue }
                guard let idx = nearestPolylineIndex(point: coord, polyline: polyline) else { continue }

                indexed.append(
                    (
                        guide: KakaoGuide(
                            id: "public:\(camera.id)",
                            name: "과속 카메라",
                            guidance: "공공데이터",
                            coordinate: coord,
                            distanceMeters: nil,
                            durationSeconds: nil,
                            type: 9902
                        ),
                        idx: idx
                    )
                )
            }

            indexed.sort { a, b in
                if a.idx != b.idx { return a.idx < b.idx }
                return a.guide.id < b.guide.id
            }

            // De-dupe very close cameras to avoid repeated alerts at the same spot.
            var guides: [KakaoGuide] = []
            guides.reserveCapacity(indexed.count)

            var lastCoord: CLLocationCoordinate2D?
            for item in indexed {
                if let lastCoord {
                    if haversineMeters(lastCoord, item.guide.coordinate) <= 28 {
                        continue
                    }
                }
                guides.append(item.guide)
                lastCoord = item.guide.coordinate
            }

            let routeIndexMap: [String: Int] = Dictionary(uniqueKeysWithValues: indexed.map { ($0.guide.id, $0.idx) })
            let finalGuides = guides

            await MainActor.run {
                if self.routeRevision != expectedRouteRevision { return }
                self.publicSpeedCameraGuides = finalGuides
                for (id, idx) in routeIndexMap {
                    self.speedCameraGuideRouteIndex[id] = idx
                }
                self.isIndexingSpeedCameras = false
                self.refreshSpeedCameraGuideCount()
                self.speedCameraRevision += 1
                self.updateNextSpeedCameraLimitIfNeeded()
            }
        }
    }
}

// MARK: - Public Speed Camera Dataset (data.go.kr)

struct PublicSpeedCameraDataset: Codable {
    let schemaVersion: Int?
    let source: String?
    let updatedAt: String?
    let count: Int?
    let cameras: [PublicSpeedCamera]
}

struct PublicSpeedCamera: Codable {
    let id: String
    let lat: Double
    let lon: Double
    let limitKph: Int?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

actor PublicSpeedCameraStore {
    static let shared = PublicSpeedCameraStore()

    private let session: URLSession
    private let decoder = JSONDecoder()

    private var isLoaded = false
    private var cameras: [PublicSpeedCamera] = []
    private var index = GridIndex.empty

    private let etagKey = "public_speed_cameras.kr.etag"
    private let lastFetchKey = "public_speed_cameras.kr.last_fetch_at"

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 25
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)
    }

    func prewarm() async {
        await ensureLoaded()
        // Keep the dataset fresh, but never block UI on it.
        Task.detached(priority: .utility) {
            _ = try? await PublicSpeedCameraStore.shared.refreshFromBackendIfNeeded(force: false)
        }
    }

    func lookupLimit(near coordinate: CLLocationCoordinate2D, withinMeters: Double = 85) async -> Int? {
        await ensureLoaded()
        return index.nearest(to: coordinate, withinMeters: withinMeters)?.camera.limitKph
    }

    func cameraCount() async -> Int {
        await ensureLoaded()
        return cameras.count
    }

    fileprivate func cameras(in bounds: LatLonBounds) async -> [PublicSpeedCamera] {
        await ensureLoaded()
        guard !cameras.isEmpty else { return [] }
        return cameras.filter { bounds.contains(lat: $0.lat, lon: $0.lon) }
    }

    func refreshFromBackendIfNeeded(force: Bool) async throws -> Bool {
        let now = Date()
        if !force, let lastFetch = UserDefaults.standard.object(forKey: lastFetchKey) as? Date {
            if now.timeIntervalSince(lastFetch) < (12 * 60 * 60) {
                return false
            }
        }

        let url = AppConfig.backendBaseURL.appendingPathComponent("api/data/speed_cameras_kr")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let etag = UserDefaults.standard.string(forKey: etagKey), !etag.isEmpty {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        if http.statusCode == 304 {
            UserDefaults.standard.set(now, forKey: lastFetchKey)
            return false
        }

        guard (200...299).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw NSError(domain: "PublicSpeedCameraStore", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: message])
        }

        let decoded = try decoder.decode(PublicSpeedCameraDataset.self, from: data)
        let next = decoded.cameras

        cameras = next
        index = GridIndex.build(from: next)
        isLoaded = true

        if let newEtag = http.value(forHTTPHeaderField: "ETag"), !newEtag.isEmpty {
            UserDefaults.standard.set(newEtag, forKey: etagKey)
        }
        UserDefaults.standard.set(now, forKey: lastFetchKey)

        try? persistCache(data: data)
        return true
    }

    private func ensureLoaded() async {
        guard !isLoaded else { return }

        if let cached = loadCache() {
            cameras = cached
            index = GridIndex.build(from: cached)
            isLoaded = true
            return
        }

        // No cache: mark as loaded (empty) and let refresh happen asynchronously.
        cameras = []
        index = .empty
        isLoaded = true
    }

    private func cacheFileURL() -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("speed_cameras_kr.min.json")
    }

    private func loadCache() -> [PublicSpeedCamera]? {
        guard let url = cacheFileURL() else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let decoded = try? decoder.decode(PublicSpeedCameraDataset.self, from: data) else { return nil }
        return decoded.cameras
    }

    private func persistCache(data: Data) throws {
        guard let url = cacheFileURL() else { return }
        try data.write(to: url, options: [.atomic])
    }
}

private struct GridIndex {
    let cellSize: Double
    let buckets: [UInt64: [PublicSpeedCamera]]

    static let empty = GridIndex(cellSize: 0.01, buckets: [:])

    static func build(from cameras: [PublicSpeedCamera]) -> GridIndex {
        guard !cameras.isEmpty else { return .empty }
        var bucketed: [UInt64: [PublicSpeedCamera]] = [:]
        bucketed.reserveCapacity(min(4096, cameras.count / 3))
        let cellSize = Self.empty.cellSize

        for camera in cameras {
            let key = cellKey(lat: camera.lat, lon: camera.lon, cellSize: cellSize)
            bucketed[key, default: []].append(camera)
        }

        return GridIndex(cellSize: cellSize, buckets: bucketed)
    }

    func nearest(to coordinate: CLLocationCoordinate2D, withinMeters: Double) -> (camera: PublicSpeedCamera, distance: Double)? {
        guard withinMeters > 0 else { return nil }
        guard !buckets.isEmpty else { return nil }

        let cells = max(1, Int(ceil(withinMeters / (cellSize * 111_000.0))) + 1)
        let centerLatIndex = Int32(floor(coordinate.latitude / cellSize))
        let centerLonIndex = Int32(floor(coordinate.longitude / cellSize))

        var best: PublicSpeedCamera?
        var bestDistance = Double.greatestFiniteMagnitude

        for dLat in -cells...cells {
            for dLon in -cells...cells {
                let key = cellKey(
                    latIndex: centerLatIndex &+ Int32(dLat),
                    lonIndex: centerLonIndex &+ Int32(dLon)
                )
                guard let candidates = buckets[key] else { continue }

                for camera in candidates {
                    let d = distanceMeters(
                        coordinate.latitude,
                        coordinate.longitude,
                        camera.lat,
                        camera.lon
                    )
                    if d <= withinMeters, d < bestDistance {
                        best = camera
                        bestDistance = d
                    }
                }
            }
        }

        if let best {
            return (best, bestDistance)
        }
        return nil
    }

    private static func cellKey(lat: Double, lon: Double, cellSize: Double) -> UInt64 {
        let latIndex = Int32(floor(lat / cellSize))
        let lonIndex = Int32(floor(lon / cellSize))
        return cellKey(latIndex: latIndex, lonIndex: lonIndex)
    }

    private static func cellKey(latIndex: Int32, lonIndex: Int32) -> UInt64 {
        (UInt64(UInt32(bitPattern: latIndex)) << 32) | UInt64(UInt32(bitPattern: lonIndex))
    }

    private func cellKey(latIndex: Int32, lonIndex: Int32) -> UInt64 {
        Self.cellKey(latIndex: latIndex, lonIndex: lonIndex)
    }

    private func distanceMeters(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let r = 6_371_000.0
        let rad = Double.pi / 180.0
        let aLat = lat1 * rad
        let bLat = lat2 * rad
        let dLat = (lat2 - lat1) * rad
        let dLon = (lon2 - lon1) * rad
        let s1 = sin(dLat / 2.0)
        let s2 = sin(dLon / 2.0)
        let h = (s1 * s1) + (cos(aLat) * cos(bLat) * s2 * s2)
        return 2.0 * r * asin(min(1.0, sqrt(h)))
    }
}
