import Foundation

actor TelemetryService {
    private let session: URLSession
    private let decoder = JSONDecoder()

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 20
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: config)
    }

    func fetchLatest() async throws -> VehicleSnapshot {
        switch AppConfig.telemetrySource {
        case .directFleet:
            return try await TeslaFleetService.shared.fetchLatestSnapshot()
        case .backend:
            return try await fetchLatestFromBackend()
        }
    }

    func fetchNavigationStateFast() async throws -> NavigationState? {
        switch AppConfig.telemetrySource {
        case .directFleet:
            return try await TeslaFleetService.shared.fetchNavigationStateFast()
        case .backend:
            // Backend mode doesn't have a dedicated lightweight endpoint yet.
            // Keep behavior stable (no extra backend polling) until we explicitly add one.
            return nil
        }
    }

    func sendCommand(_ command: String, payload: [String: Any]? = nil) async throws -> CommandResponse {
        switch AppConfig.telemetrySource {
        case .directFleet:
            // Fleet-first: lower latency and no backend token drift.
            if command == "navigation_waypoints_request" || command == "navigation_request" {
                return try await sendNavigationCommandViaFleet(command, payload: payload)
            }
            return try await TeslaFleetService.shared.sendCommand(command, payload: payload)
        case .backend:
            // Backend mode keeps server-side routing and debug visibility.
            return try await sendCommandToBackend(command, payload: payload)
        }
    }

    private func fetchLatestFromBackend() async throws -> VehicleSnapshot {
        let url = AppConfig.backendBaseURL.appendingPathComponent("api/vehicle/latest")
        let (data, http) = try await request(url: url, method: "GET")
        guard (200...299).contains(http.statusCode) else {
            let fallback = "Backend fetch failed (HTTP \(http.statusCode))."
            throw TelemetryError.server(readBackendMessage(from: data, http: http, fallback: fallback))
        }

        do {
            return try decoder.decode(VehicleSnapshot.self, from: data)
        } catch {
            if isLikelyHTMLResponse(data: data, http: http) {
                throw TelemetryError.server("Backend returned HTML instead of JSON. Check backend/tunnel routing.")
            }
            throw TelemetryError.invalidResponse
        }
    }

    private func sendCommandToBackend(_ command: String, payload: [String: Any]? = nil) async throws -> CommandResponse {
        let healthWarning = await fetchBackendHealthWarning()
        let url = AppConfig.backendBaseURL.appendingPathComponent("api/vehicle/command")
        var bodyObject: [String: Any] = ["command": command]
        if let payload {
            bodyObject["payload"] = payload
        }
        let body = try JSONSerialization.data(withJSONObject: bodyObject, options: [])
        let (data, http) = try await request(url: url, method: "POST", body: body)

        guard (200...299).contains(http.statusCode) else {
            let fallback = "Command failed (HTTP \(http.statusCode))."
            let message = readBackendMessage(from: data, http: http, fallback: fallback)
            throw TelemetryError.server(mergeWithHealthWarning(message, healthWarning: healthWarning))
        }

        do {
            let envelope = try decoder.decode(BackendCommandEnvelope.self, from: data)
            let backendMessage = composeCommandMessage(envelope)
            let message = envelope.ok
                ? backendMessage
                : mergeWithHealthWarning(backendMessage, healthWarning: healthWarning)
            return CommandResponse(
                ok: envelope.ok,
                message: message,
                details: nil,
                snapshot: envelope.snapshot
            )
        } catch {
            if isLikelyHTMLResponse(data: data, http: http) {
                let base = "Backend returned HTML instead of JSON. Check tunnel/backend health."
                throw TelemetryError.server(mergeWithHealthWarning(base, healthWarning: healthWarning))
            }
            throw TelemetryError.invalidResponse
        }
    }

    private func fetchBackendHealth() async throws -> BackendHealthEnvelope {
        var lastError: Error?
        for components in [["health"], ["api", "health"]] {
            do {
                return try await fetchBackendHealth(pathComponents: components)
            } catch {
                lastError = error
            }
        }
        throw lastError ?? TelemetryError.server("Backend health check failed.")
    }

    private func fetchBackendHealth(pathComponents: [String]) async throws -> BackendHealthEnvelope {
        let url = pathComponents.reduce(AppConfig.backendBaseURL) { partial, component in
            partial.appendingPathComponent(component)
        }
        let (data, http) = try await request(url: url, method: "GET")

        guard (200...299).contains(http.statusCode) else {
            let fallback = "Backend health check failed (HTTP \(http.statusCode))."
            throw TelemetryError.server(readBackendMessage(from: data, http: http, fallback: fallback))
        }
        if isLikelyHTMLResponse(data: data, http: http) {
            throw TelemetryError.server("Backend health returned HTML. Tunnel/login page may be intercepting requests.")
        }

        guard let parsed = try? decoder.decode(BackendHealthEnvelope.self, from: data) else {
            throw TelemetryError.server("Backend health JSON is invalid.")
        }
        guard parsed.ok else {
            throw TelemetryError.server("Backend health is not OK. mode=\(parsed.mode ?? "unknown")")
        }
        return parsed
    }

    private func fetchBackendHealthWarning() async -> String? {
        do {
            _ = try await fetchBackendHealth()
            return nil
        } catch {
            let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            return message.isEmpty ? nil : message
        }
    }

    private func request(url: URL, method: String, body: Data? = nil) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10
        if let auth = AppConfig.backendAuthorizationHeader {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
        }
        if let apiKey = AppConfig.backendTokenForAPIKeyHeader {
            request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        }
        request.httpBody = body

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError where urlError.code == .cancelled {
            throw CancellationError()
        } catch let urlError as URLError {
            throw TelemetryError.server(networkMessage(for: urlError))
        } catch {
            throw TelemetryError.server("Backend connection error: \(error.localizedDescription)")
        }
        guard let http = response as? HTTPURLResponse else {
            throw TelemetryError.invalidResponse
        }
        return (data, http)
    }

    private func readBackendMessage(from data: Data, http: HTTPURLResponse, fallback: String) -> String {
        if let envelope = try? decoder.decode(BackendMessageEnvelope.self, from: data),
           !envelope.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "HTTP \(http.statusCode): \(envelope.message)"
        }

        let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let text, !text.isEmpty {
            if isLikelyHTMLBody(text) {
                return "HTTP \(http.statusCode): Backend returned HTML. Check backend/tunnel route."
            }
            return text
        }
        return fallback
    }

    private func isLikelyHTMLResponse(data: Data, http: HTTPURLResponse) -> Bool {
        let contentType = http.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        if contentType.contains("text/html") {
            return true
        }
        guard let text = String(data: data, encoding: .utf8) else {
            return false
        }
        return isLikelyHTMLBody(text)
    }

    private func isLikelyHTMLBody(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.hasPrefix("<!doctype html") || trimmed.hasPrefix("<html")
    }

    private func networkMessage(for error: URLError) -> String {
        switch error.code {
        case .timedOut:
            return "Backend timeout. Check hotspot/tunnel status."
        case .notConnectedToInternet:
            return "No internet connection. Connect iPad hotspot and retry."
        case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
            return "Cannot reach backend host. Verify backend URL/tunnel."
        default:
            return "Backend network error (\(error.code.rawValue)): \(error.localizedDescription)"
        }
    }

    private func mergeWithHealthWarning(_ message: String, healthWarning: String?) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let healthWarning, !healthWarning.isEmpty else { return trimmed }
        if trimmed.lowercased().contains("health") {
            return trimmed
        }
        return "\(trimmed) | backend health: \(healthWarning)"
    }

    private func composeCommandMessage(_ envelope: BackendCommandEnvelope) -> String {
        var parts: [String] = []
        let base = envelope.message.trimmingCharacters(in: .whitespacesAndNewlines)
        if !base.isEmpty {
            parts.append(base)
        }
        if let upstreamStatus = envelope.upstreamStatus {
            parts.append("upstream HTTP \(upstreamStatus)")
        }
        if let routedVia = envelope.routedVia?.trimmingCharacters(in: .whitespacesAndNewlines), !routedVia.isEmpty {
            parts.append("via \(routedVia)")
        }
        if let reason = envelope.details?.response?.reason?.trimmingCharacters(in: .whitespacesAndNewlines),
           !reason.isEmpty,
           !base.localizedCaseInsensitiveContains(reason) {
            parts.append(reason)
        }
        return parts.isEmpty ? "Command failed." : parts.joined(separator: " | ")
    }

    private func sendNavigationCommandViaFleet(_ command: String, payload: [String: Any]?) async throws -> CommandResponse {
        guard let destination = normalizeNavigationDestination(payload: payload) else {
            return try await TeslaFleetService.shared.sendCommand(command, payload: payload)
        }

        let waypointBody: [String: Any] = [
            "waypoints": [
                [
                    "lat": destination.lat,
                    "lon": destination.lon,
                    "name": destination.name
                ]
            ]
        ]

        let simpleBody: [String: Any] = [
            "lat": destination.lat,
            "lon": destination.lon,
            "name": destination.name
        ]

        let preferred = command == "navigation_request"
            ? [("navigation_request", simpleBody), ("navigation_waypoints_request", waypointBody)]
            : [("navigation_waypoints_request", waypointBody), ("navigation_request", simpleBody)]

        var lastResponse: CommandResponse?
        var lastError: Error?

        for (cmd, body) in preferred {
            do {
                let response = try await TeslaFleetService.shared.sendCommand(cmd, payload: body)
                lastResponse = response
                if response.ok {
                    return response
                }
            } catch {
                lastError = error
            }
        }

        if let lastResponse {
            return lastResponse
        }
        throw lastError ?? TelemetryError.server("Navigation command failed.")
    }

    private func normalizeNavigationDestination(payload: [String: Any]?) -> (name: String, lat: Double, lon: Double)? {
        guard let payload else { return nil }

        let name = (payload["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let lat = parseDouble(payload["lat"] ?? payload["latitude"])
        let lon = parseDouble(payload["lon"] ?? payload["lng"] ?? payload["longitude"])

        guard let lat, let lon else { return nil }
        guard (-90.0...90.0).contains(lat), (-180.0...180.0).contains(lon) else { return nil }

        return (name?.isEmpty == false ? name! : "Destination", lat, lon)
    }

    private func parseDouble(_ value: Any?) -> Double? {
        if let d = value as? Double, d.isFinite { return d }
        if let i = value as? Int { return Double(i) }
        if let s = value as? String, let d = Double(s), d.isFinite { return d }
        return nil
    }
}

enum TelemetryError: LocalizedError {
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid server response."
        case .server(let message):
            return message
        }
    }
}

private struct BackendMessageEnvelope: Decodable {
    let ok: Bool?
    let message: String
}

private struct BackendHealthEnvelope: Decodable {
    let ok: Bool
    let mode: String?
}

private struct BackendCommandEnvelope: Decodable {
    let ok: Bool
    let message: String
    let routedVia: String?
    let upstreamStatus: Int?
    let details: BackendCommandDetails?
    let snapshot: VehicleSnapshot?
}

private struct BackendCommandDetails: Decodable {
    let response: BackendCommandResultBody?
}

private struct BackendCommandResultBody: Decodable {
    let result: Bool?
    let reason: String?
}
