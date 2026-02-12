import CoreLocation
import Foundation

struct VehicleSnapshot: Codable {
    let source: String
    let mode: String
    let updatedAt: String
    let lastCommand: CommandLog?
    let navigation: NavigationState?
    let vehicle: VehicleData

    init(
        source: String,
        mode: String,
        updatedAt: String,
        lastCommand: CommandLog?,
        navigation: NavigationState? = nil,
        vehicle: VehicleData
    ) {
        self.source = source
        self.mode = mode
        self.updatedAt = updatedAt
        self.lastCommand = lastCommand
        self.navigation = navigation
        self.vehicle = vehicle
    }

    static let placeholder = VehicleSnapshot(
        source: "placeholder",
        mode: "simulator",
        updatedAt: ISO8601DateFormatter().string(from: Date()),
        lastCommand: nil,
        navigation: nil,
        vehicle: VehicleData(
            vin: "SIMULATED_VIN",
            displayName: "Model Y",
            onlineState: "online",
            batteryLevel: 80,
            usableBatteryLevel: 78,
            estimatedRangeKm: 404,
            insideTempC: 23,
            outsideTempC: 11,
            odometerKm: 21483,
            speedKph: 61,
            headingDeg: 90,
            isLocked: true,
            isClimateOn: false,
            location: VehicleLocation(lat: 37.498095, lon: 127.02761)
        )
    )
}

struct NavigationState: Codable, Equatable {
    let destinationName: String?
    let destination: VehicleLocation?
    let remainingKm: Double?
    let etaMinutes: Int?
    let trafficDelayMinutes: Int?
    let energyAtArrivalPercent: Double?
}

struct CommandLog: Codable {
    let command: String
    let ok: Bool
    let message: String
    let at: String
}

struct VehicleData: Codable {
    let vin: String
    let displayName: String
    let onlineState: String
    let batteryLevel: Double
    let usableBatteryLevel: Double
    let estimatedRangeKm: Double
    let insideTempC: Double
    let outsideTempC: Double
    let odometerKm: Double
    let speedKph: Double
    let headingDeg: Double
    let isLocked: Bool
    let isClimateOn: Bool
    let location: VehicleLocation
}

struct VehicleLocation: Codable, Equatable {
    let lat: Double
    let lon: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

extension VehicleLocation {
    var isValid: Bool {
        // Treat (0,0) as "unknown" for this app, even though it's a valid coordinate.
        // Tesla sometimes omits drive_state when the vehicle is asleep or location isn't available.
        if abs(lat) < 0.000_01, abs(lon) < 0.000_01 { return false }
        guard (-90.0...90.0).contains(lat) else { return false }
        guard (-180.0...180.0).contains(lon) else { return false }
        return true
    }
}

struct CommandResponse: Codable {
    let ok: Bool
    let message: String
    let details: CommandDetails?
    let snapshot: VehicleSnapshot?
}

struct CommandDetails: Codable {
    let response: CommandResultBody?
}

struct CommandResultBody: Codable {
    let result: Bool?
    let reason: String?
}
