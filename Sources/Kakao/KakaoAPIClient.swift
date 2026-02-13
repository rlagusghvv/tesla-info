import CoreLocation
import Foundation

actor KakaoAPIClient {
    private let restAPIKey: String
    private let session: URLSession
    private let decoder = JSONDecoder()

    init(restAPIKey: String) {
        self.restAPIKey = restAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 20
        self.session = URLSession(configuration: config)
    }

    func searchPlaces(query: String, near: CLLocationCoordinate2D?) async throws -> [KakaoPlace] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        guard !restAPIKey.isEmpty else { throw KakaoAPIError.misconfigured("Missing Kakao REST API key.") }

        // Heuristic: queries ending with "역" are often subway stations.
        // Use category filter to improve accuracy (e.g., "강남역" shouldn't match random restaurants).
        let isStationQuery = q.hasSuffix("역") && q.count <= 6

        func makeURL(category: String?) throws -> URL {
            var components = URLComponents(string: "https://dapi.kakao.com/v2/local/search/keyword.json")
            var items: [URLQueryItem] = [
                URLQueryItem(name: "query", value: q),
                URLQueryItem(name: "size", value: "15")
            ]

            if let category {
                items.append(URLQueryItem(name: "category_group_code", value: category))
                // Prefer relevance for station name searches.
                items.append(URLQueryItem(name: "sort", value: "accuracy"))
            } else if let near {
                // Default: bias by current vehicle position.
                items.append(URLQueryItem(name: "x", value: String(near.longitude)))
                items.append(URLQueryItem(name: "y", value: String(near.latitude)))
                items.append(URLQueryItem(name: "radius", value: "20000"))
                items.append(URLQueryItem(name: "sort", value: "distance"))
            }

            components?.queryItems = items
            guard let url = components?.url else { throw KakaoAPIError.misconfigured("Invalid keyword search URL.") }
            return url
        }

        func fetch(url: URL) async throws -> KakaoKeywordSearchResponse {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("KakaoAK \(restAPIKey)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await session.data(for: request)
            try Self.validate(response: response, data: data)
            return try decoder.decode(KakaoKeywordSearchResponse.self, from: data)
        }

        // Station-first attempt.
        let decoded: KakaoKeywordSearchResponse
        if isStationQuery {
            let stationURL = try makeURL(category: "SW8")
            let stationDecoded = try await fetch(url: stationURL)
            if !stationDecoded.documents.isEmpty {
                decoded = stationDecoded
            } else {
                decoded = try await fetch(url: try makeURL(category: nil))
            }
        } else {
            decoded = try await fetch(url: try makeURL(category: nil))
        }

        return decoded.documents.compactMap { doc in
            guard let x = Double(doc.x), let y = Double(doc.y) else { return nil }
            let address = doc.roadAddressName.isEmpty ? doc.addressName : doc.roadAddressName
            return KakaoPlace(
                id: doc.id,
                name: doc.placeName,
                coordinate: CLLocationCoordinate2D(latitude: y, longitude: x),
                address: address,
                categoryGroupCode: doc.categoryGroupCode,
                categoryName: doc.categoryName
            )
        }
    }

    /// Fallback speed-camera candidates using Kakao local keyword POI.
    /// This supplements route-guide keyword matching to reduce misses in real driving.
    func searchSpeedCameraPOIs(
        near: CLLocationCoordinate2D,
        radiusMeters: Int = 15_000,
        pageLimit: Int = 3
    ) async throws -> [KakaoPlace] {
        guard !restAPIKey.isEmpty else { throw KakaoAPIError.misconfigured("Missing Kakao REST API key.") }

        let safeRadius = min(max(radiusMeters, 1_000), 20_000)
        let safePageLimit = min(max(pageLimit, 1), 5)
        var seen = Set<String>()
        var merged: [KakaoPlace] = []

        func makeURL(page: Int) throws -> URL {
            var components = URLComponents(string: "https://dapi.kakao.com/v2/local/search/keyword.json")
            components?.queryItems = [
                URLQueryItem(name: "query", value: "과속 단속 카메라"),
                URLQueryItem(name: "x", value: String(near.longitude)),
                URLQueryItem(name: "y", value: String(near.latitude)),
                URLQueryItem(name: "radius", value: String(safeRadius)),
                URLQueryItem(name: "sort", value: "distance"),
                URLQueryItem(name: "size", value: "15"),
                URLQueryItem(name: "page", value: String(page))
            ]
            guard let url = components?.url else { throw KakaoAPIError.misconfigured("Invalid speed-camera search URL.") }
            return url
        }

        func fetch(url: URL) async throws -> KakaoKeywordSearchResponse {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("KakaoAK \(restAPIKey)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await session.data(for: request)
            try Self.validate(response: response, data: data)
            return try decoder.decode(KakaoKeywordSearchResponse.self, from: data)
        }

        for page in 1...safePageLimit {
            let decoded = try await fetch(url: makeURL(page: page))
            if decoded.documents.isEmpty { break }

            for doc in decoded.documents {
                guard let x = Double(doc.x), let y = Double(doc.y) else { continue }
                let id = doc.id.isEmpty ? "\(x),\(y),\(doc.placeName)" : doc.id
                guard !seen.contains(id) else { continue }
                seen.insert(id)

                let address = doc.roadAddressName.isEmpty ? doc.addressName : doc.roadAddressName
                merged.append(
                    KakaoPlace(
                        id: id,
                        name: doc.placeName,
                        coordinate: CLLocationCoordinate2D(latitude: y, longitude: x),
                        address: address,
                        categoryGroupCode: doc.categoryGroupCode,
                        categoryName: doc.categoryName
                    )
                )
            }

            if decoded.meta?.isEnd == true {
                break
            }
        }

        return merged
    }

    func fetchRoute(origin: CLLocationCoordinate2D, destination: CLLocationCoordinate2D) async throws -> KakaoRoute {
        guard !restAPIKey.isEmpty else { throw KakaoAPIError.misconfigured("Missing Kakao REST API key.") }

        var components = URLComponents(string: "https://apis-navi.kakaomobility.com/v1/directions")
        components?.queryItems = [
            URLQueryItem(name: "origin", value: "\(origin.longitude),\(origin.latitude)"),
            URLQueryItem(name: "destination", value: "\(destination.longitude),\(destination.latitude)"),
            URLQueryItem(name: "priority", value: "RECOMMEND"),
            URLQueryItem(name: "alternatives", value: "false"),
            URLQueryItem(name: "road_details", value: "false")
        ]

        guard let url = components?.url else { throw KakaoAPIError.misconfigured("Invalid directions URL.") }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("KakaoAK \(restAPIKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        try Self.validate(response: response, data: data)

        let decoded = try decoder.decode(KakaoDirectionsResponse.self, from: data)
        guard let first = decoded.routes.first else {
            throw KakaoAPIError.server("No routes returned.")
        }

        let roads = first.sections?.flatMap { $0.roads ?? [] } ?? []
        let vertexes = roads.flatMap { $0.vertexes ?? [] }
        // Rendering a huge polyline can freeze MapKit on smaller iPads. Keep it lightweight for MVP.
        let polyline = Self.vertexesToCoordinates(vertexes, maxPoints: 450)
        let polylineDense = Self.vertexesToCoordinates(vertexes, maxPoints: 1800)

        let guides: [KakaoGuide] = (first.sections?.flatMap { $0.guides ?? [] } ?? []).compactMap { g -> KakaoGuide? in
            guard let x = g.x, let y = g.y else { return nil }
            let name = g.name ?? "Guide"
            let guidance = g.guidance ?? name
            let id = "\(x),\(y),\(guidance)"
            return KakaoGuide(
                id: id,
                name: name,
                guidance: guidance,
                coordinate: CLLocationCoordinate2D(latitude: y, longitude: x),
                distanceMeters: g.distance,
                durationSeconds: g.duration,
                type: g.type
            )
        }

        return KakaoRoute(
            polyline: polyline,
            polylineDense: polylineDense.isEmpty ? polyline : polylineDense,
            guides: guides,
            distanceMeters: first.summary?.distance,
            durationSeconds: first.summary?.duration
        )
    }

    private static func vertexesToCoordinates(_ vertexes: [Double], maxPoints: Int) -> [CLLocationCoordinate2D] {
        guard vertexes.count >= 4 else { return [] }
        let totalPoints = vertexes.count / 2
        guard totalPoints > 0 else { return [] }

        let cap = max(2, maxPoints)
        let step = max(1, Int(ceil(Double(totalPoints) / Double(cap))))

        var coords: [CLLocationCoordinate2D] = []
        coords.reserveCapacity(min(totalPoints, cap + 1))

        var i = 0
        while i < totalPoints {
            let base = i * 2
            let x = vertexes[base]
            let y = vertexes[base + 1]
            coords.append(CLLocationCoordinate2D(latitude: y, longitude: x))
            i += step
        }

        let lastX = vertexes[(totalPoints - 1) * 2]
        let lastY = vertexes[(totalPoints - 1) * 2 + 1]
        if let last = coords.last {
            if abs(last.latitude - lastY) > 0.000_000_001 || abs(last.longitude - lastX) > 0.000_000_001 {
                coords.append(CLLocationCoordinate2D(latitude: lastY, longitude: lastX))
            }
        } else {
            coords.append(CLLocationCoordinate2D(latitude: lastY, longitude: lastX))
        }

        return coords
    }

    private static func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw KakaoAPIError.server("Invalid server response.")
        }
        guard (200...299).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            let shortened = text.count > 600 ? String(text.prefix(600)) + "..." : text
            throw KakaoAPIError.http(status: http.statusCode, message: shortened)
        }
    }
}

