import Foundation

actor TeslaFleetService {
    static let shared = TeslaFleetService()

    // Tesla firmware 2023.38+ does not return location in drive_state unless you request `location_data`.
    // Keep this list minimal to reduce payload size (and rate-limit risk).
    private static let vehicleDataEndpoints = "drive_state;location_data;charge_state;climate_state;vehicle_state"

    private let session: URLSession
    private let decoder = JSONDecoder()
    private let iso = ISO8601DateFormatter()

    private var cachedVehicle: TeslaVehicleSummary?
    private var lastSnapshot: VehicleSnapshot?
    private var lastDriveStateFallbackAttemptAt: Date?
    private var lastPlainVehicleDataFallbackAttemptAt: Date?

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 20
        self.session = URLSession(configuration: config)
    }

    func fetchLatestSnapshot() async throws -> VehicleSnapshot {
        let vehicle = try await resolveVehicle()
        let data = try await request(
            path: "/api/1/vehicles/\(vehicle.vinOrId)/vehicle_data",
            method: "GET",
            queryItems: [
                URLQueryItem(name: "endpoints", value: Self.vehicleDataEndpoints),
                // Some accounts/firmware require this explicit flag to return coordinates.
                URLQueryItem(name: "location_data", value: "true")
            ]
        )
        let decoded = try decoder.decode(TeslaVehicleDataEnvelope.self, from: data)
        var mapped = TeslaMapper.mapVehicleDataToSnapshot(vehicleData: decoded.response, fallback: vehicle, previous: lastSnapshot)

        // Some vehicles/accounts return vehicle_data without a usable drive_state.location.
        // Try a dedicated drive_state request as a fallback, but avoid hammering the API.
        if !mapped.vehicle.location.isValid, shouldAttemptDriveStateFallback() {
            lastDriveStateFallbackAttemptAt = Date()
            do {
                let driveData = try await request(path: "/api/1/vehicles/\(vehicle.vinOrId)/data_request/drive_state", method: "GET")
                let driveEnvelope = try decoder.decode(TeslaDriveStateEnvelope.self, from: driveData)
                if let patchedVehicle = patchVehicle(from: driveEnvelope.response, existing: mapped.vehicle) {
                    mapped = VehicleSnapshot(
                        source: mapped.source,
                        mode: mapped.mode,
                        updatedAt: iso.string(from: Date()),
                        lastCommand: mapped.lastCommand,
                        vehicle: patchedVehicle
                    )
                }
            } catch {
                // Non-fatal: keep the original snapshot if drive_state fallback fails.
            }

            // Some firmware builds moved coordinates out of drive_state. If location is still missing,
            // try a dedicated location_data request.
            if !mapped.vehicle.location.isValid {
                do {
                    let locData = try await request(path: "/api/1/vehicles/\(vehicle.vinOrId)/data_request/location_data", method: "GET")
                    let locEnvelope = try decoder.decode(TeslaLocationDataEnvelope.self, from: locData)
                    if let patchedVehicle = patchVehicle(from: locEnvelope.response, existing: mapped.vehicle) {
                        mapped = VehicleSnapshot(
                            source: mapped.source,
                            mode: mapped.mode,
                            updatedAt: iso.string(from: Date()),
                            lastCommand: mapped.lastCommand,
                            vehicle: patchedVehicle
                        )
                    }
                } catch {
                    // Non-fatal: keep the snapshot if location_data fallback fails.
                }
            }
        }

        if !mapped.vehicle.location.isValid,
           let rawLocation = extractLocationFromRawJSON(data),
           let patchedVehicle = patchVehicle(from: rawLocation, existing: mapped.vehicle) {
            mapped = VehicleSnapshot(
                source: mapped.source,
                mode: mapped.mode,
                updatedAt: iso.string(from: Date()),
                lastCommand: mapped.lastCommand,
                vehicle: patchedVehicle
            )
        }

        // Some accounts appear to return sparse payloads when query params are attached.
        // As a final fallback, retry without query params and use whichever snapshot is richer.
        if !mapped.vehicle.location.isValid, shouldAttemptPlainVehicleDataFallback() {
            do {
                let plainData = try await request(path: "/api/1/vehicles/\(vehicle.vinOrId)/vehicle_data", method: "GET")
                let plainDecoded = try decoder.decode(TeslaVehicleDataEnvelope.self, from: plainData)
                var plainMapped = TeslaMapper.mapVehicleDataToSnapshot(vehicleData: plainDecoded.response, fallback: vehicle, previous: mapped)
                if !plainMapped.vehicle.location.isValid,
                   let rawLocation = extractLocationFromRawJSON(plainData),
                   let patchedVehicle = patchVehicle(from: rawLocation, existing: plainMapped.vehicle) {
                    plainMapped = VehicleSnapshot(
                        source: plainMapped.source,
                        mode: plainMapped.mode,
                        updatedAt: iso.string(from: Date()),
                        lastCommand: plainMapped.lastCommand,
                        vehicle: patchedVehicle
                    )
                }

                if scoreSnapshot(plainMapped) > scoreSnapshot(mapped) {
                    mapped = plainMapped
                }
            } catch {
                // Non-fatal: keep original snapshot.
            }
        }

        lastSnapshot = mapped
        return mapped
    }

    func testVehiclesCount() async throws -> Int {
        let data = try await request(path: "/api/1/vehicles", method: "GET")
        let decoded = try decoder.decode(TeslaVehiclesEnvelope.self, from: data)
        return decoded.response?.count ?? 0
    }

    func testSnapshotDiagnostics() async throws -> SnapshotDiagnostics {
        let vehicle = try await resolveVehicle()
        let data = try await request(
            path: "/api/1/vehicles/\(vehicle.vinOrId)/vehicle_data",
            method: "GET",
            queryItems: [
                URLQueryItem(name: "endpoints", value: Self.vehicleDataEndpoints),
                URLQueryItem(name: "location_data", value: "true")
            ]
        )

        let decoded = try decoder.decode(TeslaVehicleDataEnvelope.self, from: data)
        let mapped = TeslaMapper.mapVehicleDataToSnapshot(vehicleData: decoded.response, fallback: vehicle, previous: lastSnapshot)
        let source = decoded.response
        let drive = source.driveState
        let location = source.locationData
        let responseKeys = extractResponseKeysFromRawJSON(data)
        let rawLocation = extractLocationFromRawJSON(data)
        var plainResponseKeys = ""
        var plainRawLocation: TeslaLocationData?
        do {
            let plainData = try await request(path: "/api/1/vehicles/\(vehicle.vinOrId)/vehicle_data", method: "GET")
            plainResponseKeys = extractResponseKeysFromRawJSON(plainData).joined(separator: ", ")
            plainRawLocation = extractLocationFromRawJSON(plainData)
        } catch {
            plainResponseKeys = "(plain request failed)"
        }

        return SnapshotDiagnostics(
            mappedLocation: mapped.vehicle.location,
            driveStateLatitude: drive?.latitude,
            driveStateLongitude: drive?.longitude,
            locationDataLatitude: location?.latitude,
            locationDataLongitude: location?.longitude,
            rawLocationLatitude: rawLocation?.latitude,
            rawLocationLongitude: rawLocation?.longitude,
            responseKeys: responseKeys.joined(separator: ", "),
            plainRawLocationLatitude: plainRawLocation?.latitude,
            plainRawLocationLongitude: plainRawLocation?.longitude,
            plainResponseKeys: plainResponseKeys
        )
    }

    func sendCommand(_ command: String) async throws -> CommandResponse {
        let vehicle = try await resolveVehicle()
        // wake_up is not a /command endpoint on Fleet API.
        if command == "wake_up" {
            _ = try await request(path: "/api/1/vehicles/\(vehicle.vinOrId)/wake_up", method: "POST", body: Data("{}".utf8))
            let message = "Waking up..."

            let log = CommandLog(
                command: command,
                ok: true,
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
                ok: true,
                message: message,
                details: nil,
                snapshot: snapshot
            )
        }

        let data = try await request(path: "/api/1/vehicles/\(vehicle.vinOrId)/command/\(command)", method: "POST", body: Data("{}".utf8))
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

        if let idText = KeychainStore.getString(Keys.selectedVehicleId),
           let id = Int64(idText),
           id > 0 {
            cachedVehicle = TeslaVehicleSummary(id: id, vin: "", displayName: "(Vehicle)", state: "unknown")
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
            if let id = first.id {
                try KeychainStore.setString(String(id), for: Keys.selectedVehicleId)
            }
            try KeychainStore.setString(first.vin, for: Keys.selectedVin)
        } catch {
            // Non-fatal; just skip caching.
        }
        return first
    }

    private func request(path: String, method: String, queryItems: [URLQueryItem] = [], body: Data? = nil) async throws -> Data {
        let token = try await TeslaAuthStore.shared.ensureValidAccessToken()
        let base = (KeychainStore.getString(Keys.fleetApiBase) ?? TeslaConstants.defaultFleetApiBase).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let baseURL = URL(string: base.hasSuffix("/") ? base : "\(base)/") else {
            throw TeslaFleetError.misconfigured("Invalid Fleet API base URL.")
        }
        guard let url = URL(string: path.hasPrefix("/") ? String(path.dropFirst()) : path, relativeTo: baseURL) else {
            throw TeslaFleetError.misconfigured("Invalid API path.")
        }

        var finalURL = url
        if !queryItems.isEmpty {
            guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
                throw TeslaFleetError.misconfigured("Invalid API URL.")
            }
            var merged = components.queryItems ?? []
            merged.append(contentsOf: queryItems)
            components.queryItems = merged
            guard let updated = components.url else {
                throw TeslaFleetError.misconfigured("Invalid API URL.")
            }
            finalURL = updated
        }

        var request = URLRequest(url: finalURL)
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

            // Tesla sometimes responds with non-401 status but "Unauthorized" payload.
            if http.statusCode == 401 || http.statusCode == 403 || shortened.localizedCaseInsensitiveContains("\"error\":\"unauthorized\"") || shortened.localizedCaseInsensitiveContains("\"error\":\"Unauthorized\"") {
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
        static let selectedVehicleId = "tesla.selected_vehicle_id"
        static let fleetApiBase = "tesla.fleet_api_base"
    }

    private func shouldAttemptDriveStateFallback(now: Date = Date()) -> Bool {
        guard let last = lastDriveStateFallbackAttemptAt else { return true }
        return now.timeIntervalSince(last) > 25
    }

    private func shouldAttemptPlainVehicleDataFallback(now: Date = Date()) -> Bool {
        guard let last = lastPlainVehicleDataFallbackAttemptAt else {
            lastPlainVehicleDataFallbackAttemptAt = now
            return true
        }
        let allowed = now.timeIntervalSince(last) > 30
        if allowed {
            lastPlainVehicleDataFallbackAttemptAt = now
        }
        return allowed
    }

    private func scoreSnapshot(_ snapshot: VehicleSnapshot) -> Int {
        var score = 0
        if snapshot.vehicle.location.isValid { score += 10 }
        if snapshot.vehicle.batteryLevel > 0 { score += 3 }
        if snapshot.vehicle.estimatedRangeKm > 0 { score += 2 }
        if snapshot.vehicle.odometerKm > 0 { score += 2 }
        if snapshot.vehicle.displayName != "Vehicle" && snapshot.vehicle.displayName != "(Vehicle)" { score += 1 }
        return score
    }

    private func patchVehicle(from drive: TeslaDriveState, existing: VehicleData) -> VehicleData? {
        guard let lat = drive.latitude, let lon = drive.longitude else { return nil }
        let loc = VehicleLocation(lat: lat, lon: lon)
        guard loc.isValid else { return nil }

        return VehicleData(
            vin: existing.vin,
            displayName: existing.displayName,
            onlineState: existing.onlineState,
            batteryLevel: existing.batteryLevel,
            usableBatteryLevel: existing.usableBatteryLevel,
            estimatedRangeKm: existing.estimatedRangeKm,
            insideTempC: existing.insideTempC,
            outsideTempC: existing.outsideTempC,
            odometerKm: existing.odometerKm,
            speedKph: drive.speed.map(mphToKph) ?? existing.speedKph,
            headingDeg: drive.heading ?? existing.headingDeg,
            isLocked: existing.isLocked,
            isClimateOn: existing.isClimateOn,
            location: loc
        )
    }

    private func patchVehicle(from location: TeslaLocationData, existing: VehicleData) -> VehicleData? {
        guard let lat = location.latitude, let lon = location.longitude else { return nil }
        let loc = VehicleLocation(lat: lat, lon: lon)
        guard loc.isValid else { return nil }

        return VehicleData(
            vin: existing.vin,
            displayName: existing.displayName,
            onlineState: existing.onlineState,
            batteryLevel: existing.batteryLevel,
            usableBatteryLevel: existing.usableBatteryLevel,
            estimatedRangeKm: existing.estimatedRangeKm,
            insideTempC: existing.insideTempC,
            outsideTempC: existing.outsideTempC,
            odometerKm: existing.odometerKm,
            speedKph: location.speed.map(mphToKph) ?? existing.speedKph,
            headingDeg: location.heading ?? existing.headingDeg,
            isLocked: existing.isLocked,
            isClimateOn: existing.isClimateOn,
            location: loc
        )
    }

    private func mphToKph(_ mph: Double) -> Double {
        mph * 1.60934
    }

    private func extractResponseKeysFromRawJSON(_ data: Data) -> [String] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        guard let response = json["response"] as? [String: Any] else {
            return []
        }
        return response.keys.sorted()
    }

    private func extractLocationFromRawJSON(_ data: Data) -> TeslaLocationData? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        guard let response = json["response"] as? [String: Any] else {
            return nil
        }

        let candidatePaths: [[String]] = [
            ["drive_state"],
            ["location_data"],
            ["vehicle_data", "drive_state"],
            ["vehicle_data", "location_data"],
            ["vehicle_data_combo", "drive_state"],
            ["vehicle_data_combo", "location_data"]
        ]

        for path in candidatePaths {
            guard let node = nestedDictionary(response, path: path) else { continue }
            let lat = toDouble(node["latitude"])
            let lon = toDouble(node["longitude"])
            let heading = toDouble(node["heading"])
            let speed = toDouble(node["speed"])
            if let lat, let lon {
                let loc = VehicleLocation(lat: lat, lon: lon)
                if loc.isValid {
                    return TeslaLocationData(latitude: lat, longitude: lon, heading: heading, speed: speed)
                }
            }
        }

        return nil
    }

    private func nestedDictionary(_ root: [String: Any], path: [String]) -> [String: Any]? {
        var current: Any = root
        for key in path {
            guard let dict = current as? [String: Any], let next = dict[key] else {
                return nil
            }
            current = next
        }
        return current as? [String: Any]
    }

    private func toDouble(_ value: Any?) -> Double? {
        switch value {
        case let n as NSNumber:
            return n.doubleValue
        case let s as String:
            return Double(s)
        default:
            return nil
        }
    }
}

