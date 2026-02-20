import CryptoKit
import Foundation

@MainActor
final class TeslaAuthStore: ObservableObject {
    static let shared = TeslaAuthStore()

    @Published private(set) var isSignedIn: Bool = false
    @Published var statusMessage: String?
    @Published var isBusy: Bool = false

    @Published var clientId: String = ""
    @Published var clientSecret: String = ""
    @Published var redirectURI: String = TeslaConstants.defaultRedirectURI
    @Published var audience: String = TeslaConstants.defaultAudience
    @Published var fleetApiBase: String = TeslaConstants.defaultFleetApiBase
    @Published var manualCode: String = ""
    @Published var manualState: String = ""

    private let session: URLSession
    private let iso = ISO8601DateFormatter()

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 20
        self.session = URLSession(configuration: config)

        loadConfig()
        loadTokenState()
    }

    struct TokenDiagnostics {
        let accessTokenMasked: String
        let refreshTokenPresent: Bool
        let expiresAtISO8601: String
        let jwtAudience: String
        let jwtScopes: String
    }

    func loadConfig() {
        clientId = (KeychainStore.getString(Keys.clientId) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        clientSecret = (KeychainStore.getString(Keys.clientSecret) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        let loadedRedirect = KeychainStore.getString(Keys.redirectURI)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        redirectURI = loadedRedirect.isEmpty ? TeslaConstants.defaultRedirectURI : loadedRedirect

        let loadedAudience = KeychainStore.getString(Keys.audience)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        audience = loadedAudience.isEmpty ? TeslaConstants.defaultAudience : loadedAudience

        let loadedFleetBase = KeychainStore.getString(Keys.fleetApiBase)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        fleetApiBase = loadedFleetBase.isEmpty ? TeslaConstants.defaultFleetApiBase : loadedFleetBase
    }

    func saveConfig() {
        do {
            try KeychainStore.setString(clientId.trimmingCharacters(in: .whitespacesAndNewlines), for: Keys.clientId)
            try KeychainStore.setString(clientSecret.trimmingCharacters(in: .whitespacesAndNewlines), for: Keys.clientSecret)
            try KeychainStore.setString(redirectURI.trimmingCharacters(in: .whitespacesAndNewlines), for: Keys.redirectURI)
            try KeychainStore.setString(audience.trimmingCharacters(in: .whitespacesAndNewlines), for: Keys.audience)
            try KeychainStore.setString(fleetApiBase.trimmingCharacters(in: .whitespacesAndNewlines), for: Keys.fleetApiBase)
            statusMessage = "Saved Tesla settings."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func signOut() {
        KeychainStore.delete(Keys.accessToken)
        KeychainStore.delete(Keys.refreshToken)
        KeychainStore.delete(Keys.expiresAt)
        KeychainStore.delete(Keys.selectedVin)
        KeychainStore.delete(Keys.selectedVehicleId)
        loadTokenState()
        statusMessage = "Signed out."
    }

    func getTokenDiagnostics() -> TokenDiagnostics {
        let access = KeychainStore.getString(Keys.accessToken) ?? ""
        let refresh = KeychainStore.getString(Keys.refreshToken) ?? ""
        let expiresAt = KeychainStore.getString(Keys.expiresAt) ?? ""

        let masked = mask(access)
        let claims = decodeJWTPayload(access)

        let aud = normalizeJWTValue(claims?["aud"])
        let scp = normalizeJWTValue(claims?["scp"]) ?? normalizeJWTValue(claims?["scope"])

        return TokenDiagnostics(
            accessTokenMasked: masked,
            refreshTokenPresent: !refresh.isEmpty,
            expiresAtISO8601: expiresAt,
            jwtAudience: aud ?? "(unknown)",
            jwtScopes: scp ?? "(unknown)"
        )
    }

    func makeAuthorizeURL() -> URL? {
        let trimmedClientId = clientId.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRedirect = redirectURI.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAudience = audience.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedClientId.isEmpty else {
            statusMessage = "Missing Tesla Client ID."
            return nil
        }
        guard !trimmedRedirect.isEmpty else {
            statusMessage = "Missing Redirect URI."
            return nil
        }

        let state = randomBase64URL(bytes: 16)
        let verifier = randomBase64URL(bytes: 48)
        let challenge = sha256Base64URL(verifier)

        do {
            try KeychainStore.setString(state, for: Keys.oauthState)
            try KeychainStore.setString(verifier, for: Keys.codeVerifier)
        } catch {
            statusMessage = error.localizedDescription
            return nil
        }

        var url = TeslaConstants.authorizeURL
        url.append(queryItems: [
            URLQueryItem(name: "client_id", value: trimmedClientId),
            URLQueryItem(name: "redirect_uri", value: trimmedRedirect),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: TeslaConstants.scopes),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            // When we add scopes later (ex: vehicle_location), this makes Tesla prompt only if missing.
            URLQueryItem(name: "prompt_missing_scopes", value: "true"),
            URLQueryItem(name: "audience", value: trimmedAudience.isEmpty ? TeslaConstants.defaultAudience : trimmedAudience)
        ])
        return url
    }

    func handleOAuthCallbackURL(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        let q = components.queryItems ?? []
        let code = q.first(where: { $0.name == "code" })?.value ?? ""
        let state = q.first(where: { $0.name == "state" })?.value ?? ""
        let error = q.first(where: { $0.name == "error" })?.value ?? q.first(where: { $0.name == "error_description" })?.value ?? ""

        guard error.isEmpty else {
            statusMessage = error
            return
        }

        guard !code.isEmpty else {
            statusMessage = "Missing OAuth code."
            return
        }

        Task {
            await exchangeAuthorizationCode(code: code, returnedState: state)
        }
    }

    func finishLoginManually() {
        let code = manualCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let state = manualState.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else {
            statusMessage = "Missing OAuth code."
            return
        }

        Task {
            await exchangeAuthorizationCode(code: code, returnedState: state)
        }
    }

    func ensureValidAccessToken() async throws -> String {
        try await refreshAccessToken(force: false)
    }

    func forceRefreshAccessToken() async throws -> String {
        try await refreshAccessToken(force: true)
    }

    private func refreshAccessToken(force: Bool) async throws -> String {
        if !force,
           let token = KeychainStore.getString(Keys.accessToken),
           let expiresAt = KeychainStore.getString(Keys.expiresAt),
           let date = iso.date(from: expiresAt),
           date.timeIntervalSinceNow > 60 {
            return token
        }

        guard let refresh = KeychainStore.getString(Keys.refreshToken), !refresh.isEmpty else {
            throw TeslaAuthError.notSignedIn
        }

        let trimmedClientId = clientId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedClientId.isEmpty else { throw TeslaAuthError.misconfigured("Missing Client ID") }
        let trimmedAudience = audience.trimmingCharacters(in: .whitespacesAndNewlines)

        var params = URLSearchParams()
        params.set("grant_type", "refresh_token")
        params.set("client_id", trimmedClientId)
        params.set("refresh_token", refresh)
        params.set("audience", trimmedAudience.isEmpty ? TeslaConstants.defaultAudience : trimmedAudience)

        let trimmedSecret = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSecret.isEmpty {
            params.set("client_secret", trimmedSecret)
        }

        var request = URLRequest(url: TeslaConstants.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = params.encoded()

        let (data, response) = try await session.data(for: request)
        let http = try TeslaHTTP.ensureHTTP(response)
        guard (200...299).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Refresh failed"
            throw TeslaAuthError.network(message)
        }

        let token = try JSONDecoder().decode(TeslaTokenResponse.self, from: data)
        try persist(token: token)
        loadTokenState()
        return token.access_token
    }

    private func exchangeAuthorizationCode(code: String, returnedState: String) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        let expectedState = KeychainStore.getString(Keys.oauthState) ?? ""
        guard !expectedState.isEmpty else {
            statusMessage = "OAuth session expired. Please try again."
            return
        }
        guard returnedState == expectedState else {
            statusMessage = "OAuth state mismatch. Please try again."
            return
        }

        let verifier = KeychainStore.getString(Keys.codeVerifier) ?? ""
        guard !verifier.isEmpty else {
            statusMessage = "Missing PKCE verifier. Please try again."
            return
        }

        let trimmedClientId = clientId.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSecret = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRedirect = redirectURI.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAudience = audience.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedClientId.isEmpty, !trimmedSecret.isEmpty, !trimmedRedirect.isEmpty else {
            statusMessage = "Missing Client ID / Client Secret / Redirect URI."
            return
        }

        var params = URLSearchParams()
        params.set("grant_type", "authorization_code")
        params.set("client_id", trimmedClientId)
        params.set("client_secret", trimmedSecret)
        params.set("code", code)
        params.set("code_verifier", verifier)
        params.set("redirect_uri", trimmedRedirect)
        params.set("audience", trimmedAudience.isEmpty ? TeslaConstants.defaultAudience : trimmedAudience)

        var request = URLRequest(url: TeslaConstants.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = params.encoded()

        do {
            let (data, response) = try await session.data(for: request)
            let http = try TeslaHTTP.ensureHTTP(response)
            guard (200...299).contains(http.statusCode) else {
                statusMessage = String(data: data, encoding: .utf8) ?? "Token exchange failed"
                return
            }

            let token = try JSONDecoder().decode(TeslaTokenResponse.self, from: data)
            try persist(token: token)
            KeychainStore.delete(Keys.oauthState)
            KeychainStore.delete(Keys.codeVerifier)
            loadTokenState()
            statusMessage = "Tesla connected."
            manualCode = ""
            manualState = ""
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func persist(token: TeslaTokenResponse) throws {
        let expiresAt = iso.string(from: Date().addingTimeInterval(TimeInterval(token.expires_in)))
        try KeychainStore.setString(token.access_token, for: Keys.accessToken)
        if let refresh = token.refresh_token, !refresh.isEmpty {
            try KeychainStore.setString(refresh, for: Keys.refreshToken)
        }
        try KeychainStore.setString(expiresAt, for: Keys.expiresAt)
    }

    private func loadTokenState() {
        let token = KeychainStore.getString(Keys.accessToken) ?? ""
        isSignedIn = !token.isEmpty
    }

    private func randomBase64URL(bytes: Int) -> String {
        var data = Data(count: bytes)
        let status = data.withUnsafeMutableBytes { ptr -> Int32 in
            guard let base = ptr.baseAddress else { return errSecParam }
            return SecRandomCopyBytes(kSecRandomDefault, bytes, base)
        }
        if status == errSecSuccess {
            return base64url(data)
        }

        // PKCE verifier fallback: keep flow alive even if secure random fails unexpectedly.
        let fallback = Data((UUID().uuidString + UUID().uuidString).utf8)
        return base64url(fallback)
    }

    private func sha256Base64URL(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return base64url(Data(digest))
    }

    private func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func mask(_ token: String) -> String {
        let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= 16 else { return "(short/empty)" }
        return String(t.prefix(8)) + "..." + String(t.suffix(6))
    }

    private func decodeJWTPayload(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        let payload = String(parts[1])
        guard let data = base64URLDecode(payload) else { return nil }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json
    }

    private func normalizeJWTValue(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let s = value as? String { return s }
        if let n = value as? NSNumber { return n.stringValue }
        if let a = value as? [Any] {
            let parts = a.compactMap { normalizeJWTValue($0) }
            if parts.isEmpty { return nil }
            return parts.joined(separator: " ")
        }
        return nil
    }

    private func base64URLDecode(_ input: String) -> Data? {
        var s = input.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let mod = s.count % 4
        if mod != 0 {
            s.append(String(repeating: "=", count: 4 - mod))
        }
        return Data(base64Encoded: s)
    }

    private enum Keys {
        static let clientId = "tesla.client_id"
        static let clientSecret = "tesla.client_secret"
        static let redirectURI = "tesla.redirect_uri"
        static let audience = "tesla.audience"
        static let fleetApiBase = "tesla.fleet_api_base"

        static let accessToken = "tesla.access_token"
        static let refreshToken = "tesla.refresh_token"
        static let expiresAt = "tesla.expires_at"
        static let selectedVin = "tesla.selected_vin"
        static let selectedVehicleId = "tesla.selected_vehicle_id"

        static let oauthState = "tesla.oauth_state"
        static let codeVerifier = "tesla.code_verifier"
    }
}

private struct TeslaTokenResponse: Decodable {
    let access_token: String
    let refresh_token: String?
    let expires_in: Int
}

private enum TeslaHTTP {
    static func ensureHTTP(_ response: URLResponse) throws -> HTTPURLResponse {
        guard let http = response as? HTTPURLResponse else {
            throw TeslaAuthError.network("Invalid server response.")
        }
        return http
    }
}

enum TeslaAuthError: LocalizedError {
    case notSignedIn
    case misconfigured(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Tesla login required."
        case .misconfigured(let message):
            return message
        case .network(let message):
            return message
        }
    }
}

private struct URLSearchParams {
    private var items: [(String, String)] = []

    mutating func set(_ key: String, _ value: String) {
        items.removeAll(where: { $0.0 == key })
        items.append((key, value))
    }

    func encoded() -> Data {
        let s = items
            .map { key, value in
                "\(escape(key))=\(escape(value))"
            }
            .joined(separator: "&")
        return Data(s.utf8)
    }

    private func escape(_ s: String) -> String {
        // application/x-www-form-urlencoded percent-encoding (spaces as %20 is accepted).
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }
}

private extension URL {
    mutating func append(queryItems: [URLQueryItem]) {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return }
        var existing = components.queryItems ?? []
        existing.append(contentsOf: queryItems)
        components.queryItems = existing
        if let updated = components.url {
            self = updated
        }
    }
}
