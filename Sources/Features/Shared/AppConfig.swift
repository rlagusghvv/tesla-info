import Foundation

enum AppConfig {
    private static let defaultBackend = "https://tesla.splui.com"
    private static let backendOverrideKey = "backend_base_url_override"
    private static let telemetrySourceKey = "telemetry_source"
    private static let backendTokenKey = "backend.api.token"
    private static let alertVolumeKey = "alerts.volume"
    private static let alertVoiceIdentifierKey = "alerts.voice_identifier"

    // MVP: keep IAP code in place, but do not gate features until explicitly enabled.
    // Flip this by adding `SubdashIAPEnabled = YES` to Info.plist (or by wiring a remote flag later).
    static var iapEnabled: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "SubdashIAPEnabled") as? Bool) ?? false
    }

    static var backendBaseURL: URL {
        if let override = UserDefaults.standard.string(forKey: backendOverrideKey),
           !override.isEmpty,
           let overrideURL = URL(string: override) {
            return overrideURL
        }

        if let configured = Bundle.main.object(forInfoDictionaryKey: "BackendBaseURL") as? String,
           let url = URL(string: configured),
           !configured.isEmpty {
            return url
        }

        return URL(string: defaultBackend)!
    }

    static var backendBaseURLString: String {
        backendBaseURL.absoluteString
    }

    static var backendAPIToken: String {
        KeychainStore.getString(backendTokenKey) ?? ""
    }

    static var backendTokenForAPIKeyHeader: String? {
        let trimmed = backendAPIToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.count > 7, trimmed.lowercased().hasPrefix("bearer ") {
            let token = String(trimmed.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
            return token.isEmpty ? nil : token
        }
        return trimmed
    }
    static var alertVolume: Double {
        let raw = UserDefaults.standard.object(forKey: alertVolumeKey) as? Double
        let value = raw ?? 0.95
        if !value.isFinite { return 0.95 }
        return min(1.0, max(0.0, value))
    }

    static func setAlertVolume(_ value: Double) {
        let fallback = 0.95
        let v = value.isFinite ? value : fallback
        let clamped = min(1.0, max(0.0, v))
        UserDefaults.standard.set(clamped, forKey: alertVolumeKey)
    }

    static var alertVoiceIdentifier: String? {
        let raw = (UserDefaults.standard.string(forKey: alertVoiceIdentifierKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? nil : raw
    }

    static func setAlertVoiceIdentifier(_ identifier: String?) {
        let trimmed = (identifier ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: alertVoiceIdentifierKey)
        } else {
            UserDefaults.standard.set(trimmed, forKey: alertVoiceIdentifierKey)
        }
    }

    static var backendAuthorizationHeader: String? {
        guard let token = backendTokenForAPIKeyHeader else { return nil }
        return "Bearer \(token)"
    }

    static var telemetrySource: TelemetrySource {
        if let raw = UserDefaults.standard.string(forKey: telemetrySourceKey),
           let source = TelemetrySource(rawValue: raw) {
            return source
        }
        // Default to direct Fleet for lowest latency and simpler ops (no backend/tunnel required).
        return .directFleet
    }

    static func setTelemetrySource(_ source: TelemetrySource) {
        UserDefaults.standard.set(source.rawValue, forKey: telemetrySourceKey)
    }

    static func setBackendOverride(urlString: String) throws {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            UserDefaults.standard.removeObject(forKey: backendOverrideKey)
            return
        }

        guard let _ = URL(string: trimmed) else {
            throw AppConfigError.invalidURL
        }

        UserDefaults.standard.set(trimmed, forKey: backendOverrideKey)
    }

    static func setBackendAPIToken(_ token: String) throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            KeychainStore.delete(backendTokenKey)
            return
        }
        try KeychainStore.setString(trimmed, for: backendTokenKey)
    }
}

enum TelemetrySource: String, CaseIterable {
    case directFleet = "direct_fleet"
    case backend = "backend"

    var title: String {
        switch self {
        case .directFleet:
            return "Direct Fleet"
        case .backend:
            return "Backend"
        }
    }
}

enum AppConfigError: LocalizedError {
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid backend URL format."
        }
    }
}

enum AppLogLevel: String, Sendable, Codable {
    case debug
    case info
    case warn
    case error
}

enum AppLogCategory: String, Sendable, Codable {
    case app
    case fleet
    case backend
    case route
    case cameras
    case gps
    case audio
}

struct AppLogEntry: Sendable, Codable {
    let at: Date
    let level: AppLogLevel
    let category: AppLogCategory
    let message: String
}

actor AppLogStore {
    static let shared = AppLogStore()

    private var entries: [AppLogEntry] = []
    private let maxEntries = 500
    private let iso = ISO8601DateFormatter()
    private let persistURL: URL
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init() {
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        persistURL = base.appendingPathComponent("subdash_app_logs.json")

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        // Best-effort restore from disk (helps debugging when the app freezes/crashes and is relaunched).
        if let data = try? Data(contentsOf: persistURL),
           let decoded = try? decoder.decode([AppLogEntry].self, from: data),
           !decoded.isEmpty {
            entries = Array(decoded.suffix(maxEntries))
        }
    }

    func log(_ level: AppLogLevel = .info, _ category: AppLogCategory, _ message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        entries.append(AppLogEntry(at: Date(), level: level, category: category, message: trimmed))
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }

    func clear() {
        entries.removeAll(keepingCapacity: true)
        try? FileManager.default.removeItem(at: persistURL)
    }

    func persist() {
        do {
            let data = try encoder.encode(entries)
            try data.write(to: persistURL, options: [.atomic])
        } catch {
            // Non-fatal.
        }
    }

    func dumpText(limit: Int = 400) -> String {
        let cap = max(0, min(maxEntries, limit))
        let slice = entries.suffix(cap)
        return slice.map { e in
            let ts = iso.string(from: e.at)
            return "\(ts) [\(e.level.rawValue.uppercased())][\(e.category.rawValue)] \(e.message)"
        }.joined(separator: "\n")
    }
}

func appLog(_ category: AppLogCategory, _ message: String, level: AppLogLevel = .info) {
    Task.detached(priority: .utility) {
        await AppLogStore.shared.log(level, category, message)
    }
}