struct SnapshotDiagnostics {
    let mappedLocation: VehicleLocation
    let driveStateLatitude: Double?
    let driveStateLongitude: Double?
    let locationDataLatitude: Double?
    let locationDataLongitude: Double?
    let rawLocationLatitude: Double?
    let rawLocationLongitude: Double?
    let responseKeys: String
    let plainRawLocationLatitude: Double?
    let plainRawLocationLongitude: Double?
    let plainResponseKeys: String
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
        case .unauthorized(let details):
            #if DEBUG
            let trimmed = details.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return "Tesla authorization failed. Please sign in again."
            }
            return "Tesla authorization failed. Please sign in again.\n\nDetails: \(trimmed)"
            #else
            return "Tesla authorization failed. Please sign in again."
            #endif
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
    let id: Int64?
    let vin: String
    let displayName: String
    let state: String

    enum CodingKeys: String, CodingKey {
        case id
        case vin
        case displayName = "display_name"
        case state
    }

    init(id: Int64? = nil, vin: String, displayName: String, state: String) {
        self.id = id
        self.vin = vin
        self.displayName = displayName
        self.state = state
    }

    var identifier: String {
        if let id {
            return String(id)
        }
        return vin
    }

    var vinOrId: String {
        if !vin.isEmpty { return vin }
        if let id { return String(id) }
        return vin
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
    let locationData: TeslaLocationData?
    let chargeState: TeslaChargeState?
    let climateState: TeslaClimateState?
    let vehicleState: TeslaVehicleState?

    enum CodingKeys: String, CodingKey {
        case vin
        case displayName = "display_name"
        case state
        case driveState = "drive_state"
        case locationData = "location_data"
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

private struct TeslaLocationData: Decodable {
    let latitude: Double?
    let longitude: Double?
    let heading: Double?
    let speed: Double?

    init(latitude: Double?, longitude: Double?, heading: Double?, speed: Double?) {
        self.latitude = latitude
        self.longitude = longitude
        self.heading = heading
        self.speed = speed
    }
}

private struct TeslaDriveStateEnvelope: Decodable {
    let response: TeslaDriveState
}

private struct TeslaLocationDataEnvelope: Decodable {
    let response: TeslaLocationData
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
        let loc = vehicleData.locationData
        let charge = vehicleData.chargeState
        let climate = vehicleData.climateState
        let vehicleState = vehicleData.vehicleState

        let mph = drive?.speed ?? loc?.speed
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
                headingDeg: drive?.heading ?? loc?.heading ?? prev?.headingDeg ?? 0,
                isLocked: vehicleState?.locked ?? prev?.isLocked ?? true,
                isClimateOn: climate?.isClimateOn ?? prev?.isClimateOn ?? false,
                location: VehicleLocation(
                    lat: loc?.latitude ?? drive?.latitude ?? prev?.location.lat ?? 0,
                    lon: loc?.longitude ?? drive?.longitude ?? prev?.location.lon ?? 0
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
