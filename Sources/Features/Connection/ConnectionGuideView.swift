import SwiftUI
import UIKit

struct ConnectionGuideView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var teslaAuth: TeslaAuthStore
    @EnvironmentObject private var kakaoConfig: KakaoConfigStore
    @State private var isTestingTesla = false
    @State private var isTestingSnapshot = false
    @State private var isTestingFleetStatus = false
    @State private var showManualLogin = false
    @State private var showKakaoKey = false
    @State private var showKakaoJSKey = false
    @State private var showAdvancedTesla = false
    @State private var showTeslaDiagnostics = false
    @State private var selectedTelemetrySource: TelemetrySource = AppConfig.telemetrySource
    @State private var backendURLText: String = AppConfig.backendBaseURLString
    @State private var backendAPITokenText: String = AppConfig.backendAPIToken
    @State private var showBackendToken = false
    @State private var isTestingBackend = false
    @State private var isDetectingBackend = false

    private let quickBackendCandidates: [String] = [
        "https://tesla.splui.com",
        "http://192.168.0.30:8787",
        "http://172.20.10.5:8787",
        "http://172.20.10.3:8787",
        "http://127.0.0.1:8787"
    ]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(.systemBackground), Color(.systemGray6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Sub Dashboard")
                        .font(.system(size: 44, weight: .heavy, design: .rounded))

                    statusBadge

                    Text("Fast Hotspot Setup")
                        .font(.system(size: 34, weight: .bold, design: .rounded))

                    StepCard(
                        index: 1,
                        title: "Prepare iPhone",
                        description: "Keep Bluetooth, Wi-Fi, and Personal Hotspot enabled on your iPhone."
                    )

                    StepCard(
                        index: 2,
                        title: "Set Auto-Join on iPad",
                        description: "Settings > Wi-Fi > Auto-Join Hotspot > Automatic."
                    )

                    StepCard(
                        index: 3,
                        title: "Use one-tap launch",
                        description: "Run the Start Car Mode shortcut or tap the blue button below."
                    )

                    telemetrySourcePanel
                    teslaConfigPanel
                    kakaoConfigPanel

                    Button {
                        let source = AppConfig.telemetrySource
                        if source == .backend || teslaAuth.isSignedIn {
                            router.enterCarMode(reason: .manualShortcut)
                            dismiss()
                        } else {
                            teslaAuth.statusMessage = "Please connect Tesla first, or switch Telemetry Source to Backend."
                        }
                    } label: {
                        Label("Start Car Mode", systemImage: "car.fill")
                    }
                    .buttonStyle(PrimaryCarButtonStyle())

                    HStack(spacing: 14) {
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                openURL(url)
                            }
                        } label: {
                            Label("Open Settings", systemImage: "gearshape")
                        }
                        .buttonStyle(SecondaryCarButtonStyle())

                        Button {
                            if let url = URL(string: "shortcuts://") {
                                openURL(url)
                            }
                        } label: {
                            Label("Shortcuts", systemImage: "square.grid.2x2")
                        }
                        .buttonStyle(SecondaryCarButtonStyle())
                    }
                }
                .padding(24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .onAppear {
            selectedTelemetrySource = AppConfig.telemetrySource
            backendURLText = AppConfig.backendBaseURLString
            backendAPITokenText = AppConfig.backendAPIToken
        }
    }

    private var statusBadge: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(networkMonitor.isConnected ? Color.green : Color.red)
                .frame(width: 12, height: 12)

            Text(networkMonitor.isConnected ? "Connected" : "Disconnected")
                .font(.system(size: 22, weight: .bold, design: .rounded))

            Text(networkMonitor.connectionTypeText)
                .font(.system(size: 20, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Capsule(style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var telemetrySourcePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Telemetry Source")
                .font(.system(size: 24, weight: .bold, design: .rounded))

            HStack(spacing: 10) {
                ForEach(TelemetrySource.allCases, id: \.rawValue) { source in
                    Button(source.title) {
                        selectedTelemetrySource = source
                        AppConfig.setTelemetrySource(source)
                        teslaAuth.statusMessage = "Telemetry source: \(source.title)"
                    }
                    .buttonStyle(
                        SecondaryCarButtonStyle(
                            fontSize: 18,
                            height: 56,
                            cornerRadius: 16,
                            fillColor: selectedTelemetrySource == source ? Color.blue.opacity(0.2) : Color(.tertiarySystemBackground),
                            strokeColor: selectedTelemetrySource == source ? Color.blue : Color.clear
                        )
                    )
                }
            }

            if selectedTelemetrySource == .backend {
                TextField("Backend URL", text: $backendURLText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)

                HStack(spacing: 10) {
                    Group {
                        if showBackendToken {
                            TextField("Backend API Token", text: $backendAPITokenText)
                        } else {
                            SecureField("Backend API Token", text: $backendAPITokenText)
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                    Button(showBackendToken ? "Hide" : "Show") {
                        showBackendToken.toggle()
                    }
                    .buttonStyle(SecondaryCarButtonStyle(fontSize: 18, height: 56, cornerRadius: 16))
                    .frame(width: 90)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(quickBackendCandidates, id: \.self) { candidate in
                            Button(shortBackendLabel(candidate)) {
                                applyBackendURLAndSave(candidate)
                            }
                            .buttonStyle(SecondaryCarButtonStyle(fontSize: 14, height: 44, cornerRadius: 12))
                        }
                    }
                    .padding(.vertical, 2)
                }

                HStack(spacing: 10) {
                    Button("Save URL") {
                        saveBackendURL()
                    }
                    .buttonStyle(SecondaryCarButtonStyle(fontSize: 18, height: 56, cornerRadius: 16))

                    Button("Save Token") {
                        saveBackendToken()
                    }
                    .buttonStyle(SecondaryCarButtonStyle(fontSize: 18, height: 56, cornerRadius: 16))

                    Button(isTestingBackend ? "Testing..." : "Test Backend") {
                        testBackendConnection()
                    }
                    .disabled(isTestingBackend)
                    .buttonStyle(SecondaryCarButtonStyle(fontSize: 18, height: 56, cornerRadius: 16))
                }

                Button(isDetectingBackend ? "Detecting..." : "Auto Detect Backend") {
                    autoDetectBackend()
                }
                .disabled(isDetectingBackend)
                .buttonStyle(SecondaryCarButtonStyle(fontSize: 18, height: 56, cornerRadius: 16))

                Text("Use this mode for TeslaMate/local backend. If your backend enforces auth, set Backend API Token.")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                Text("Direct Fleet mode uses Tesla OAuth in this app.")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var teslaConfigPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tesla Account")
                .font(.system(size: 24, weight: .bold, design: .rounded))

            HStack(spacing: 10) {
                Circle()
                    .fill(teslaAuth.isSignedIn ? Color.green : Color.red)
                    .frame(width: 10, height: 10)
                Text(teslaAuth.isSignedIn ? "Signed In" : "Not Signed In")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            TextField("Client ID", text: $teslaAuth.clientId)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            SecureField("Client Secret", text: $teslaAuth.clientSecret)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            TextField("Redirect URI", text: $teslaAuth.redirectURI)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)

            DisclosureGroup("Advanced (Audience / Fleet API Base)", isExpanded: $showAdvancedTesla) {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Audience", text: $teslaAuth.audience)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)

                    TextField("Fleet API Base", text: $teslaAuth.fleetApiBase)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)

                    Text("Scopes requested: \(TeslaConstants.scopes)")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 8)
            }
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .foregroundStyle(.secondary)

            DisclosureGroup("Manual Finish (if Open App fails)", isExpanded: $showManualLogin) {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("OAuth Code", text: $teslaAuth.manualCode)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    TextField("State", text: $teslaAuth.manualState)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Button(teslaAuth.isBusy ? "Working..." : "Exchange Code") {
                        teslaAuth.finishLoginManually()
                    }
                    .disabled(teslaAuth.isBusy)
                    .buttonStyle(SecondaryCarButtonStyle())
                    .frame(height: 70)
                }
                .padding(.top, 8)
            }
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .foregroundStyle(.secondary)

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Button("Save") {
                        teslaAuth.saveConfig()
                    }
                    .buttonStyle(SecondaryCarButtonStyle())

                    Button(teslaAuth.isBusy ? "Working..." : "Connect") {
                        teslaAuth.saveConfig()
                        guard let url = teslaAuth.makeAuthorizeURL() else { return }
                        openURL(url)
                    }
                    .disabled(teslaAuth.isBusy)
                    .buttonStyle(SecondaryCarButtonStyle())

                    Button("Sign Out") {
                        teslaAuth.signOut()
                    }
                    .buttonStyle(SecondaryCarButtonStyle())
                }

                HStack(spacing: 10) {
                    Button(isTestingTesla ? "Testing..." : "Test Vehicles") {
                        testTeslaConnection()
                    }
                    .disabled(isTestingTesla)
                    .buttonStyle(SecondaryCarButtonStyle())

                    Button(isTestingSnapshot ? "Testing..." : "Test Snapshot") {
                        testTeslaSnapshot()
                    }
                    .disabled(isTestingSnapshot)
                    .buttonStyle(SecondaryCarButtonStyle())

                    Button(isTestingFleetStatus ? "Testing..." : "Test Fleet Status") {
                        testTeslaFleetStatus()
                    }
                    .disabled(isTestingFleetStatus)
                    .buttonStyle(SecondaryCarButtonStyle())
                }
            }
            .frame(minHeight: 84)

            DisclosureGroup("Diagnostics (token / claims)", isExpanded: $showTeslaDiagnostics) {
                let diag = teslaAuth.getTokenDiagnostics()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Access token: \(diag.accessTokenMasked)")
                    Text("Refresh token: \(diag.refreshTokenPresent ? "present" : "missing")")
                    Text("ExpiresAt: \(diag.expiresAtISO8601.isEmpty ? "(missing)" : diag.expiresAtISO8601)")
                    Text("JWT aud: \(diag.jwtAudience)")
                    Text("JWT scopes: \(diag.jwtScopes)")
                }
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.top, 8)
            }
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .foregroundStyle(.secondary)

            if let message = teslaAuth.statusMessage {
                Text(message)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var kakaoConfigPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Navigation (Kakao)")
                .font(.system(size: 24, weight: .bold, design: .rounded))

            HStack(spacing: 10) {
                Circle()
                    .fill(kakaoConfig.restAPIKey.isEmpty ? Color.red : Color.green)
                    .frame(width: 10, height: 10)
                Text(kakaoConfig.restAPIKey.isEmpty ? "REST Key Missing" : "REST Key Set")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Group {
                    if showKakaoKey {
                        TextField("Kakao REST API Key", text: $kakaoConfig.restAPIKey)
                    } else {
                        SecureField("Kakao REST API Key", text: $kakaoConfig.restAPIKey)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

                Button(showKakaoKey ? "Hide" : "Show") {
                    showKakaoKey.toggle()
                }
                .buttonStyle(SecondaryCarButtonStyle(fontSize: 18, height: 56, cornerRadius: 16))
                .frame(width: 90)
            }

            HStack(spacing: 10) {
                Circle()
                    .fill(kakaoConfig.javaScriptKey.isEmpty ? Color.orange : Color.green)
                    .frame(width: 10, height: 10)
                Text(kakaoConfig.javaScriptKey.isEmpty ? "Map JS Key Optional (not set)" : "Map JS Key Set")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Group {
                    if showKakaoJSKey {
                        TextField("Kakao JavaScript Key (for Kakao map rendering)", text: $kakaoConfig.javaScriptKey)
                    } else {
                        SecureField("Kakao JavaScript Key (for Kakao map rendering)", text: $kakaoConfig.javaScriptKey)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

                Button(showKakaoJSKey ? "Hide" : "Show") {
                    showKakaoJSKey.toggle()
                }
                .buttonStyle(SecondaryCarButtonStyle(fontSize: 18, height: 56, cornerRadius: 16))
                .frame(width: 90)
            }

            Button("Save") {
                kakaoConfig.save()
            }
            .buttonStyle(SecondaryCarButtonStyle())
            .frame(height: 70)

            Text("REST key is used for search/route API. JavaScript key enables Kakao map rendering in Navi. In Kakao Developers, add Web platform domain `tesla.splui.com` for this JS key.")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func saveBackendURL() {
        do {
            try AppConfig.setBackendOverride(urlString: backendURLText)
            selectedTelemetrySource = .backend
            AppConfig.setTelemetrySource(.backend)
            backendURLText = AppConfig.backendBaseURLString
            teslaAuth.statusMessage = "Saved backend URL. Telemetry Source switched to Backend."
        } catch {
            teslaAuth.statusMessage = error.localizedDescription
        }
    }

    private func saveBackendToken() {
        do {
            try AppConfig.setBackendAPIToken(backendAPITokenText)
            backendAPITokenText = AppConfig.backendAPIToken
            let set = !backendAPITokenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            teslaAuth.statusMessage = set ? "Saved backend token." : "Cleared backend token."
        } catch {
            teslaAuth.statusMessage = error.localizedDescription
        }
    }

    private func applyBackendURLAndSave(_ urlString: String) {
        backendURLText = urlString
        saveBackendURL()
    }

    private func testBackendConnection() {
        guard !isTestingBackend else { return }
        isTestingBackend = true
        teslaAuth.statusMessage = nil

        Task {
            defer { isTestingBackend = false }
            do {
                let trimmed = backendURLText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    throw AppConfigError.invalidURL
                }
                if let info = try await probeBackendHealth(baseURLString: trimmed) {
                    teslaAuth.statusMessage = "Backend OK. mode=\(info.mode)"
                } else {
                    teslaAuth.statusMessage = "Backend OK."
                }
            } catch {
                teslaAuth.statusMessage = error.localizedDescription
            }
        }
    }

    private func autoDetectBackend() {
        guard !isDetectingBackend else { return }
        isDetectingBackend = true
        teslaAuth.statusMessage = "Detecting backend..."

        Task {
            defer { isDetectingBackend = false }

            let typed = backendURLText.trimmingCharacters(in: .whitespacesAndNewlines)
            let candidates = ([typed] + quickBackendCandidates)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .reduce(into: [String]()) { acc, next in
                    if !acc.contains(next) { acc.append(next) }
                }

            for candidate in candidates {
                if let info = try? await probeBackendHealth(baseURLString: candidate) {
                    backendURLText = candidate
                    selectedTelemetrySource = .backend
                    AppConfig.setTelemetrySource(.backend)
                    do {
                        try AppConfig.setBackendOverride(urlString: candidate)
                        teslaAuth.statusMessage = "Backend detected: \(candidate) (mode=\(info.mode))"
                    } catch {
                        teslaAuth.statusMessage = "Detected backend but save failed: \(error.localizedDescription)"
                    }
                    return
                }
            }

            teslaAuth.statusMessage = "No backend detected. Check Mac backend process and iPad hotspot network."
        }
    }

    private func probeBackendHealth(baseURLString: String) async throws -> BackendHealthInfo? {
        let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let baseURL = URL(string: trimmed), !trimmed.isEmpty else {
            throw AppConfigError.invalidURL
        }

        let healthURL = baseURL.appendingPathComponent("health")
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 2.5
        config.timeoutIntervalForResource = 4
        let session = URLSession(configuration: config)

        var request = URLRequest(url: healthURL)
        request.httpMethod = "GET"
        if let auth = AppConfig.backendAuthorizationHeader {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
        }
        if let apiKey = AppConfig.backendTokenForAPIKeyHeader {
            request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TelemetryError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw TelemetryError.server("Backend error: \(body)")
        }
        return try? JSONDecoder().decode(BackendHealthInfo.self, from: data)
    }

    private func shortBackendLabel(_ urlString: String) -> String {
        guard let url = URL(string: urlString), let host = url.host else {
            return urlString
        }
        let port = url.port.map(String.init) ?? "80"
        return "\(host):\(port)"
    }

    private func testTeslaConnection() {
        guard !isTestingTesla else { return }
        isTestingTesla = true
        teslaAuth.statusMessage = nil

        Task {
            defer { isTestingTesla = false }
            do {
                let diag = try await TeslaFleetService.shared.testVehiclesDiagnostics()
                teslaAuth.statusMessage = """
                Fleet OK. Vehicles: \(diag.count)
                URL: \(diag.requestURL)
                Network: \(diag.networkPathSummary)
                """
            } catch {
                teslaAuth.statusMessage = error.localizedDescription
            }
        }
    }

    private func testTeslaSnapshot() {
        guard !isTestingSnapshot else { return }
        isTestingSnapshot = true
        teslaAuth.statusMessage = nil

        Task {
            defer { isTestingSnapshot = false }
            do {
                let diag = try await TeslaFleetService.shared.testSnapshotDiagnostics()
                let loc = diag.mappedLocation
                if loc.isValid {
                    teslaAuth.statusMessage = String(format: "vehicle_data OK. Location: %.5f, %.5f", loc.lat, loc.lon)
                } else {
                    let driveLat = formatDiagValue(diag.driveStateLatitude)
                    let driveLon = formatDiagValue(diag.driveStateLongitude)
                    let driveNativeLat = formatDiagValue(diag.driveStateNativeLatitude)
                    let driveNativeLon = formatDiagValue(diag.driveStateNativeLongitude)
                    let locLat = formatDiagValue(diag.locationDataLatitude)
                    let locLon = formatDiagValue(diag.locationDataLongitude)
                    let locNativeLat = formatDiagValue(diag.locationDataNativeLatitude)
                    let locNativeLon = formatDiagValue(diag.locationDataNativeLongitude)
                    let rawLat = formatDiagValue(diag.rawLocationLatitude)
                    let rawLon = formatDiagValue(diag.rawLocationLongitude)
                    let accessTypeFlagged = diag.flaggedAccessType ?? "nil"
                    let plainRawLat = formatDiagValue(diag.plainRawLocationLatitude)
                    let plainRawLon = formatDiagValue(diag.plainRawLocationLongitude)
                    let accessTypePlain = diag.plainAccessType ?? "nil"
                    let endpointLat = formatDiagValue(diag.locationEndpointLatitude)
                    let endpointLon = formatDiagValue(diag.locationEndpointLongitude)
                    let endpointError = diag.locationEndpointError.trimmingCharacters(in: .whitespacesAndNewlines)
                    let likelyTeslaScopeFilter =
                        diag.driveStateLatitude == nil &&
                        diag.driveStateLongitude == nil &&
                        diag.driveStateNativeLatitude == nil &&
                        diag.driveStateNativeLongitude == nil &&
                        diag.locationDataLatitude == nil &&
                        diag.locationDataLongitude == nil &&
                        diag.locationDataNativeLatitude == nil &&
                        diag.locationDataNativeLongitude == nil &&
                        diag.rawLocationLatitude == nil &&
                        diag.rawLocationLongitude == nil &&
                        diag.plainRawLocationLatitude == nil &&
                        diag.plainRawLocationLongitude == nil &&
                        diag.locationEndpointLatitude == nil &&
                        diag.locationEndpointLongitude == nil &&
                        (diag.responseKeys.contains("drive_state") || diag.plainResponseKeys.contains("drive_state"))

                    let hint = likelyTeslaScopeFilter
                        ? "\nLikely Tesla-side filtering or propagation delay.\n1) Tesla app > Security & Privacy > Third Party Apps > Manage this app > Vehicle Location ON.\n2) Wait 10+ minutes after scope/permission changes.\n3) If still nil, complete Fleet key pairing for this VIN, then retry Wake + Refresh."
                        : ""
                    let endpointLine: String
                    if endpointError == "not_supported_on_fleet_api" {
                        endpointLine = "location_endpoint: not supported on Fleet API (404 expected)"
                    } else if endpointError.isEmpty {
                        endpointLine = "location_endpoint: \(endpointLat), \(endpointLon)"
                    } else {
                        endpointLine = "location_endpoint_error: \(endpointError)"
                    }
                    teslaAuth.statusMessage = """
                    vehicle_data OK, but location is missing.
                    drive_state: \(driveLat), \(driveLon)
                    drive_state(native): \(driveNativeLat), \(driveNativeLon)
                    location_data: \(locLat), \(locLon)
                    location_data(native): \(locNativeLat), \(locNativeLon)
                    raw_fallback: \(rawLat), \(rawLon)
                    response_keys(flagged): \(diag.responseKeys)
                    access_type(flagged): \(accessTypeFlagged)
                    raw_fallback(plain): \(plainRawLat), \(plainRawLon)
                    response_keys(plain): \(diag.plainResponseKeys)
                    access_type(plain): \(accessTypePlain)
                    \(endpointLine)
                    Try Wake + Refresh.\(hint)
                    """
                }
            } catch {
                teslaAuth.statusMessage = error.localizedDescription
            }
        }
    }

    private func testTeslaFleetStatus() {
        guard !isTestingFleetStatus else { return }
        isTestingFleetStatus = true
        teslaAuth.statusMessage = nil

        Task {
            defer { isTestingFleetStatus = false }
            do {
                let diag = try await TeslaFleetService.shared.testFleetStatusDiagnostics()
                let protocolText = diag.protocolRequired.map { $0 ? "true" : "false" } ?? "unknown"
                let keyCountText = diag.totalNumberOfKeys.map(String.init) ?? "unknown"
                let needsPairingHint: String
                if diag.protocolRequired == true,
                   (diag.totalNumberOfKeys == nil || diag.totalNumberOfKeys == 0) {
                    needsPairingHint = "\nLikely missing Fleet key pairing for this VIN."
                } else {
                    needsPairingHint = ""
                }

                teslaAuth.statusMessage = """
                fleet_status OK
                vin: \(diag.vin)
                vehicle_command_protocol_required: \(protocolText)
                total_number_of_keys: \(keyCountText)
                status_keys: \(diag.statusKeys)
                response_keys: \(diag.responseKeys)\(needsPairingHint)

                (raw_preview omitted to keep UI responsive)
                """
            } catch {
                teslaAuth.statusMessage = error.localizedDescription
            }
        }
    }

    private func formatDiagValue(_ value: Double?) -> String {
        guard let value else { return "nil" }
        return String(format: "%.5f", value)
    }
}

private struct BackendHealthInfo: Decodable {
    let ok: Bool
    let mode: String
}

private struct StepCard: View {
    let index: Int
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(index)")
                .font(.system(size: 26, weight: .black, design: .rounded))
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.blue.opacity(0.14)))

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                Text(description)
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }
}
