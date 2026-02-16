import CoreLocation
import SwiftUI
import UIKit
import WebKit

private final class WebViewStore: ObservableObject {
    lazy var webView: WKWebView = {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        return WKWebView(frame: .zero, configuration: configuration)
    }()
}

@MainActor
private final class DeviceLocationTracker: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var latestLocation: CLLocation?
    @Published private(set) var latestSpeedKph: Double?
    @Published private(set) var latestCourseDeg: Double?
    @Published private(set) var lastUpdatedAt: Date = .distantPast

    // Called after each CLLocation update (used to drive alerts even when UI isn't actively rendering).
    var onTick: (() -> Void)?

    private let manager = CLLocationManager()
    private var hasStartedUpdates = false
    private var hasRequestedAlwaysAuthorization = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = 2
        manager.activityType = .automotiveNavigation
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = false
        authorizationStatus = manager.authorizationStatus
    }

    func start() {
        guard CLLocationManager.locationServicesEnabled() else { return }
        authorizationStatus = manager.authorizationStatus
        if authorizationStatus == .notDetermined {
            manager.requestAlwaysAuthorization()
            return
        }
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            if authorizationStatus == .authorizedWhenInUse && !hasRequestedAlwaysAuthorization {
                hasRequestedAlwaysAuthorization = true
                manager.requestAlwaysAuthorization()
            }
            manager.startUpdatingLocation()
            manager.startMonitoringSignificantLocationChanges()
            // Force a fresh callback even when the device is stationary (helps on app resume).
            manager.requestLocation()
            hasStartedUpdates = true
        }
    }

    func stop() {
        guard hasStartedUpdates else { return }
        manager.stopUpdatingLocation()
        manager.stopMonitoringSignificantLocationChanges()
        hasStartedUpdates = false
    }

    private func makeVehicleLocation(from location: CLLocation) -> VehicleLocation? {
        let coordinate = location.coordinate
        guard (-90.0...90.0).contains(coordinate.latitude) else { return nil }
        guard (-180.0...180.0).contains(coordinate.longitude) else { return nil }
        guard abs(coordinate.latitude) > 0.000_01 || abs(coordinate.longitude) > 0.000_01 else { return nil }
        return VehicleLocation(lat: coordinate.latitude, lon: coordinate.longitude)
    }

    var currentVehicleLocation: VehicleLocation? {
        guard let location = latestLocation else { return nil }
        let age = Date().timeIntervalSince(lastUpdatedAt)
        // Best-effort (route sync can start even if GPS is still settling).
        guard age <= 600 else { return nil }
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 2_000 else { return nil }
        return makeVehicleLocation(from: location)
    }

    var alertVehicleLocation: VehicleLocation? {
        guard let location = latestLocation else { return nil }
        let age = Date().timeIntervalSince(lastUpdatedAt)
        // Stricter gate: alerts are only safe when GPS is fresh and accurate.
        guard age <= 12 else { return nil }
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 90 else { return nil }
        return makeVehicleLocation(from: location)
    }

    var currentSpeedKph: Double? {
        guard let speed = latestSpeedKph else { return nil }
        let age = Date().timeIntervalSince(lastUpdatedAt)
        guard age <= 12 else { return nil }
        return max(0, speed)
    }

    var currentCourseDeg: Double? {
        guard let course = latestCourseDeg else { return nil }
        let age = Date().timeIntervalSince(lastUpdatedAt)
        guard age <= 12 else { return nil }
        guard course.isFinite else { return nil }
        return course
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus
            if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
                if authorizationStatus == .authorizedWhenInUse && !hasRequestedAlwaysAuthorization {
                    hasRequestedAlwaysAuthorization = true
                    manager.requestAlwaysAuthorization()
                }
                manager.startUpdatingLocation()
                manager.startMonitoringSignificantLocationChanges()
                manager.requestLocation()
                hasStartedUpdates = true
            } else if authorizationStatus == .denied || authorizationStatus == .restricted {
                manager.stopUpdatingLocation()
                manager.stopMonitoringSignificantLocationChanges()
                hasStartedUpdates = false
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        Task { @MainActor in
            let now = Date()
            let previousLocation = latestLocation
            latestLocation = latest
            if latest.speed >= 0 {
                latestSpeedKph = latest.speed * 3.6
            } else if let prev = previousLocation {
                let dt = now.timeIntervalSince(lastUpdatedAt)
                if dt >= 0.3, dt <= 8, latest.horizontalAccuracy >= 0, latest.horizontalAccuracy <= 120 {
                    let meters = latest.distance(from: prev)
                    let computed = (meters / dt) * 3.6
                    if computed.isFinite {
                        latestSpeedKph = computed
                    }
                }
            }
            if latest.course >= 0 {
                latestCourseDeg = latest.course
            }
            lastUpdatedAt = now
            onTick?()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Keep telemetry fallback active when GPS fails temporarily.
        Task { @MainActor in
            if (error as NSError).code == CLError.denied.rawValue {
                hasStartedUpdates = false
            }
        }
    }
}

