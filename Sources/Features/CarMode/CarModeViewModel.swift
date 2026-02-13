import CoreLocation
import Foundation

@MainActor
final class CarModeViewModel: ObservableObject {
    enum CenterMode: String {
        case navi = "Assist"
        case media = "Media"

        static var allCases: [CenterMode] { [.navi] }
    }

    @Published private(set) var snapshot: VehicleSnapshot = .placeholder
    @Published private(set) var isLoading = true
    @Published private(set) var isCommandRunning = false
    @Published var errorMessage: String?
    @Published var commandMessage: String?
    @Published var centerMode: CenterMode = .navi
    @Published var mediaURLText: String = "https://www.youtube.com"
    @Published private(set) var pollIntervalSeconds: Int = 20
    @Published private(set) var lastSuccessfulUpdateAt: Date?

    private let service: TelemetryService
    private var pollTask: Task<Void, Never>?
    private var isRefreshing = false
    private var consecutiveFailures = 0
    private var lastErrorFingerprint = ""

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
                let seconds = max(10, self.pollIntervalSeconds)
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
            if shouldReplaceSnapshot(with: latest) {
                snapshot = latest
            }
            isLoading = false
            errorMessage = nil
            lastErrorFingerprint = ""
            consecutiveFailures = 0
            lastSuccessfulUpdateAt = Date()

