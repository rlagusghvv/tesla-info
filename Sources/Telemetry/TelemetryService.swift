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

    func sendCommand(_ command: String) async throws -> CommandResponse {
        // In-car operation policy: always send commands through backend to keep
        // Fleet/TeslaMate command handling and retries centralized.
        return try await sendCommandToBackend(command)
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

    private func sendCommandToBackend(_ command: String) async throws -> CommandResponse {
        let healthWarning = await fetchBackendHealthWarning()
        let url = AppConfig.backendBaseURL.appendingPathComponent("api/vehicle/command")
        let body = try JSONSerialization.data(withJSONObject: ["command": command], options: [])
        let (data, http) = try await request(url: url, method: "POST", body: body)

        guard (200...299).contains(http.statusCode) else {
            let fallback = "Command failed (HTTP \(http.statusCode))."
            let message = readBackendMessage(from: data, http: http, fallback: fallback)
            throw TelemetryError.server(mergeWithHealthWarning(message, healthWarning: healthWarning))
        }

        do {
            let envelope = try decoder.decode(BackendCommandEnvelope.self, from: data)
            let message = envelope.ok
                ? envelope.message
                : mergeWithHealthWarning(envelope.message, healthWarning: healthWarning)
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
    let snapshot: VehicleSnapshot?
}
