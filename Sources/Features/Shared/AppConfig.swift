import Foundation

enum AppConfig {
    private static let defaultBackend = "http://127.0.0.1:8787"
    private static let backendOverrideKey = "backend_base_url_override"

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
