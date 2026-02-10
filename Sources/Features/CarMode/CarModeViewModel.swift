import Foundation

@MainActor
final class CarModeViewModel: ObservableObject {
    enum CenterMode: String, CaseIterable {
        case map = "Map"
        case navi = "Navi"
        case media = "Media"
    }

    @Published private(set) var snapshot: VehicleSnapshot = .placeholder
    @Published private(set) var isLoading = true
    @Published private(set) var isCommandRunning = false
    @Published var errorMessage: String?
    @Published var commandMessage: String?
    @Published var centerMode: CenterMode = .map
    @Published var mediaURLText: String = "https://www.youtube.com"
    @Published private(set) var pollIntervalSeconds: Int = 12
    @Published private(set) var lastSuccessfulUpdateAt: Date?

    private let service: TelemetryService
    private var pollTask: Task<Void, Never>?
    private var isRefreshing = false
    private var consecutiveFailures = 0

    init(service: TelemetryService = TelemetryService()) {
        self.service = service
    }

    deinit {
        pollTask?.cancel()
    }

    func start() {
        guard pollTask == nil else { return }

        pollTask = Task { @MainActor [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                await self.refresh()
                // Fleet API polling too frequently can get rate-limited.
                let seconds = max(6, self.pollIntervalSeconds)
                try? await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    func refresh() async {
        guard !isCommandRunning else { return }
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        if isLoading {
            errorMessage = nil
        }

        do {
            let latest = try await service.fetchLatest()
            snapshot = latest
            isLoading = false
            errorMessage = nil
            consecutiveFailures = 0
            lastSuccessfulUpdateAt = Date()

            if latest.vehicle.speedKph > 1 {
                pollIntervalSeconds = 8
            } else {
                pollIntervalSeconds = 12
            }
        } catch {
            isLoading = false
            consecutiveFailures += 1
            errorMessage = error.localizedDescription

            if let fleetError = error as? TeslaFleetError {
                switch fleetError {
                case .rateLimited(let retryAfterSeconds):
                    pollIntervalSeconds = max(pollIntervalSeconds, retryAfterSeconds ?? 30)
                    return
                case .unauthorized:
                    pollIntervalSeconds = 45
                    return
                default:
                    break
                }
            }

            // Exponential-ish backoff to keep the UI responsive when the API is failing.
            pollIntervalSeconds = min(60, 12 + (consecutiveFailures * 6))
        }
    }

    func sendCommand(_ command: String) {
        guard !isCommandRunning else { return }

        isCommandRunning = true
        commandMessage = nil

        Task {
            defer { isCommandRunning = false }

            do {
                let response = try await service.sendCommand(command)
                if let latest = response.snapshot {
                    snapshot = latest
                }
                commandMessage = response.message
                if !response.ok {
                    errorMessage = response.message
                }
            } catch {
                errorMessage = error.localizedDescription
                commandMessage = nil
            }
        }
    }

    var speedText: String {
        "\(Int(snapshot.vehicle.speedKph.rounded())) km/h"
    }

    var batteryText: String {
        "\(Int(snapshot.vehicle.batteryLevel.rounded()))%"
    }

    var rangeText: String {
        "\(Int(snapshot.vehicle.estimatedRangeKm.rounded())) km"
    }

    var lockText: String {
        snapshot.vehicle.isLocked ? "Locked" : "Unlocked"
    }

    var climateText: String {
        snapshot.vehicle.isClimateOn ? "A/C On" : "A/C Off"
    }

    var locationText: String {
        let lat = String(format: "%.5f", snapshot.vehicle.location.lat)
        let lon = String(format: "%.5f", snapshot.vehicle.location.lon)
        return "\(lat), \(lon)"
    }

    var mediaURL: URL? {
        URL(string: mediaURLText.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
