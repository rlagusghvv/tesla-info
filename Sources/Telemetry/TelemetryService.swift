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
        switch AppConfig.telemetrySource {
        case .directFleet:
            return try await TeslaFleetService.shared.sendCommand(command)
        case .backend:
            return try await sendCommandToBackend(command)
        }
    }

    private func fetchLatestFromBackend() async throws -> VehicleSnapshot {
        let url = AppConfig.backendBaseURL.appendingPathComponent("api/vehicle/latest")
        let (data, http) = try await request(url: url, method: "GET")
        guard (200...299).contains(http.statusCode) else {
            throw TelemetryError.server(readBackendMessage(from: data, fallback: "Backend fetch failed."))
        }

        do {
            return try decoder.decode(VehicleSnapshot.self, from: data)
        } catch {
            throw TelemetryError.invalidResponse
        }
    }

    private func sendCommandToBackend(_ command: String) async throws -> CommandResponse {
        let url = AppConfig.backendBaseURL.appendingPathComponent("api/vehicle/command")
        let body = try JSONSerialization.data(withJSONObject: ["command": command], options: [])
        let (data, http) = try await request(url: url, method: "POST", body: body)

        guard (200...299).contains(http.statusCode) else {
            throw TelemetryError.server(readBackendMessage(from: data, fallback: "Command failed."))
        }

        do {
            let envelope = try decoder.decode(BackendCommandEnvelope.self, from: data)
            return CommandResponse(
                ok: envelope.ok,
                message: envelope.message,
                details: nil,
                snapshot: envelope.snapshot
            )
        } catch {
            throw TelemetryError.invalidResponse
        }
    }

    private func request(url: URL, method: String, body: Data? = nil) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
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
        } catch {
            throw error
        }
        guard let http = response as? HTTPURLResponse else {
            throw TelemetryError.invalidResponse
        }
        return (data, http)
    }

    private func readBackendMessage(from data: Data, fallback: String) -> String {
        if let envelope = try? decoder.decode(BackendMessageEnvelope.self, from: data),
           !envelope.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return envelope.message
        }

        let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let text, !text.isEmpty {
            return text
        }
        return fallback
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

private struct BackendCommandEnvelope: Decodable {
    let ok: Bool
    let message: String
    let snapshot: VehicleSnapshot?
}
