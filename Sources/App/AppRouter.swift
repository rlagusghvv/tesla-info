import Foundation

@MainActor
final class AppRouter: ObservableObject {
    enum Screen {
        case connectionGuide
        case carMode
    }

    enum TriggerReason: String {
        case launch
        case alreadyConnected
        case networkConnected
        case manualShortcut
        case deepLink
    }

    @Published private(set) var screen: Screen = .connectionGuide
    @Published private(set) var lastReason: TriggerReason = .launch

    func showGuide() {
        screen = .connectionGuide
    }

    func enterCarMode(reason: TriggerReason) {
        lastReason = reason
        screen = .carMode
    }

    func handleDeepLink(_ url: URL) {
        guard url.scheme == "myapp" else { return }

        let host = url.host?.lowercased() ?? ""
        if host == "car" || url.path.lowercased() == "/car" {
            enterCarMode(reason: .deepLink)
        }
    }
}

@MainActor
final class AdminSessionStore: ObservableObject {
    static let shared = AdminSessionStore()

    @Published private(set) var isLoggedIn: Bool = false
    @Published var isBusy: Bool = false
    @Published var statusMessage: String?
    @Published var username: String = "admin"
    @Published var backendURL: String = AppConfig.backendBaseURLString

    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 20
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)

        if let storedUsername = KeychainStore.getString(Keys.username)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !storedUsername.isEmpty {
            username = storedUsername
        }

        if let token = loadSessionToken(), !token.isEmpty {
            isLoggedIn = true
            Task { await validateStoredSession() }
        }
    }

    func login(password: String) async {
        guard !isBusy else { return }
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBackend = backendURL.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedUsername.isEmpty else {
            statusMessage = "아이디를 입력하세요."
            return
        }
        guard !trimmedPassword.isEmpty else {
            statusMessage = "비밀번호를 입력하세요."
            return
        }
        guard let baseURL = URL(string: trimmedBackend) else {
            statusMessage = "백엔드 URL 형식이 올바르지 않습니다."
            return
        }

        isBusy = true
        defer { isBusy = false }
        statusMessage = nil

        do {
            let payload = AuthLoginRequest(username: trimmedUsername, password: trimmedPassword)
            let body = try encoder.encode(payload)
            let (data, http) = try await request(
                baseURL: baseURL,
                path: "api/auth/login",
                method: "POST",
                body: body,
                sessionToken: nil
            )
            let envelope = try decode(AuthLoginEnvelope.self, from: data)
            guard (200 ... 299).contains(http.statusCode), envelope.ok else {
                throw AdminSessionError.server(envelope.message ?? "로그인에 실패했습니다.")
            }
            guard let sessionToken = envelope.sessionToken, !sessionToken.isEmpty else {
                throw AdminSessionError.server("세션 토큰이 비어 있습니다.")
            }

            try KeychainStore.setString(trimmedUsername, for: Keys.username)
            try KeychainStore.setString(sessionToken, for: Keys.sessionToken)
            try AppConfig.setBackendOverride(urlString: baseURL.absoluteString)

            if let bootstrap = envelope.bootstrap {
                try applyBootstrap(bootstrap, fallbackBaseURL: baseURL)
            } else {
                try await fetchAndApplyBootstrap(baseURL: baseURL, sessionToken: sessionToken)
            }

            username = trimmedUsername
            backendURL = baseURL.absoluteString
            isLoggedIn = true
            statusMessage = "로그인 성공"
        } catch {
            clearSession(localOnly: true)
            statusMessage = error.localizedDescription
        }
    }

    func signup(password: String, confirmPassword: String) async {
        guard !isBusy else { return }
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedConfirmPassword = confirmPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBackend = backendURL.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedUsername.isEmpty else {
            statusMessage = "아이디를 입력하세요."
            return
        }
        guard trimmedPassword.count >= 4 else {
            statusMessage = "비밀번호는 4자 이상이어야 합니다."
            return
        }
        guard trimmedPassword == trimmedConfirmPassword else {
            statusMessage = "비밀번호 확인이 일치하지 않습니다."
            return
        }
        guard let baseURL = URL(string: trimmedBackend) else {
            statusMessage = "백엔드 URL 형식이 올바르지 않습니다."
            return
        }

        isBusy = true
        defer { isBusy = false }
        statusMessage = nil

        do {
            let payload = AuthSignupRequest(username: trimmedUsername, password: trimmedPassword)
            let body = try encoder.encode(payload)
            let (data, http) = try await request(
                baseURL: baseURL,
                path: "api/auth/signup",
                method: "POST",
                body: body,
                sessionToken: nil
            )
            let envelope = try decode(AuthLoginEnvelope.self, from: data)
            guard (200 ... 299).contains(http.statusCode), envelope.ok else {
                throw AdminSessionError.server(envelope.message ?? "회원가입에 실패했습니다.")
            }
            guard let sessionToken = envelope.sessionToken, !sessionToken.isEmpty else {
                throw AdminSessionError.server("세션 토큰이 비어 있습니다.")
            }

            try KeychainStore.setString(trimmedUsername, for: Keys.username)
            try KeychainStore.setString(sessionToken, for: Keys.sessionToken)
            try AppConfig.setBackendOverride(urlString: baseURL.absoluteString)

            if let bootstrap = envelope.bootstrap {
                try applyBootstrap(bootstrap, fallbackBaseURL: baseURL)
            } else {
                try await fetchAndApplyBootstrap(baseURL: baseURL, sessionToken: sessionToken)
            }

            username = trimmedUsername
            backendURL = baseURL.absoluteString
            isLoggedIn = true
            statusMessage = "회원가입 완료"
        } catch {
            clearSession(localOnly: true)
            statusMessage = error.localizedDescription
        }
    }

    func syncUserKeysToBackend(
        teslaClientId: String,
        teslaClientSecret: String,
        teslaRedirectURI: String,
        teslaAudience: String,
        teslaFleetApiBase: String,
        kakaoRestAPIKey: String,
        kakaoJavaScriptKey: String
    ) async throws {
        guard let token = loadSessionToken(), !token.isEmpty else {
            throw AdminSessionError.server("로그인이 필요합니다.")
        }
        let trimmedBackend = backendURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let baseURL = URL(string: trimmedBackend) else {
            throw AdminSessionError.server("백엔드 URL 형식이 올바르지 않습니다.")
        }

        let payload = AuthUserKeysUpdateRequest(
            tesla: AuthTeslaKeysUpdatePayload(
                clientId: teslaClientId,
                clientSecret: teslaClientSecret,
                redirectURI: teslaRedirectURI,
                audience: teslaAudience,
                fleetApiBase: teslaFleetApiBase
            ),
            kakao: AuthKakaoKeysUpdatePayload(
                restAPIKey: kakaoRestAPIKey,
                javaScriptKey: kakaoJavaScriptKey
            )
        )
        let body = try encoder.encode(payload)
        let (data, http) = try await request(
            baseURL: baseURL,
            path: "api/auth/keys",
            method: "POST",
            body: body,
            sessionToken: token
        )
        let envelope = try decode(AuthBootstrapEnvelope.self, from: data)
        guard (200 ... 299).contains(http.statusCode), envelope.ok else {
            throw AdminSessionError.server(envelope.message ?? "키 저장에 실패했습니다.")
        }
        if let bootstrap = envelope.bootstrap {
            try applyBootstrap(bootstrap, fallbackBaseURL: baseURL)
        }
    }

    func logout() {
        let currentToken = loadSessionToken()
        let currentBaseURL = URL(string: backendURL.trimmingCharacters(in: .whitespacesAndNewlines))

        clearSession(localOnly: true)
        statusMessage = "로그아웃되었습니다."

        guard let token = currentToken, !token.isEmpty, let baseURL = currentBaseURL else {
            return
        }

        Task {
            _ = try? await request(baseURL: baseURL, path: "api/auth/logout", method: "POST", body: nil, sessionToken: token)
        }
    }

    func refreshSession() async {
        guard isLoggedIn else { return }
        await validateStoredSession()
    }

    private func validateStoredSession() async {
        guard let token = loadSessionToken(), !token.isEmpty else {
            clearSession(localOnly: true)
            return
        }
        guard let baseURL = URL(string: backendURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            clearSession(localOnly: true)
            statusMessage = "저장된 백엔드 URL이 잘못되었습니다."
            return
        }

        do {
            let (data, http) = try await request(
                baseURL: baseURL,
                path: "api/auth/me",
                method: "GET",
                body: nil,
                sessionToken: token
            )
            let envelope = try decode(AuthStatusEnvelope.self, from: data)
            guard (200 ... 299).contains(http.statusCode), envelope.ok else {
                throw AdminSessionError.server(envelope.message ?? "세션이 만료되었습니다.")
            }
            try await fetchAndApplyBootstrap(baseURL: baseURL, sessionToken: token)
            isLoggedIn = true
        } catch {
            clearSession(localOnly: true)
            statusMessage = "세션이 만료되었습니다. 다시 로그인해 주세요."
        }
    }

    private func fetchAndApplyBootstrap(baseURL: URL, sessionToken: String) async throws {
        let (data, http) = try await request(
            baseURL: baseURL,
            path: "api/auth/bootstrap",
            method: "GET",
            body: nil,
            sessionToken: sessionToken
        )
        let envelope = try decode(AuthBootstrapEnvelope.self, from: data)
        guard (200 ... 299).contains(http.statusCode), envelope.ok, let bootstrap = envelope.bootstrap else {
            throw AdminSessionError.server(envelope.message ?? "부트스트랩 정보를 불러오지 못했습니다.")
        }
        try applyBootstrap(bootstrap, fallbackBaseURL: baseURL)
    }

    private func applyBootstrap(_ bootstrap: AuthBootstrapPayload, fallbackBaseURL: URL) throws {
        let resolvedBackendURL = (bootstrap.backendBaseURL ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let backend = resolvedBackendURL.isEmpty ? fallbackBaseURL.absoluteString : resolvedBackendURL
        try AppConfig.setBackendOverride(urlString: backend)
        backendURL = backend

        let backendToken = bootstrap.backendApiToken.trimmingCharacters(in: .whitespacesAndNewlines)
        try AppConfig.setBackendAPIToken(backendToken)

        let telemetrySource = (bootstrap.telemetrySource ?? "").lowercased()
        if telemetrySource == TelemetrySource.backend.rawValue {
            AppConfig.setTelemetrySource(.backend)
        }

        let tesla = TeslaAuthStore.shared
        tesla.clientId = bootstrap.tesla.clientId
        tesla.clientSecret = bootstrap.tesla.clientSecret
        tesla.redirectURI = bootstrap.tesla.redirectURI
        tesla.audience = bootstrap.tesla.audience
        tesla.fleetApiBase = bootstrap.tesla.fleetApiBase
        tesla.saveConfig()

        if let kakao = bootstrap.kakao {
            let kakaoStore = KakaoConfigStore.shared
            kakaoStore.restAPIKey = kakao.restAPIKey
            kakaoStore.javaScriptKey = kakao.javaScriptKey
            kakaoStore.save()
        }
    }

    private func request(
        baseURL: URL,
        path: String,
        method: String,
        body: Data?,
        sessionToken: String?
    ) async throws -> (Data, HTTPURLResponse) {
        let url = path
            .split(separator: "/")
            .reduce(baseURL) { partial, segment in
                partial.appendingPathComponent(String(segment))
            }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let sessionToken, !sessionToken.isEmpty {
            request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
            request.setValue(sessionToken, forHTTPHeaderField: "X-App-Session")
        }
        request.httpBody = body

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw AdminSessionError.network(error.localizedDescription)
        } catch {
            throw AdminSessionError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AdminSessionError.network("서버 응답이 올바르지 않습니다.")
        }
        return (data, http)
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                throw AdminSessionError.server(text)
            }
            throw AdminSessionError.server("응답 파싱에 실패했습니다.")
        }
    }

    private func loadSessionToken() -> String? {
        let token = (KeychainStore.getString(Keys.sessionToken) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }

    private func clearSession(localOnly: Bool) {
        KeychainStore.delete(Keys.sessionToken)
        isLoggedIn = false
        if !localOnly {
            statusMessage = nil
        }
    }

    private enum Keys {
        static let username = "app.admin.username"
        static let sessionToken = "app.admin.session_token"
    }
}

