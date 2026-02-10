import Foundation

actor TeslaFleetService {
    static let shared = TeslaFleetService()

    private let session: URLSession
    private let decoder = JSONDecoder()
    private let iso = ISO8601DateFormatter()

    private var cachedVehicle: TeslaVehicleSummary?
    private var lastSnapshot: VehicleSnapshot?

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 20
        self.session = URLSession(configuration: config)
    }

    func fetchLatestSnapshot() async throws -> VehicleSnapshot {
        let vehicle = try await resolveVehicle()
        let data = try await request(path: "/api/1/vehicles/\(vehicle.vin)/vehicle_data", method: "GET")
        let decoded = try decoder.decode(TeslaVehicleDataEnvelope.self, from: data)
        let mapped = TeslaMapper.mapVehicleDataToSnapshot(vehicleData: decoded.response, fallback: vehicle, previous: lastSnapshot)
        lastSnapshot = mapped
        return mapped
    }

    func testVehiclesCount() async throws -> Int {
        let data = try await request(path: "/api/1/vehicles", method: "GET")
        let decoded = try decoder.decode(TeslaVehiclesEnvelope.self, from: data)
        return decoded.response?.count ?? 0
    }

    func sendCommand(_ command: String) async throws -> CommandResponse {
        let vehicle = try await resolveVehicle()
        let data = try await request(path: "/api/1/vehicles/\(vehicle.vin)/command/\(command)", method: "POST", body: Data("{}".utf8))
        let decoded = try decoder.decode(TeslaCommandEnvelope.self, from: data)
        let ok = decoded.response?.result ?? true
        let reason = decoded.response?.reason
        let message = reason ?? (ok ? "OK" : "Command failed")

        let log = CommandLog(
            command: command,
            ok: ok,
            message: message,
            at: iso.string(from: Date())
        )

        var latest: VehicleSnapshot?
        do {
            latest = try await fetchLatestSnapshot()
        } catch {
            latest = nil
        }

        let snapshot = latest.map { snap in
            VehicleSnapshot(
                source: snap.source,
                mode: snap.mode,
                updatedAt: snap.updatedAt,
                lastCommand: log,
                vehicle: snap.vehicle
            )
        }

        return CommandResponse(
            ok: ok,
            message: message,
            details: CommandDetails(response: CommandResultBody(result: decoded.response?.result, reason: decoded.response?.reason)),
            snapshot: snapshot
        )
    }

    private func resolveVehicle() async throws -> TeslaVehicleSummary {
        if let cachedVehicle {
            return cachedVehicle
        }

        if let vin = KeychainStore.getString(Keys.selectedVin), !vin.isEmpty {
            cachedVehicle = TeslaVehicleSummary(vin: vin, displayName: "(Vehicle)", state: "unknown")
            return cachedVehicle!
        }

        let data = try await request(path: "/api/1/vehicles", method: "GET")
        let decoded = try decoder.decode(TeslaVehiclesEnvelope.self, from: data)
        let list = decoded.response ?? []
        guard let first = list.first, !first.vin.isEmpty else {
            throw TeslaFleetError.noVehicles
        }

        cachedVehicle = first
        do {
            try KeychainStore.setString(first.vin, for: Keys.selectedVin)
        } catch {
            // Non-fatal; just skip caching.
        }
        return first
    }

    private func request(path: String, method: String, body: Data? = nil) async throws -> Data {
        let token = try await TeslaAuthStore.shared.ensureValidAccessToken()
        let base = (KeychainStore.getString(Keys.fleetApiBase) ?? TeslaConstants.defaultFleetApiBase).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let baseURL = URL(string: base.hasSuffix("/") ? base : "\(base)/") else {
            throw TeslaFleetError.misconfigured("Invalid Fleet API base URL.")
        }
        guard let url = URL(string: path.hasPrefix("/") ? String(path.dropFirst()) : path, relativeTo: baseURL) else {
            throw TeslaFleetError.misconfigured("Invalid API path.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TeslaFleetError.http(status: -1, message: "Invalid server response.")
        }

        guard (200...299).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            let shortened = text.count > 600 ? String(text.prefix(600)) + "..." : text

            if http.statusCode == 401 || http.statusCode == 403 {
                throw TeslaFleetError.unauthorized(shortened)
            }
            if http.statusCode == 429 {
                let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap { Int($0) }
                throw TeslaFleetError.rateLimited(retryAfterSeconds: retryAfter)
            }
            throw TeslaFleetError.http(status: http.statusCode, message: shortened)
        }

        return data
    }

    private enum Keys {
        static let selectedVin = "tesla.selected_vin"
        static let fleetApiBase = "tesla.fleet_api_base"
    }
}

enum TeslaFleetError: LocalizedError {
    case noVehicles
    case misconfigured(String)
    case unauthorized(String)
    case rateLimited(retryAfterSeconds: Int?)
    case http(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .noVehicles:
            return "No vehicles found for this Tesla account."
        case .misconfigured(let message):
            return message
        case .unauthorized:
            return "Tesla authorization failed. Please sign in again."
        case .rateLimited(let seconds):
            if let seconds {
                return "Rate limited by Tesla API. Retry after \(seconds)s."
            }
            return "Rate limited by Tesla API. Please try again later."
        case .http(let status, let message):
            return "Tesla API error (HTTP \(status)): \(message)"
        }
    }
}

