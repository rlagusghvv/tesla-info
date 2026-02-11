import Foundation

enum AppConfig {
    private static let defaultBackend = "http://127.0.0.1:8787"
    private static let backendOverrideKey = "backend_base_url_override"
    private static let telemetrySourceKey = "telemetry_source"
    private static let backendTokenKey = "backend.api.token"

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

    static var backendAuthorizationHeader: String? {
        guard let token = backendTokenForAPIKeyHeader else { return nil }
        return "Bearer \(token)"
    }

    static var telemetrySource: TelemetrySource {
        if let raw = UserDefaults.standard.string(forKey: telemetrySourceKey),
           let source = TelemetrySource(rawValue: raw) {
            return source
        }
        // Default to backend mode for in-car reliability and easier local iteration.
        return .backend
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