enum KakaoAPIError: LocalizedError {
    case misconfigured(String)
    case server(String)
    case http(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .misconfigured(let message):
            return message
        case .server(let message):
            return message
        case .http(let status, let message):
            return "Kakao API error (HTTP \(status)): \(message)"
        }
    }
}

private struct KakaoKeywordSearchResponse: Decodable {
    let meta: KakaoKeywordSearchMeta?
    let documents: [KakaoKeywordSearchDocument]
}

private struct KakaoKeywordSearchMeta: Decodable {
    let isEnd: Bool?

    enum CodingKeys: String, CodingKey {
        case isEnd = "is_end"
    }
}

private struct KakaoKeywordSearchDocument: Decodable {
    let id: String
    let placeName: String
    let x: String
    let y: String
    let addressName: String
    let roadAddressName: String
    let categoryGroupCode: String?
    let categoryName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case placeName = "place_name"
        case x
        case y
        case addressName = "address_name"
        case roadAddressName = "road_address_name"
        case categoryGroupCode = "category_group_code"
        case categoryName = "category_name"
    }
}

private struct KakaoDirectionsResponse: Decodable {
    let routes: [KakaoDirectionsRoute]
}

private struct KakaoDirectionsRoute: Decodable {
    let summary: KakaoDirectionsSummary?
    let sections: [KakaoDirectionsSection]?
}

private struct KakaoDirectionsSummary: Decodable {
    let distance: Int?
    let duration: Int?
}

private struct KakaoDirectionsSection: Decodable {
    let roads: [KakaoDirectionsRoad]?
    let guides: [KakaoDirectionsGuide]?
}

private struct KakaoDirectionsRoad: Decodable {
    let vertexes: [Double]?
}

private struct KakaoDirectionsGuide: Decodable {
    let name: String?
    let guidance: String?
    let x: Double?
    let y: Double?
    let distance: Int?
    let duration: Int?
    let type: Int?
}