private struct TeslaVehiclesEnvelope: Decodable {
    let response: [TeslaVehicleSummary]?
}

private struct TeslaVehicleSummary: Decodable {
    let vin: String
    let displayName: String
    let state: String

    enum CodingKeys: String, CodingKey {
        case vin
        case displayName = "display_name"
        case state
    }
}

private struct TeslaVehicleDataEnvelope: Decodable {
    let response: TeslaVehicleData
}

private struct TeslaVehicleData: Decodable {
    let vin: String?
    let displayName: String?
    let state: String?
    let driveState: TeslaDriveState?
    let chargeState: TeslaChargeState?
    let climateState: TeslaClimateState?
    let vehicleState: TeslaVehicleState?

    enum CodingKeys: String, CodingKey {
        case vin
        case displayName = "display_name"
        case state
        case driveState = "drive_state"
        case chargeState = "charge_state"
        case climateState = "climate_state"
        case vehicleState = "vehicle_state"
    }
}

private struct TeslaDriveState: Decodable {
    let latitude: Double?
    let longitude: Double?
    let heading: Double?
    let speed: Double?
}

private struct TeslaChargeState: Decodable {
    let batteryLevel: Double?
    let usableBatteryLevel: Double?
    let batteryRange: Double?

    enum CodingKeys: String, CodingKey {
        case batteryLevel = "battery_level"
        case usableBatteryLevel = "usable_battery_level"
        case batteryRange = "battery_range"
    }
}

private struct TeslaClimateState: Decodable {
    let insideTemp: Double?
    let outsideTemp: Double?
    let isClimateOn: Bool?

    enum CodingKeys: String, CodingKey {
        case insideTemp = "inside_temp"
        case outsideTemp = "outside_temp"
        case isClimateOn = "is_climate_on"
    }
}

private struct TeslaVehicleState: Decodable {
    let odometer: Double?
    let locked: Bool?
}

private struct TeslaCommandEnvelope: Decodable {
    let response: TeslaCommandResult?
}

private struct TeslaCommandResult: Decodable {
    let result: Bool?
    let reason: String?
}

private enum TeslaMapper {
    static func mapVehicleDataToSnapshot(vehicleData: TeslaVehicleData, fallback: TeslaVehicleSummary, previous: VehicleSnapshot?) -> VehicleSnapshot {
        let prev = previous?.vehicle

        let vin = vehicleData.vin ?? fallback.vin
        let displayName = vehicleData.displayName ?? fallback.displayName
        let onlineState = vehicleData.state ?? fallback.state

        let drive = vehicleData.driveState
        let charge = vehicleData.chargeState
        let climate = vehicleData.climateState
        let vehicleState = vehicleData.vehicleState

        let mph = drive?.speed
        let batteryRangeMi = charge?.batteryRange
        let odometerMi = vehicleState?.odometer

        let snapshot = VehicleSnapshot(
            source: "fleet_api",
            mode: "fleet_api",
            updatedAt: ISO8601DateFormatter().string(from: Date()),
            lastCommand: nil,
            vehicle: VehicleData(
                vin: vin,
                displayName: displayName.isEmpty ? (prev?.displayName ?? "Vehicle") : displayName,
                onlineState: onlineState,
                batteryLevel: charge?.batteryLevel ?? prev?.batteryLevel ?? 0,
                usableBatteryLevel: charge?.usableBatteryLevel ?? prev?.usableBatteryLevel ?? (charge?.batteryLevel ?? prev?.batteryLevel ?? 0),
                estimatedRangeKm: milesToKm(batteryRangeMi) ?? prev?.estimatedRangeKm ?? 0,
                insideTempC: climate?.insideTemp ?? prev?.insideTempC ?? 0,
                outsideTempC: climate?.outsideTemp ?? prev?.outsideTempC ?? 0,
                odometerKm: milesToKm(odometerMi) ?? prev?.odometerKm ?? 0,
                speedKph: mph.map(mphToKph) ?? prev?.speedKph ?? 0,
                headingDeg: drive?.heading ?? prev?.headingDeg ?? 0,
                isLocked: vehicleState?.locked ?? prev?.isLocked ?? true,
                isClimateOn: climate?.isClimateOn ?? prev?.isClimateOn ?? false,
                location: VehicleLocation(
                    lat: drive?.latitude ?? prev?.location.lat ?? 0,
                    lon: drive?.longitude ?? prev?.location.lon ?? 0
                )
            )
        )

        return snapshot
    }

    private static func mphToKph(_ mph: Double) -> Double {
        mph * 1.60934
    }

    private static func milesToKm(_ mi: Double?) -> Double? {
        guard let mi else { return nil }
        return mi * 1.60934
    }
}