            if latest.vehicle.speedKph > 1 {
                pollIntervalSeconds = 12
            } else {
                pollIntervalSeconds = 20
            }
        } catch {
            if shouldIgnore(error) {
                return
            }
            isLoading = false
            consecutiveFailures += 1
            let message = compactErrorMessage(error.localizedDescription)
            if message != lastErrorFingerprint {
                errorMessage = message
                lastErrorFingerprint = message
            }

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
            pollIntervalSeconds = min(90, 20 + (consecutiveFailures * 10))
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
                    if shouldReplaceSnapshot(with: latest) {
                        snapshot = latest
                    }
                }
                applyOptimisticControlState(for: command, response: response)
                commandMessage = response.message
                if !response.ok {
                    errorMessage = compactErrorMessage(response.message)
                }
            } catch {
                if shouldIgnore(error) {
                    return
                }
                errorMessage = compactErrorMessage(error.localizedDescription)
                commandMessage = nil
            }
        }
    }

    func sendNavigationDestination(name: String, coordinate: CLLocationCoordinate2D) async -> (ok: Bool, message: String) {
        guard !isCommandRunning else {
            return (false, "Another command is already running.")
        }

        isCommandRunning = true
        commandMessage = nil
        defer { isCommandRunning = false }

        do {
            let payload: [String: Any] = [
                "name": name,
                "lat": coordinate.latitude,
                "lon": coordinate.longitude,
                "waypoints": [
                    [
                        "name": name,
                        "lat": coordinate.latitude,
                        "lon": coordinate.longitude
                    ]
                ]
            ]

            let response = try await service.sendCommand("navigation_waypoints_request", payload: payload)
            if let latest = response.snapshot, shouldReplaceSnapshot(with: latest) {
                snapshot = latest
            }
            commandMessage = response.message
            if !response.ok {
                errorMessage = compactErrorMessage(response.message)
            }
            return (response.ok, response.message)
        } catch {
            if shouldIgnore(error) {
                return (false, "Command cancelled.")
            }
            let message = compactErrorMessage(error.localizedDescription)
            errorMessage = message
            commandMessage = nil
            return (false, message)
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

    var navigationDestinationText: String {
        guard let nav = snapshot.navigation else { return "경로 없음" }
        let name = nav.destinationName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !name.isEmpty { return name }
        if let destination = nav.destination {
            let lat = String(format: "%.5f", destination.lat)
            let lon = String(format: "%.5f", destination.lon)
            return "\(lat), \(lon)"
        }
        return "Active route"
    }

    var navigationSummaryText: String {
        guard let nav = snapshot.navigation else { return "경로 없음" }
        var parts: [String] = []
        if let remainingKm = nav.remainingKm {
            parts.append(String(format: "%.1f km left", remainingKm))
        }
        if let etaMinutes = nav.etaMinutes {
            parts.append("\(etaMinutes) min")
        }
        if let delay = nav.trafficDelayMinutes, delay > 0 {
            parts.append("+\(delay)m traffic")
        }
        return parts.isEmpty ? "Route active" : parts.joined(separator: " · ")
    }

    var locationText: String {
        if snapshot.vehicle.location.isValid {
            let lat = String(format: "%.5f", snapshot.vehicle.location.lat)
            let lon = String(format: "%.5f", snapshot.vehicle.location.lon)
            return "\(lat), \(lon)"
        }
        return "Unknown (tap Wake)"
    }

    var mediaURL: URL? {
        URL(string: mediaURLText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func shouldIgnore(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        if let urlError = error as? URLError, urlError.code == .cancelled {
            return true
        }
        if let fleetError = error as? TeslaFleetError,
           case .network(_, let code, _, _) = fleetError,
           code == .cancelled {
            return true
        }
        return false
    }

    private func compactErrorMessage(_ message: String) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Unknown error." }

        // Avoid showing raw HTML error pages in UI popups (e.g., Cloudflare 5xx/403 pages).
        let lower = trimmed.lowercased()
        if lower.contains("<!doctype html") || lower.contains("<html") {
            return "Server error (received HTML). Check tunnel/backend and try again."
        }

        if trimmed.count > 220 {
            return String(trimmed.prefix(220)) + "..."
        }
        return trimmed
    }

    private func applyOptimisticControlState(for command: String, response: CommandResponse) {
        // Tesla/Fleet state can lag a few seconds after a successful command.
        // Patch the local snapshot immediately so the UI feels responsive.
        guard response.ok else { return }

        let targetLocked: Bool? = {
            switch command {
            case "door_lock":
                return true
            case "door_unlock":
                return false
            default:
                return nil
            }
        }()

        let targetClimateOn: Bool? = {
            switch command {
            case "auto_conditioning_start":
                return true
            case "auto_conditioning_stop":
                return false
            default:
                return nil
            }
        }()

        guard targetLocked != nil || targetClimateOn != nil else { return }

        let vehicle = snapshot.vehicle
        let patchedVehicle = VehicleData(
            vin: vehicle.vin,
            displayName: vehicle.displayName,
            onlineState: vehicle.onlineState,
            batteryLevel: vehicle.batteryLevel,
            usableBatteryLevel: vehicle.usableBatteryLevel,
            estimatedRangeKm: vehicle.estimatedRangeKm,
            insideTempC: vehicle.insideTempC,
            outsideTempC: vehicle.outsideTempC,
            odometerKm: vehicle.odometerKm,
            speedKph: vehicle.speedKph,
            headingDeg: vehicle.headingDeg,
            isLocked: targetLocked ?? vehicle.isLocked,
            isClimateOn: targetClimateOn ?? vehicle.isClimateOn,
            location: vehicle.location
        )

        let now = ISO8601DateFormatter().string(from: Date())
        let existingLog = snapshot.lastCommand
        let log = existingLog ?? CommandLog(
            command: command,
            ok: response.ok,
            message: response.message,
            at: now
        )

        snapshot = VehicleSnapshot(
            source: snapshot.source,
            mode: snapshot.mode,
            updatedAt: now,
            lastCommand: log,
            navigation: snapshot.navigation,
            vehicle: patchedVehicle
        )
    }

    private func shouldReplaceSnapshot(with latest: VehicleSnapshot) -> Bool {
        let current = snapshot

        if current.source != latest.source || current.mode != latest.mode {
            return true
        }

        let old = current.vehicle
        let new = latest.vehicle

        if old.displayName != new.displayName { return true }
        if old.onlineState != new.onlineState { return true }
        if old.isLocked != new.isLocked { return true }
        if old.isClimateOn != new.isClimateOn { return true }
        if abs(old.speedKph - new.speedKph) >= 0.3 { return true }
        if abs(old.batteryLevel - new.batteryLevel) >= 0.2 { return true }
        if abs(old.estimatedRangeKm - new.estimatedRangeKm) >= 0.5 { return true }
        if abs(old.headingDeg - new.headingDeg) >= 1.0 { return true }
        if abs(old.location.lat - new.location.lat) + abs(old.location.lon - new.location.lon) >= 0.00005 { return true }

        let oldCommandAt = current.lastCommand?.at ?? ""
        let newCommandAt = latest.lastCommand?.at ?? ""
        if oldCommandAt != newCommandAt { return true }

        return false
    }
}