struct CarModeView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    @EnvironmentObject private var teslaAuth: TeslaAuthStore
    @EnvironmentObject private var kakaoConfig: KakaoConfigStore
    @StateObject private var viewModel = CarModeViewModel()
    @StateObject private var naviModel = KakaoNavigationViewModel()
    @StateObject private var deviceLocationTracker = DeviceLocationTracker()
    @StateObject private var speedCameraAlertEngine = SpeedCameraAlertEngine()
    @State private var lastSyncedTeslaRouteSignature: String = ""
    @State private var lastTeslaRouteAttemptAt: Date = .distantPast
    @State private var routeDriftStrikeCount: Int = 0
    @State private var lastAssistNetworkTickAt: Date = .distantPast
    @State private var naviHUDVisible: Bool = true
    @State private var showChromeInNavi: Bool = false
    @State private var showAccountSheet: Bool = false

    @State private var showDiagnosticsSheet: Bool = false
    @State private var diagnosticsStatusText: String?
    @State private var diagnosticsLogDump: String = ""
    @State private var diagnosticsCameraCount: Int = 0

    @StateObject private var mediaWebViewStore = WebViewStore()
    @State private var mediaOverlaySize: CGSize = .zero
    @State private var mediaOverlayOrigin: CGPoint = .zero
    @State private var mediaOverlayDragAnchor: CGPoint = .zero
    @State private var mediaOverlayResizeAnchor: CGSize = .zero
    @State private var hasInitializedMediaOverlay = false

    private let mediaToolbarHeight: CGFloat = 64
    private let mediaMinSize = CGSize(width: 330, height: 220)
    private let phoneLayoutMaxWidth: CGFloat = 430
    private let useUltraLiteAssist = true

    // Design Contract: keep spacing and card metrics on shared tokens.
    private let uiSectionSpacing: CGFloat = 16
    private let uiCardPadding: CGFloat = 16
    private let uiCardCornerRadius: CGFloat = 20

    private var usePhoneSizedLayout: Bool {
        // Product decision: run car mode UI in iPhone-size layout on all devices.
        true
    }

    private var isFullscreenNaviActive: Bool {
        viewModel.centerMode == .navi && !showChromeInNavi && !usePhoneSizedLayout
    }

    private var effectiveNaviLocation: VehicleLocation {
        // GPS-only: never fall back to Fleet/telemetry location.
        deviceLocationTracker.currentVehicleLocation ?? VehicleLocation(lat: 0, lon: 0)
    }

    private var effectiveNaviSpeedKph: Double {
        // GPS-first: Fleet/Backend speed is too delayed for real driving assist.
        deviceLocationTracker.currentSpeedKph ?? 0
    }

    private var effectiveLocationSourceLabel: String {
        "아이폰 GPS"
    }

    private var effectiveLocationText: String {
        guard CLLocationManager.locationServicesEnabled() else {
            return "Location Services OFF"
        }

        switch deviceLocationTracker.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            break
        case .notDetermined:
            return "Requesting permission..."
        case .denied, .restricted:
            return "Permission denied"
        @unknown default:
            return "Permission unknown"
        }

        if let gps = deviceLocationTracker.currentVehicleLocation, gps.isValid {
            return String(format: "%.5f, %.5f", gps.lat, gps.lon)
        }
        return "GPS fix pending..."
    }

    private var speedCameraStatusText: String? {
        guard viewModel.snapshot.navigation != nil else {
            return "단속 카메라: Tesla route OFF (테슬라에서 경로 설정 필요)"
        }

        if !CLLocationManager.locationServicesEnabled() {
            return "단속 카메라: iOS 위치 서비스 OFF"
        }

        if deviceLocationTracker.authorizationStatus == .denied || deviceLocationTracker.authorizationStatus == .restricted {
            return "단속 카메라: 위치 권한 없음 (설정에서 허용 필요)"
        }

        let key = kakaoConfig.restAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty {
            return "단속 카메라: Kakao REST 키 필요 (Account에서 설정)"
        }

        guard let gps = deviceLocationTracker.currentVehicleLocation, gps.isValid else {
            return "단속 카메라: GPS 수신 대기중 (실외에서 5-10초)"
        }

        if deviceLocationTracker.alertVehicleLocation == nil {
            let age = Date().timeIntervalSince(deviceLocationTracker.lastUpdatedAt)
            let accuracy = deviceLocationTracker.latestLocation?.horizontalAccuracy ?? -1
            if age > 12 {
                if effectiveNaviSpeedKph < 2 {
                    return "단속 카메라: 정지 중 (GPS 업데이트 \(Int(age))초 전) · 경보 대기"
                }
                return "단속 카메라: GPS 업데이트 지연 (\(Int(age))초 전) · 경보 대기"
            }
            if accuracy.isFinite, accuracy > 90 {
                return "단속 카메라: GPS 정확도 낮음 (±\(Int(accuracy))m) · 경보 대기"
            }
            return "단속 카메라: GPS 품질 확인중 · 경보 대기"
        }
        if naviModel.route == nil {
            return "단속 카메라: 경로 동기화 중..."
        }
        if naviModel.isIndexingSpeedCameras {
            return "단속 카메라: 경로 카메라 분석 중..."
        }
        if naviModel.speedCameraGuideCount == 0 {
            return "단속 카메라: 이 경로에서 찾지 못함"
        }
        if naviModel.nextSpeedCameraGuide == nil {
            return "단속 카메라: 경로 카메라 \(naviModel.speedCameraGuideCount)개 · 다음 계산 중..."
        }
        if let meters = naviModel.distanceToNextSpeedCameraMeters() {
            if let limit = naviModel.nextSpeedCameraLimitKph, limit > 0 {
                return "단속 카메라: \(meters)m · 제한 \(limit)"
            }
            return "단속 카메라: \(meters)m"
        }
        return "단속 카메라: 계산 중"
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }

    var body: some View {
        GeometryReader { root in
            let isFullscreenNavi = isFullscreenNaviActive

            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.96, green: 0.97, blue: 0.99),
                        Color(red: 0.91, green: 0.94, blue: 0.99)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                content
                    .padding(.horizontal, isFullscreenNavi ? 0 : 16)
                    // Avoid double-safe-area padding (ScrollView already applies automatic insets on iOS).
                    .padding(.top, 0)
                    .padding(.bottom, isFullscreenNavi ? 0 : 12)

                if !teslaAuth.isSignedIn {
                    VStack(spacing: 14) {
                        Text("Tesla login required")
                            .font(.system(size: 22, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color.black.opacity(0.86))

                        Text("Exit Car Mode to connect your Tesla account.")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.black.opacity(0.64))

                        Button {
                            showAccountSheet = true
                        } label: {
                            Label("Go to Tesla Account", systemImage: "person.crop.circle")
                        }
                        .buttonStyle(SecondaryCarButtonStyle())
                        .frame(height: 70)
                    }
                    .padding(18)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white)
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
                            )
                    )
                    .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 6)
                    .padding(24)
                }
            }
        }
        .sheet(isPresented: $showAccountSheet) {
            ConnectionGuideView()
                .environmentObject(networkMonitor)
                .environmentObject(router)
                .environmentObject(teslaAuth)
                .environmentObject(kakaoConfig)
        }
        .sheet(isPresented: $showDiagnosticsSheet) {
            diagnosticsSheet
        }
        .onAppear {
            appLog(.app, "CarMode appear", level: .info)
            viewModel.start()
            deviceLocationTracker.start()
            // Drive the assist loop from CLLocation updates (works even when SwiftUI is not actively redrawing).
            deviceLocationTracker.onTick = { handleUltraLiteAssistTick() }
            Task { await PublicSpeedCameraStore.shared.prewarm() }
        }
        .onDisappear {
            appLog(.app, "CarMode disappear", level: .info)
            Task { await AppLogStore.shared.persist() }
            viewModel.stop()
            deviceLocationTracker.stop()
            deviceLocationTracker.onTick = nil
        }
        .onChange(of: scenePhase) { _, next in
            switch next {
            case .active:
                appLog(.app, "scenePhase active", level: .info)
                viewModel.start()
                deviceLocationTracker.start()
            case .inactive, .background:
                appLog(.app, "scenePhase background", level: .info)
                Task { await AppLogStore.shared.persist() }
                viewModel.stop()
            @unknown default:
                break
            }
        }
        .onChange(of: viewModel.snapshot.navigation) { _, _ in
            guard useUltraLiteAssist else { return }
            handleTeslaNavigationChanged()
        }
    }

    private var content: some View {
        GeometryReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: uiSectionSpacing) {
                    regularCenterPanel
                    sidePanel
                }
                .padding(.bottom, uiSectionSpacing)
            }
            .contentMargins(.top, 0, for: .scrollContent)
            .frame(maxWidth: min(phoneLayoutMaxWidth, proxy.size.width))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private var suspendedCenterPanel: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                CenterModeSegmentedControl(selection: $viewModel.centerMode)
                    .frame(maxWidth: .infinity)
                    .layoutPriority(1)

                headerIconButton(systemImage: "person.crop.circle.fill", accessibilityLabel: "계정 설정(비활성)") {}
                    .disabled(true)
            }

            VStack(spacing: 10) {
                Image(systemName: "pause.circle.fill")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))

                Text("Setup Mode")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)

                Text("Map and polling are paused for stability while Account is open.")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
            )

            Text("Source: \(viewModel.snapshot.source)")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }

    private var suspendedSidePanel: some View {
        VStack(spacing: 12) {
            card {
                VStack(alignment: .leading, spacing: 6) {
                    Text(viewModel.snapshot.vehicle.displayName)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("Account panel active")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.75))
                }
            }

            card {
                Text("Controls are temporarily paused.")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var centerPanel: some View {
        if isFullscreenNaviActive {
            fullscreenNaviPanel
        } else {
            regularCenterPanel
        }
    }

    private var fullscreenNaviPanel: some View {
        ZStack(alignment: .bottomTrailing) {
            naviPane

            // Keep access to Account / Controls even in fullscreen mode.
            VStack(spacing: 10) {
                headerIconButton(systemImage: "hand.tap", accessibilityLabel: "화면 컨트롤 표시 전환") {
                    toggleChromeInNavi()
                }
                headerIconButton(systemImage: "person.crop.circle", accessibilityLabel: "계정 설정 열기") {
                    showAccountSheet = true
                }
            }
            .padding(.trailing, 12)
            .padding(.top, 16)
            .safeAreaPadding(.top, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .ignoresSafeArea()
    }

    private var naviPane: some View {
        Group {
            if useUltraLiteAssist {
                ultraLiteAssistPane
            } else {
                KakaoNavigationPaneView(
                    model: naviModel,
                    vehicleLocation: effectiveNaviLocation,
                    vehicleSpeedKph: effectiveNaviSpeedKph,
                    locationSourceLabel: effectiveLocationSourceLabel,
                    preferNativeMapRenderer: true,
                    wakeVehicle: {
                        viewModel.sendCommand("wake_up")
                        Task {
                            for attempt in 0..<6 {
                                let waitSeconds = attempt == 0 ? 5 : 4
                                try? await Task.sleep(nanoseconds: UInt64(waitSeconds) * 1_000_000_000)
                                await viewModel.refresh()
                                if viewModel.snapshot.vehicle.location.isValid {
                                    break
                                }
                            }
                        }
                    },
                    sendDestinationToVehicle: { place in
                        await viewModel.sendNavigationDestination(name: place.name, coordinate: place.coordinate)
                    },
                    teslaNavigation: viewModel.snapshot.navigation,
                    minimalMode: true,
                    hudVisible: $naviHUDVisible
                )
            }
        }
    }

    private var ultraLiteAssistPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(Int(max(0, effectiveNaviSpeedKph.rounded())))")
                    .font(.system(size: 52, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.black.opacity(0.9))
                Text("km/h")
                    .font(.system(size: 19, weight: .black, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.6))
                Spacer(minLength: 0)
                if viewModel.snapshot.navigation != nil {
                    Text(viewModel.navigationDestinationText)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.66))
                        .lineLimit(1)
                }
            }

            HStack(spacing: 8) {
                Text("위치: \(effectiveLocationSourceLabel)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.56))
                Spacer(minLength: 8)
                Text(effectiveLocationText)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.black.opacity(0.46))
                    .lineLimit(1)
            }

            if let cameraText = speedCameraAlertEngine.latestAlertText {
                Text(cameraText)
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(red: 0.92, green: 0.62, blue: 0.10))
            } else if let status = speedCameraStatusText {
                Text(status)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.55))
            }

            HStack(spacing: 8) {
                if viewModel.snapshot.navigation == nil {
                    Text("Tesla route: OFF")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.55))
                } else {
                    Text("Tesla route: ON")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundStyle(Color.green.opacity(0.8))
                    Text(viewModel.navigationSummaryText)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.55))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if kakaoConfig.restAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Kakao key 필요")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundStyle(Color.orange.opacity(0.9))
                }
            }

            HStack(spacing: 8) {
                controlButton(title: "Wake", symbol: "bolt.fill", command: "wake_up", variant: .compact)
                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(SecondaryCarButtonStyle(fontSize: 14, height: 44, cornerRadius: 12))
                .disabled(!networkMonitor.isConnected || viewModel.isCommandRunning)

                if deviceLocationTracker.authorizationStatus == .denied || deviceLocationTracker.authorizationStatus == .restricted {
                    Button {
                        openAppSettings()
                    } label: {
                        Label("Location", systemImage: "location.slash")
                    }
                    .buttonStyle(SecondaryCarButtonStyle(fontSize: 14, height: 44, cornerRadius: 12))
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(red: 0.98, green: 0.99, blue: 1.0))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.black.opacity(0.06), lineWidth: 1)
                )
        )
    }

    private func handleUltraLiteAssistTick() {
        updateAssistFromGPS()

        guard viewModel.snapshot.navigation != nil else { return }

        // Throttle network-dependent work (route sync / POI refresh) so we do not spawn a Task for every GPS tick.
        let now = Date()
        if now.timeIntervalSince(lastAssistNetworkTickAt) < 3.5 {
            return
        }
        lastAssistNetworkTickAt = now

        Task {
            await syncRouteFromTeslaIfNeeded(force: false)
            await naviModel.refreshSpeedCameraPOIsIfNeeded(restAPIKey: kakaoConfig.restAPIKey, force: false)
            updateSpeedCameraAlerts()
        }
    }

    private func updateAssistFromGPS() {
        // GPS-only: keep the last coordinate if GPS is temporarily unavailable.
        if let current = deviceLocationTracker.currentVehicleLocation {
            naviModel.updateVehicle(location: current, speedKph: effectiveNaviSpeedKph, courseDeg: deviceLocationTracker.currentCourseDeg)
        } else if let existing = naviModel.vehicleCoordinate {
            naviModel.updateVehicle(
                location: VehicleLocation(lat: existing.latitude, lon: existing.longitude),
                speedKph: effectiveNaviSpeedKph,
                courseDeg: deviceLocationTracker.currentCourseDeg
            )
        }
        updateSpeedCameraAlerts()
    }

    private func handleTeslaNavigationChanged() {
        // Reset when Tesla route ends.
        guard let destination = viewModel.snapshot.navigation?.destination, destination.isValid else {
            lastSyncedTeslaRouteSignature = ""
            routeDriftStrikeCount = 0
            naviModel.clearRoute()
            speedCameraAlertEngine.reset()
            return
        }

        Task {
            await syncRouteFromTeslaIfNeeded(force: true)
            updateSpeedCameraAlerts()
        }
    }

    private func updateSpeedCameraAlerts() {
        // Only speak alerts when we have an active route.
        guard viewModel.snapshot.navigation != nil else {
            if speedCameraAlertEngine.latestAlertText != nil {
                speedCameraAlertEngine.reset()
            }
            return
        }

        // GPS-only: do not emit camera alerts unless GPS is precise enough.
        guard deviceLocationTracker.alertVehicleLocation != nil else {
            if speedCameraAlertEngine.latestAlertText != nil {
                speedCameraAlertEngine.reset()
            }
            return
        }

        speedCameraAlertEngine.update(
            nextGuide: naviModel.nextSpeedCameraGuide,
            distanceMeters: naviModel.distanceToNextSpeedCameraMeters(),
            speedKph: effectiveNaviSpeedKph,
            speedLimitKph: naviModel.nextSpeedCameraLimitKph,
            isPro: SubscriptionManager.shared.effectiveIsPro
        )
    }

    private var teslaRouteSignature: String {
        guard let destination = viewModel.snapshot.navigation?.destination, destination.isValid else { return "" }
        let destinationName = viewModel.snapshot.navigation?.destinationName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return String(format: "%.5f,%.5f|%@", destination.lat, destination.lon, destinationName)
    }

    private func syncRouteFromTeslaIfNeeded(force: Bool) async {
        guard let nav = viewModel.snapshot.navigation,
              let destination = nav.destination,
              destination.isValid else {
            return
        }
        guard networkMonitor.isConnected else { return }

        let signature = teslaRouteSignature
        guard !signature.isEmpty else { return }

        // GPS-only: route sync requires a GPS fix.
        let origin = deviceLocationTracker.currentVehicleLocation?.coordinate ?? naviModel.vehicleCoordinate

        if !force, signature == lastSyncedTeslaRouteSignature, naviModel.route != nil {
            // Re-sync when we detect route drift (different actual road than Kakao route), which reduces false positives.
            // Avoid route API churn by requiring moderate drift to persist across multiple samples.
            if let origin, let drift = naviModel.routeMatchDistanceMeters(for: origin) {
                if drift <= 90 {
                    routeDriftStrikeCount = 0
                    return
                }
                if drift <= 130 {
                    routeDriftStrikeCount += 1
                    if routeDriftStrikeCount < 2 {
                        return
                    }
                }
            }
        }
        routeDriftStrikeCount = 0

        // Prevent route API churn when GPS updates rapidly.
        let now = Date()
        if !force, now.timeIntervalSince(lastTeslaRouteAttemptAt) < 8 {
            return
        }
        lastTeslaRouteAttemptAt = now

        let key = kakaoConfig.restAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        guard let origin else { return }

        await naviModel.startRoute(restAPIKey: key, origin: origin, destination: destination.coordinate)
        if naviModel.route != nil {
            lastSyncedTeslaRouteSignature = signature
        }
    }

    private var regularCenterPanel: some View {
        VStack(spacing: uiSectionSpacing) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Drive Assist")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.88))
                    Text("가볍고 안정적인 iPhone 주행 보조")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.58))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

                HStack(spacing: 8) {
                    statusPill(
                        text: networkMonitor.isConnected ? "ONLINE" : "OFFLINE",
                        tint: networkMonitor.isConnected ? Color.blue : Color.gray
                    )

                    statusPill(
                        text: viewModel.snapshot.vehicle.onlineState.uppercased(),
                        tint: viewModel.snapshot.vehicle.onlineState.lowercased() == "online" ? Color.green : Color.orange
                    )
                }
                .frame(maxWidth: .infinity, alignment: .trailing)

                headerIconButton(systemImage: "arrow.clockwise", accessibilityLabel: "차량 정보 새로고침") {
                    Task { await viewModel.refresh() }
                }
                .disabled(!networkMonitor.isConnected)

                headerIconButton(systemImage: "waveform.path.ecg", accessibilityLabel: "진단 화면 열기") {
                    showDiagnosticsSheet = true
                    refreshDiagnosticsSnapshot()
                }

                headerIconButton(systemImage: "person.crop.circle", accessibilityLabel: "계정 설정 열기") {
                    showAccountSheet = true
                }
            }

            if !networkMonitor.isConnected {
                HStack(spacing: 10) {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.orange)
                    Text("핫스팟 연결 대기 중입니다.")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.72))
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(red: 1.0, green: 0.96, blue: 0.90))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.orange.opacity(0.22), lineWidth: 1)
                        )
                )
            }

            naviPane
                .frame(maxWidth: .infinity, alignment: .top)

            HStack(spacing: 8) {
                Text("Source \(viewModel.snapshot.source)")
                    .foregroundStyle(Color.black.opacity(0.55))
                Text("Updated \(viewModel.snapshot.updatedAt)")
                    .foregroundStyle(Color.black.opacity(0.55))
                    .lineLimit(1)
                    .truncationMode(.head)
                Spacer(minLength: 0)
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .accessibilityElement(children: .combine)
        }
        .padding(uiCardPadding)
        .background(
            RoundedRectangle(cornerRadius: uiCardCornerRadius + 2, style: .continuous)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: uiCardCornerRadius + 2, style: .continuous)
                        .stroke(Color.black.opacity(0.06), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.08), radius: 14, x: 0, y: 8)
    }

    private func statusPill(text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .black, design: .rounded))
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.12))
            )
    }

    private func toggleChromeInNavi() {
        showChromeInNavi.toggle()
    }

    private func headerIconButton(systemImage: String, accessibilityLabel: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color(red: 0.18, green: 0.22, blue: 0.30))
                .frame(width: 42, height: 42)
                .background(
                    Circle()
                        .fill(Color(red: 0.92, green: 0.94, blue: 0.98))
                )
                .overlay(
                    Circle()
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(accessibilityLabel))
    }

    private struct CenterModeSegmentedControl: View {
        @Binding var selection: CarModeViewModel.CenterMode

        var body: some View {
            HStack(spacing: 0) {
                ForEach(CarModeViewModel.CenterMode.allCases, id: \.self) { mode in
                    Button {
                        selection = mode
                    } label: {
                        Text(mode.rawValue)
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white.opacity(selection == mode ? 1.0 : 0.75))
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background {
                        if selection == mode {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.white.opacity(0.16))
                                .padding(4)
                        }
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.14), lineWidth: 1)
                    )
            )
        }
    }

    private struct DraggableMediaOverlay: View {
        let url: URL
        let webView: WKWebView

        @State private var offset: CGSize = .zero
        @GestureState private var dragTranslation: CGSize = .zero

        // Resize is implemented by changing the overlay frame (NOT web page zoom).
        @State private var size: CGSize = CGSize(width: 360, height: 220)

        private let minSize = CGSize(width: 240, height: 160)
        private let maxSize = CGSize(width: 920, height: 720)

        private let presetS = CGSize(width: 320, height: 200)
        private let presetM = CGSize(width: 420, height: 260)
        private let presetL = CGSize(width: 560, height: 340)
        private let presetFull = CGSize(width: 860, height: 620)

        var body: some View {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text("Media")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))

                    Spacer()

                    Button("-") { scale(by: 0.90) }
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundStyle(.white.opacity(0.95))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.white.opacity(0.10)))

                    Button("+") { scale(by: 1.10) }
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundStyle(.white.opacity(0.95))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.white.opacity(0.10)))

                    Button("S") { applyPreset(presetS) }
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.white.opacity(0.10)))

                    Button("M") { applyPreset(presetM) }
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.white.opacity(0.10)))

                    Button("L") { applyPreset(presetL) }
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.white.opacity(0.10)))

                    Button("Full") { applyPreset(presetFull) }
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundStyle(.white.opacity(0.92))
                        .frame(height: 26)
                        .padding(.horizontal, 8)
                        .background(Capsule(style: .continuous).fill(Color.white.opacity(0.10)))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.55))

                InAppBrowserView(url: url, persistentWebView: webView)
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
            .overlay(alignment: .bottomTrailing) {
                resizeHandle
            }
            .shadow(color: Color.black.opacity(0.35), radius: 16, x: 0, y: 10)
            .offset(x: offset.width + dragTranslation.width, y: offset.height + dragTranslation.height)
            .gesture(
                DragGesture()
                    .updating($dragTranslation) { value, state, _ in
                        state = value.translation
                    }
                    .onEnded { value in
                        offset.width += value.translation.width
                        offset.height += value.translation.height
                    }
            )
        }

        private var resizeHandle: some View {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(.white.opacity(0.95))
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.black.opacity(0.55)))
                .padding(10)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            let next = CGSize(width: size.width + value.translation.width, height: size.height + value.translation.height)
                            size = clampSize(next)
                        }
                )
        }

        private func clampSize(_ raw: CGSize) -> CGSize {
            CGSize(
                width: min(maxSize.width, max(minSize.width, raw.width)),
                height: min(maxSize.height, max(minSize.height, raw.height))
            )
        }

        private func applyPreset(_ preset: CGSize) {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.88)) {
                size = clampSize(preset)
            }
        }

        private func scale(by factor: CGFloat) {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.88)) {
                size = clampSize(CGSize(width: size.width * factor, height: size.height * factor))
            }
        }
    }

    private var mediaPane: some View {
        GeometryReader { proxy in
            let containerSize = proxy.size

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )

                HStack(spacing: 8) {
                    Button("YouTube") {
                        viewModel.mediaURLText = "https://m.youtube.com"
                    }
                    .buttonStyle(SecondaryCarButtonStyle(fontSize: 16, height: 48, cornerRadius: 12))

                    Button("CHZZK") {
                        viewModel.mediaURLText = "https://chzzk.naver.com"
                    }
                    .buttonStyle(SecondaryCarButtonStyle(fontSize: 16, height: 48, cornerRadius: 12))

                    Spacer(minLength: 8)

                    Button("-") {
                        scaleMediaOverlay(by: 0.90, in: containerSize)
                    }
                    .buttonStyle(SecondaryCarButtonStyle(fontSize: 18, height: 42, cornerRadius: 12))
                    .frame(width: 42)

                    Button("+") {
                        scaleMediaOverlay(by: 1.10, in: containerSize)
                    }
                    .buttonStyle(SecondaryCarButtonStyle(fontSize: 18, height: 42, cornerRadius: 12))
                    .frame(width: 42)

                    ForEach(MediaOverlayPreset.allCases, id: \.self) { preset in
                        Button(preset.label) {
                            applyMediaPreset(preset, in: containerSize)
                        }
                        .buttonStyle(SecondaryCarButtonStyle(fontSize: 14, height: 42, cornerRadius: 10))
                        .frame(width: preset == .full ? 56 : 44)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .frame(height: mediaToolbarHeight)

                if let mediaURL = viewModel.mediaURL {
                    mediaWindow(url: mediaURL, containerSize: containerSize)
                } else {
                    Text("Invalid media URL")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .onAppear {
                initializeMediaOverlayIfNeeded(in: containerSize)
            }
            .onChange(of: containerSize) { _, next in
                initializeMediaOverlayIfNeeded(in: next)
                clampMediaOverlay(in: next)
            }
        }
    }

    private var sidePanel: some View {
        VStack(spacing: 12) {
            card {
                VStack(alignment: .leading, spacing: 8) {
                    Text(viewModel.snapshot.vehicle.displayName)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.90))

                    HStack(spacing: 6) {
                        statusPill(
                            text: viewModel.snapshot.vehicle.onlineState.uppercased(),
                            tint: viewModel.snapshot.vehicle.onlineState.lowercased() == "online" ? Color.green : Color.orange
                        )
                        if viewModel.snapshot.navigation != nil {
                            Text(viewModel.navigationSummaryText)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.black.opacity(0.56))
                                .lineLimit(1)
                        }
                    }

                    Divider().overlay(Color.black.opacity(0.08))

                    metricRow(title: "Speed", value: viewModel.speedText)
                    metricRow(title: "Battery", value: viewModel.batteryText)
                    metricRow(title: "Range", value: viewModel.rangeText)
                    metricRow(title: "Lock", value: viewModel.lockText)
                    metricRow(title: "Climate", value: viewModel.climateText)
                }
            }

            if viewModel.isLoading {
                card {
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(.blue)
                        Text("차량 데이터를 동기화하는 중입니다...")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.black.opacity(0.78))
                    }
                }
            } else if viewModel.snapshot.navigation == nil {
                card {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("경로 대기 중", systemImage: "location.slash")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.black.opacity(0.78))
                        Text("테슬라에서 목적지를 설정하면 카메라 경고가 자동으로 시작됩니다.")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.black.opacity(0.60))
                    }
                }
            }

            card {
                VStack(alignment: .leading, spacing: 10) {
                    Text("차량 제어")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.86))

                    controlsGrid

                    if !networkMonitor.isConnected {
                        Text("네트워크 연결 후 제어 버튼이 활성화됩니다.")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.black.opacity(0.55))
                    } else if viewModel.isCommandRunning {
                        Text("명령 전송 중에는 버튼이 잠시 비활성화됩니다.")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.black.opacity(0.55))
                    }
                }
            }

            if viewModel.isCommandRunning {
                card {
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(.blue)
                        Text("차량에 명령을 전송하는 중입니다...")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.black.opacity(0.78))
                    }
                }
            }

            if let commandMessage = viewModel.commandMessage {
                card {
                    Text(commandMessage)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.78))
                }
            }

            if let message = viewModel.errorMessage {
                card {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("연결 오류", systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(.red.opacity(0.88))

                        Text(message)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.red.opacity(0.88))
                            .lineLimit(4)
                            .truncationMode(.tail)

                        Button {
                            Task { await viewModel.refresh() }
                        } label: {
                            Label("다시 시도", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(SecondaryCarButtonStyle(fontSize: 15, height: 44, cornerRadius: 12))
                        .disabled(!networkMonitor.isConnected || viewModel.isCommandRunning)
                    }
                }
            }

            Button {
                router.showGuide()
            } label: {
                Label("Exit Car Mode", systemImage: "arrowshape.turn.up.backward.fill")
            }
            .buttonStyle(SecondaryCarButtonStyle(fontSize: 17, height: 52, cornerRadius: 14))
            .accessibilityLabel(Text("차량 모드 종료"))
        }
    }

    @ViewBuilder
    private func mediaWindow(url: URL, containerSize: CGSize) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))

                Text("Media Overlay")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))

                Spacer(minLength: 0)

                Text("\(Int(mediaOverlaySize.width.rounded())) x \(Int(mediaOverlaySize.height.rounded()))")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(Color.black.opacity(0.30))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        let proposal = CGPoint(
                            x: mediaOverlayDragAnchor.x + value.translation.width,
                            y: mediaOverlayDragAnchor.y + value.translation.height
                        )
                        mediaOverlayOrigin = clampedMediaOrigin(proposal, size: mediaOverlaySize, container: containerSize)
                    }
                    .onEnded { _ in
                        mediaOverlayDragAnchor = mediaOverlayOrigin
                    }
            )

            InAppBrowserView(url: url, persistentWebView: mediaWebViewStore.webView)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: mediaOverlaySize.width, height: mediaOverlaySize.height)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.40))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
        .overlay(alignment: .bottomTrailing) {
            Circle()
                .fill(Color.white.opacity(0.90))
                .frame(width: 26, height: 26)
                .overlay(
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(.black.opacity(0.85))
                )
                .padding(8)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { value in
                            let next = CGSize(
                                width: mediaOverlayResizeAnchor.width + value.translation.width,
                                height: mediaOverlayResizeAnchor.height + value.translation.height
                            )
                            mediaOverlaySize = clampedMediaSize(next, container: containerSize)
                            mediaOverlayOrigin = clampedMediaOrigin(mediaOverlayOrigin, size: mediaOverlaySize, container: containerSize)
                        }
                        .onEnded { _ in
                            mediaOverlayResizeAnchor = mediaOverlaySize
                            mediaOverlayDragAnchor = mediaOverlayOrigin
                        }
                )
        }
        .position(
            x: mediaOverlayOrigin.x + (mediaOverlaySize.width / 2.0),
            y: mediaOverlayOrigin.y + (mediaOverlaySize.height / 2.0)
        )
    }

    private func initializeMediaOverlayIfNeeded(in container: CGSize) {
        guard container.width > 0, container.height > 0 else { return }
        guard !hasInitializedMediaOverlay else { return }

        let initial = clampedMediaSize(
            CGSize(width: container.width * 0.62, height: container.height * 0.58),
            container: container
        )
        let origin = CGPoint(
            x: max(10, (container.width - initial.width) / 2.0),
            y: mediaToolbarHeight + 10
        )

        mediaOverlaySize = initial
        mediaOverlayOrigin = clampedMediaOrigin(origin, size: initial, container: container)
        mediaOverlayDragAnchor = mediaOverlayOrigin
        mediaOverlayResizeAnchor = mediaOverlaySize
        hasInitializedMediaOverlay = true
    }

    private func clampMediaOverlay(in container: CGSize) {
        guard hasInitializedMediaOverlay else { return }
        mediaOverlaySize = clampedMediaSize(mediaOverlaySize, container: container)
        mediaOverlayOrigin = clampedMediaOrigin(mediaOverlayOrigin, size: mediaOverlaySize, container: container)
        mediaOverlayDragAnchor = mediaOverlayOrigin
        mediaOverlayResizeAnchor = mediaOverlaySize
    }

    private func scaleMediaOverlay(by factor: CGFloat, in container: CGSize) {
        guard hasInitializedMediaOverlay else {
            initializeMediaOverlayIfNeeded(in: container)
            return
        }
        let proposal = CGSize(
            width: mediaOverlaySize.width * factor,
            height: mediaOverlaySize.height * factor
        )
        mediaOverlaySize = clampedMediaSize(proposal, container: container)
        mediaOverlayOrigin = clampedMediaOrigin(mediaOverlayOrigin, size: mediaOverlaySize, container: container)
        mediaOverlayResizeAnchor = mediaOverlaySize
        mediaOverlayDragAnchor = mediaOverlayOrigin
    }

    private func applyMediaPreset(_ preset: MediaOverlayPreset, in container: CGSize) {
        guard container.width > 0, container.height > 0 else { return }
        let target: CGSize
        switch preset {
        case .small:
            target = CGSize(width: container.width * 0.44, height: container.height * 0.34)
        case .medium:
            target = CGSize(width: container.width * 0.58, height: container.height * 0.48)
        case .large:
            target = CGSize(width: container.width * 0.74, height: container.height * 0.65)
        case .full:
            target = CGSize(width: container.width * 0.95, height: container.height - mediaToolbarHeight - 16)
        }

        mediaOverlaySize = clampedMediaSize(target, container: container)
        let centered = CGPoint(
            x: (container.width - mediaOverlaySize.width) / 2.0,
            y: mediaToolbarHeight + 8
        )
        mediaOverlayOrigin = clampedMediaOrigin(centered, size: mediaOverlaySize, container: container)
        mediaOverlayResizeAnchor = mediaOverlaySize
        mediaOverlayDragAnchor = mediaOverlayOrigin
        hasInitializedMediaOverlay = true
    }

    private func clampedMediaSize(_ proposal: CGSize, container: CGSize) -> CGSize {
        let maxWidth = max(mediaMinSize.width, container.width - 20)
        let maxHeight = max(mediaMinSize.height, container.height - mediaToolbarHeight - 12)
        return CGSize(
            width: min(max(proposal.width, mediaMinSize.width), maxWidth),
            height: min(max(proposal.height, mediaMinSize.height), maxHeight)
        )
    }

    private func clampedMediaOrigin(_ proposal: CGPoint, size: CGSize, container: CGSize) -> CGPoint {
        let minX: CGFloat = 10
        let minY: CGFloat = mediaToolbarHeight + 6
        let maxX = max(minX, container.width - size.width - 10)
        let maxY = max(minY, container.height - size.height - 10)
        return CGPoint(
            x: min(max(proposal.x, minX), maxX),
            y: min(max(proposal.y, minY), maxY)
        )
    }

    private enum MediaOverlayPreset: CaseIterable {
        case small
        case medium
        case large
        case full

        var label: String {
            switch self {
            case .small:
                return "S"
            case .medium:
                return "M"
            case .large:
                return "L"
            case .full:
                return "Full"
            }
        }
    }

    private var controlsGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ]

        return LazyVGrid(columns: columns, spacing: 10) {
            controlButton(title: "Lock", symbol: "lock.fill", command: "door_lock", variant: .compact)
            controlButton(title: "Unlock", symbol: "lock.open.fill", command: "door_unlock", variant: .compact)
            controlButton(title: "A/C ON", symbol: "wind", command: "auto_conditioning_start", variant: .compact)
            controlButton(title: "A/C OFF", symbol: "snowflake", command: "auto_conditioning_stop", variant: .compact)
            controlButton(title: "Wake", symbol: "bolt.fill", command: "wake_up", variant: .compact)
            Button {
                showAccountSheet = true
            } label: {
                Label("Account", systemImage: "person.crop.circle")
            }
            .buttonStyle(SecondaryCarButtonStyle(fontSize: 17, height: 54, cornerRadius: 14))
            .accessibilityLabel(Text("계정 설정 열기"))
        }
    }

    private enum ControlButtonVariant {
        case regular
        case compact
    }

    private func controlButton(title: String, symbol: String, command: String, variant: ControlButtonVariant = .regular) -> some View {
        Button {
            viewModel.sendCommand(command)
        } label: {
            Label(title, systemImage: symbol)
        }
        .buttonStyle(primaryStyle(for: variant))
        .disabled(viewModel.isCommandRunning || !networkMonitor.isConnected)
        .accessibilityLabel(Text(title))
        .accessibilityHint(Text("차량 명령을 전송합니다"))
    }

    private func primaryStyle(for variant: ControlButtonVariant) -> PrimaryCarButtonStyle {
        switch variant {
        case .regular:
            return PrimaryCarButtonStyle(fontSize: 22, height: 80, cornerRadius: 20)
        case .compact:
            return PrimaryCarButtonStyle(fontSize: 17, height: 54, cornerRadius: 14)
        }
    }


    private var diagnosticsSheet: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    card {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Quick Status")
                                .font(.system(size: 18, weight: .heavy, design: .rounded))
                                .foregroundStyle(Color.black.opacity(0.88))

                            if let diagnosticsStatusText {
                                Text(diagnosticsStatusText)
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color.blue)
                            }

                            Group {
                                metricRow(title: "App", value: appVersionText)
                                metricRow(title: "Network", value: networkMonitor.isConnected ? "Connected" : "Disconnected")
                                metricRow(title: "Telemetry", value: AppConfig.telemetrySource.rawValue)
                                metricRow(title: "Backend", value: AppConfig.backendBaseURLString)
                                metricRow(title: "Speed Cameras", value: "cached \(diagnosticsCameraCount)")
                                metricRow(title: "Tesla route", value: viewModel.snapshot.navigation == nil ? "OFF" : "ON")
                                metricRow(title: "Kakao route", value: naviModel.route == nil ? "Not synced" : "Synced")
                                metricRow(title: "Location", value: effectiveLocationText)
                            }
                        }
                    }

                    card {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Actions")
                                .font(.system(size: 18, weight: .heavy, design: .rounded))
                                .foregroundStyle(Color.black.opacity(0.88))

                            HStack(spacing: 10) {
                                Button("Copy Report") {
                                    copyDiagnosticsToClipboard()
                                }
                                .buttonStyle(SecondaryCarButtonStyle(fontSize: 15, height: 54, cornerRadius: 14))

                                Button("Refresh") {
                                    refreshDiagnosticsSnapshot()
                                }
                                .buttonStyle(SecondaryCarButtonStyle(fontSize: 15, height: 54, cornerRadius: 14))
                            }

                            HStack(spacing: 10) {
                                Button("Restart Polling") {
                                    restartPolling()
                                }
                                .buttonStyle(SecondaryCarButtonStyle(fontSize: 15, height: 54, cornerRadius: 14))

                                Button("Restart GPS") {
                                    restartGPS()
                                }
                                .buttonStyle(SecondaryCarButtonStyle(fontSize: 15, height: 54, cornerRadius: 14))
                            }

                            HStack(spacing: 10) {
                                Button("Refresh Cameras") {
                                    refreshSpeedCameraDataset()
                                }
                                .buttonStyle(SecondaryCarButtonStyle(fontSize: 15, height: 54, cornerRadius: 14))

                                Button("Clear Logs") {
                                    clearDiagnosticsLogs()
                                }
                                .buttonStyle(SecondaryCarButtonStyle(fontSize: 15, height: 54, cornerRadius: 14))
                            }
                        }
                    }

                    card {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Logs")
                                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                                    .foregroundStyle(Color.black.opacity(0.88))
                                Spacer()
                                Button("Refresh") {
                                    refreshDiagnosticsSnapshot()
                                }
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                            }

                            Text(diagnosticsLogDump.isEmpty ? "(No logs yet)" : diagnosticsLogDump)
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color.black.opacity(0.72))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(16)
            }
            .navigationTitle("Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        showDiagnosticsSheet = false
                    }
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                }
            }
            .onAppear {
                refreshDiagnosticsSnapshot()
            }
        }
    }

    private var appVersionText: String {
        let version = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "?"
        let build = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "?"
        return "\(version) (\(build))"
    }

    private func refreshDiagnosticsSnapshot() {
        Task { @MainActor in
            diagnosticsCameraCount = await PublicSpeedCameraStore.shared.cameraCount()
            diagnosticsLogDump = await AppLogStore.shared.dumpText(limit: 500)
        }
    }

    private func copyDiagnosticsToClipboard() {
        Task { @MainActor in
            let report = await buildDiagnosticsReport(logLimit: 220)
            UIPasteboard.general.string = report
            diagnosticsStatusText = "Copied diagnostics to clipboard."
            await AppLogStore.shared.persist()
        }
    }

    private func clearDiagnosticsLogs() {
        Task { @MainActor in
            await AppLogStore.shared.clear()
            diagnosticsLogDump = ""
            diagnosticsStatusText = "Logs cleared."
        }
    }

    private func restartPolling() {
        appLog(.app, "diagnostics: restart polling", level: .info)
        viewModel.stop()
        viewModel.start()
        Task { await viewModel.refresh() }
        diagnosticsStatusText = "Polling restarted."
    }

    private func restartGPS() {
        appLog(.gps, "diagnostics: restart gps", level: .info)
        deviceLocationTracker.stop()
        deviceLocationTracker.start()
        diagnosticsStatusText = "GPS restarted."
    }

    private func refreshSpeedCameraDataset() {
        Task { @MainActor in
            diagnosticsStatusText = "Refreshing speed camera dataset..."
            do {
                _ = try await PublicSpeedCameraStore.shared.refreshFromBackendIfNeeded(force: true)
                diagnosticsCameraCount = await PublicSpeedCameraStore.shared.cameraCount()
                diagnosticsStatusText = "Speed camera dataset refreshed (\(diagnosticsCameraCount))."
                appLog(.cameras, "dataset refreshed: cached=\(diagnosticsCameraCount)", level: .info)
            } catch {
                let msg = "Speed camera dataset refresh failed: \(error.localizedDescription)"
                diagnosticsStatusText = msg
                appLog(.cameras, msg, level: .error)
            }
            diagnosticsLogDump = await AppLogStore.shared.dumpText(limit: 500)
        }
    }

    private func buildDiagnosticsReport(logLimit: Int) async -> String {
        let version = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "?"
        let build = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "?"

        let now = ISO8601DateFormatter().string(from: Date())

        let kakaoRestKeySet = !kakaoConfig.restAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let kakaoJSKeySet = !kakaoConfig.javaScriptKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        let backendTokenSet = !(AppConfig.backendAPIToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

        let gpsStatus: String = {
            guard CLLocationManager.locationServicesEnabled() else { return "Location Services OFF" }
            switch deviceLocationTracker.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                break
            case .notDetermined:
                return "Permission not determined"
            case .denied, .restricted:
                return "Permission denied"
            @unknown default:
                return "Permission unknown"
            }

            guard let loc = deviceLocationTracker.latestLocation else { return "GPS: none" }
            let age = Int(Date().timeIntervalSince(deviceLocationTracker.lastUpdatedAt))
            return String(format: "GPS: %.5f, %.5f (±%dm, age %ds)", loc.coordinate.latitude, loc.coordinate.longitude, Int(loc.horizontalAccuracy), age)
        }()

        let camerasCached = await PublicSpeedCameraStore.shared.cameraCount()
        let logs = await AppLogStore.shared.dumpText(limit: logLimit)

        return """
Subdash Diagnostics
- at: \(now)
- app: \(version) (\(build))
- network: \(networkMonitor.isConnected ? "connected" : "disconnected") \(networkMonitor.connectionTypeText)
- telemetry: \(AppConfig.telemetrySource.rawValue)
- backend: \(AppConfig.backendBaseURLString)
- backend_token_set: \(backendTokenSet ? "yes" : "no")
- tesla_signed_in: \(teslaAuth.isSignedIn ? "yes" : "no")
- tesla_route: \(viewModel.snapshot.navigation == nil ? "off" : "on")
- kakao_rest_key_set: \(kakaoRestKeySet ? "yes" : "no")
- kakao_js_key_set: \(kakaoJSKeySet ? "yes" : "no")
- speed_cameras_cached: \(camerasCached)
- gps: \(gpsStatus)

Recent logs:
\(logs)
"""
    }

    private func metricRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(Color.black.opacity(0.55))
            Spacer()
            Text(value)
                .foregroundStyle(Color.black.opacity(0.88))
                .fontWeight(.bold)
        }
        .font(.system(size: 16, weight: .semibold, design: .rounded))
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(uiCardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: uiCardCornerRadius, style: .continuous)
                    .fill(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: uiCardCornerRadius, style: .continuous)
                            .stroke(Color.black.opacity(0.06), lineWidth: 1)
                    )
            )
            .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 6)
    }
}
