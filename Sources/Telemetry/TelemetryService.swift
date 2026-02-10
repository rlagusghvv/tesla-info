import Foundation

actor TelemetryService {
    init() {
    }

    func fetchLatest() async throws -> VehicleSnapshot {
        try await TeslaFleetService.shared.fetchLatestSnapshot()
    }

    func sendCommand(_ command: String) async throws -> CommandResponse {
        try await TeslaFleetService.shared.sendCommand(command)
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
