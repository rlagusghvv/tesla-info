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
    @State private var showManualLogin = false
    @State private var showKakaoKey = false
    @State private var showAdvancedTesla = false
    @State private var showTeslaDiagnostics = false

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

                    teslaConfigPanel
                    kakaoConfigPanel

                    Button {
                        if teslaAuth.isSignedIn {
                            router.enterCarMode(reason: .manualShortcut)
                            dismiss()
                        } else {
                            teslaAuth.statusMessage = "Please connect Tesla first."
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
                Text(kakaoConfig.restAPIKey.isEmpty ? "API Key Missing" : "API Key Set")
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

            Button("Save") {
                kakaoConfig.save()
            }
            .buttonStyle(SecondaryCarButtonStyle())
            .frame(height: 70)

            Text("Used for in-app destination search and routing. For App Store release, keys should be proxied by a backend.")
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

    private func testTeslaConnection() {
        guard !isTestingTesla else { return }
        isTestingTesla = true
        teslaAuth.statusMessage = nil

        Task {
            defer { isTestingTesla = false }
            do {
                let count = try await TeslaFleetService.shared.testVehiclesCount()
                teslaAuth.statusMessage = "Fleet OK. Vehicles: \(count)"
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
                    let locLat = formatDiagValue(diag.locationDataLatitude)
                    let locLon = formatDiagValue(diag.locationDataLongitude)
                    let rawLat = formatDiagValue(diag.rawLocationLatitude)
                    let rawLon = formatDiagValue(diag.rawLocationLongitude)
                    let plainRawLat = formatDiagValue(diag.plainRawLocationLatitude)
                    let plainRawLon = formatDiagValue(diag.plainRawLocationLongitude)
                    teslaAuth.statusMessage = """
                    vehicle_data OK, but location is missing.
                    drive_state: \(driveLat), \(driveLon)
                    location_data: \(locLat), \(locLon)
                    raw_fallback: \(rawLat), \(rawLon)
                    response_keys(flagged): \(diag.responseKeys)
                    raw_fallback(plain): \(plainRawLat), \(plainRawLon)
                    response_keys(plain): \(diag.plainResponseKeys)
                    Try Wake + Refresh.
                    """
                }
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
