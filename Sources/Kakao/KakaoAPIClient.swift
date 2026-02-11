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

        var components = URLComponents(string: "https://dapi.kakao.com/v2/local/search/keyword.json")
        var items: [URLQueryItem] = [
            URLQueryItem(name: "query", value: q),
            URLQueryItem(name: "size", value: "10")
        ]
        if let near {
            items.append(URLQueryItem(name: "x", value: String(near.longitude)))
            items.append(URLQueryItem(name: "y", value: String(near.latitude)))
            items.append(URLQueryItem(name: "radius", value: "20000"))
            items.append(URLQueryItem(name: "sort", value: "distance"))
        }
        components?.queryItems = items

        guard let url = components?.url else { throw KakaoAPIError.misconfigured("Invalid keyword search URL.") }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("KakaoAK \(restAPIKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        try Self.validate(response: response, data: data)

        let decoded = try decoder.decode(KakaoKeywordSearchResponse.self, from: data)
        return decoded.documents.compactMap { doc in
            guard let x = Double(doc.x), let y = Double(doc.y) else { return nil }
            let address = doc.roadAddressName.isEmpty ? doc.addressName : doc.roadAddressName
            return KakaoPlace(
                id: doc.id,
                name: doc.placeName,
                coordinate: CLLocationCoordinate2D(latitude: y, longitude: x),
                address: address
            )
        }
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
    let documents: [KakaoKeywordSearchDocument]
}

private struct KakaoKeywordSearchDocument: Decodable {
    let id: String
    let placeName: String
    let x: String
    let y: String
    let addressName: String
    let roadAddressName: String

    enum CodingKeys: String, CodingKey {
        case id
        case placeName = "place_name"
        case x
        case y
        case addressName = "address_name"
        case roadAddressName = "road_address_name"
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