private struct AuthLoginRequest: Encodable {
    let username: String
    let password: String
}

private struct AuthSignupRequest: Encodable {
    let username: String
    let password: String
}

private struct AuthUserKeysUpdateRequest: Encodable {
    let tesla: AuthTeslaKeysUpdatePayload
    let kakao: AuthKakaoKeysUpdatePayload
}

private struct AuthTeslaKeysUpdatePayload: Encodable {
    let clientId: String
    let clientSecret: String
    let redirectURI: String
    let audience: String
    let fleetApiBase: String
}

private struct AuthKakaoKeysUpdatePayload: Encodable {
    let restAPIKey: String
    let javaScriptKey: String
}

private struct AuthStatusEnvelope: Decodable {
    let ok: Bool
    let message: String?
}

private struct AuthLoginEnvelope: Decodable {
    let ok: Bool
    let message: String?
    let sessionToken: String?
    let bootstrap: AuthBootstrapPayload?
}

private struct AuthBootstrapEnvelope: Decodable {
    let ok: Bool
    let message: String?
    let bootstrap: AuthBootstrapPayload?
}

private struct AuthBootstrapPayload: Decodable {
    let backendBaseURL: String?
    let backendApiToken: String
    let telemetrySource: String?
    let tesla: AuthTeslaKeys
    let kakao: AuthKakaoKeys?
}

private struct AuthTeslaKeys: Decodable {
    let clientId: String
    let clientSecret: String
    let redirectURI: String
    let audience: String
    let fleetApiBase: String
}

private struct AuthKakaoKeys: Decodable {
    let restAPIKey: String
    let javaScriptKey: String
}

private enum AdminSessionError: LocalizedError {
    case server(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .server(let message):
            return message
        case .network(let message):
            return "네트워크 오류: \(message)"
        }
    }
}
