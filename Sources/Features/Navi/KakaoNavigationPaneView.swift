import AVFoundation
import CoreLocation
import SwiftUI
import UIKit

struct KakaoNavigationPaneView: View {
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    @EnvironmentObject private var kakaoConfig: KakaoConfigStore
    @ObservedObject var model: KakaoNavigationViewModel

    let vehicleLocation: VehicleLocation
    let vehicleSpeedKph: Double
    let locationSourceLabel: String?
    let preferNativeMapRenderer: Bool
    let wakeVehicle: (() -> Void)?
    let sendDestinationToVehicle: ((KakaoPlace) async -> (ok: Bool, message: String))?
    let teslaNavigation: NavigationState?
    let minimalMode: Bool

    /// Controls whether overlays (HUD/search/results/route info) are visible.
    @Binding var hudVisible: Bool

    @FocusState private var searchFocused: Bool
    @State private var topPanelOffset: CGSize = .zero
    @State private var topPanelAnchorOffset: CGSize = .zero
    @State private var turnBannerOffset: CGSize = .zero
    @State private var turnBannerAnchorOffset: CGSize = .zero
    @State private var followPulseTask: Task<Void, Never>?
    @State private var didRestorePersistedOffsets = false
    @State private var suppressMapTapUntil: Date = .distantPast

    @State private var autoHideTask: Task<Void, Never>?
    @State private var speedCameraRefreshTask: Task<Void, Never>?
    @State private var teslaRouteSyncTask: Task<Void, Never>?
    @State private var destinationPushStatus: (ok: Bool, message: String)?
    @State private var lastSyncedTeslaRouteSignature: String = ""
    @State private var lastTeslaRouteAttemptAt: Date = .distantPast
    @StateObject private var speedCameraAlertEngine = SpeedCameraAlertEngine()

    private let autoHideSeconds: Double = 14
    private let topPanelXKey = "kakao.navi.topPanel.offset.x"
    private let topPanelYKey = "kakao.navi.topPanel.offset.y"
    private let bannerXKey = "kakao.navi.banner.offset.x"
    private let bannerYKey = "kakao.navi.banner.offset.y"
    private let autoTeslaRouteSyncEnabled = false
    private let speedCameraPOIEnabledInMinimalMode = false

    var body: some View {
        Group {
            if minimalMode {
                minimalAssistBody
            } else {
                GeometryReader { proxy in
                    let panelWidth = min(proxy.size.width * 0.64, 560)
                    let topInset = max(24.0, proxy.safeAreaInsets.top + 16)
                    let bottomInset = max(16.0, proxy.safeAreaInsets.bottom + 12)
                    let resultsTopPadding = topInset + topPanelEstimatedHeight + topPanelOffset.height + 10
                    let turnBannerWidth = max(260.0, min(proxy.size.width - 132, 760))

                    ZStack(alignment: .topLeading) {
                        mapCanvas(resultsTopPadding: resultsTopPadding, topInset: topInset)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                searchFocused = false
                                if Date() < suppressMapTapUntil { return }
                                revealHUDAndScheduleAutoHide()
                            }

                        // Minimal turn-by-turn banner (keeps navigation feeling alive even when HUD is hidden)
                        if model.route != nil {
                            turnByTurnBanner(next: model.nextGuide)
                                .frame(maxWidth: turnBannerWidth, alignment: .leading)
                                .padding(.top, topInset + 20 + turnBannerOffset.height)
                                .padding(.leading, 64 + turnBannerOffset.width)
                                .padding(.trailing, 24)
                                .gesture(
                                    DragGesture(minimumDistance: 2, coordinateSpace: .local)
                                        .onChanged { value in
                                            searchFocused = false
                                            turnBannerOffset = clampedTurnBannerOffset(
                                                proposalX: turnBannerAnchorOffset.width + value.translation.width,
                                                proposalY: turnBannerAnchorOffset.height + value.translation.height,
                                                containerSize: proxy.size,
                                                baseTopInset: topInset,
                                                bannerWidth: turnBannerWidth
                                            )
                                        }
                                        .onEnded { _ in
                                            turnBannerAnchorOffset = turnBannerOffset
                                            persistPanelOffsets()
                                        }
                                )
                                .transition(.opacity)
                        }

                        if hudVisible {
                            VStack(alignment: .leading, spacing: 8) {
                                header

                                if kakaoConfig.restAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    missingKeyCard
                                } else {
                                    searchBar
                                    favoriteDestinationsRow
                                }

                                routeInfo

                                if model.route == nil, model.results.isEmpty {
                                    compactHowToCard
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: panelWidth, alignment: .topLeading)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color.clear)
                                    .contentShape(Rectangle())
                            )
                            .offset(
                                x: topPanelOffset.width,
                                y: topInset + topPanelOffset.height
                            )
                            .gesture(
                                    DragGesture(minimumDistance: 2, coordinateSpace: .local)
                                        .onChanged { value in
                                            searchFocused = false
                                            topPanelOffset = clampedTopPanelOffset(
                                                proposalX: topPanelAnchorOffset.width + value.translation.width,
                                                proposalY: topPanelAnchorOffset.height + value.translation.height,
                                            containerSize: proxy.size,
                                            panelWidth: panelWidth,
                                            topInset: topInset
                                        )
                                    }
                                    .onEnded { _ in
                                        topPanelAnchorOffset = topPanelOffset
                                        persistPanelOffsets()
                                    }
                            )
                            .transition(.opacity)
                        }

                        // Always-visible handle so users can bring HUD back.
                        Button {
                            if hudVisible {
                                searchFocused = false
                                autoHideTask?.cancel()
                                autoHideTask = nil
                                suppressMapTapUntil = Date().addingTimeInterval(0.25)
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    hudVisible = false
                                }
                            } else {
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    hudVisible = true
                                }
                                revealHUDAndScheduleAutoHide()
                            }
                        } label: {
                            Image(systemName: hudVisible ? "eye" : "eye.slash")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white.opacity(0.92))
                                .frame(width: 40, height: 40)
                                .background(Circle().fill(Color.black.opacity(0.45)))
                                .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .padding(.bottom, bottomInset)
                        .padding(.leading, 12)
                        .opacity(hudVisible ? 0.55 : 1.0)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    }
                    .animation(.easeInOut(duration: 0.18), value: hudVisible)
                    .onAppear {
                        restoreOffsetsIfNeeded(
                            containerSize: proxy.size,
                            panelWidth: panelWidth,
                            topInset: topInset,
                            bannerWidth: turnBannerWidth
                        )
                    }
                    .onChange(of: proxy.size) { _, size in
                        clampPersistedOffsets(
                            containerSize: size,
                            panelWidth: panelWidth,
                            topInset: topInset,
                            bannerWidth: turnBannerWidth
                        )
                    }
                }
            }
        }
        .onAppear {
            model.updateVehicle(location: vehicleLocation, speedKph: vehicleSpeedKph)
            searchFocused = false
            DispatchQueue.main.async {
                searchFocused = false
                dismissKeyboard()
            }
            if minimalMode {
                hudVisible = true
                autoHideTask?.cancel()
                autoHideTask = nil
            } else {
                startFollowPulseLoop()
                revealHUDAndScheduleAutoHide()
            }
            speedCameraAlertEngine.reset()
            if model.route != nil {
                scheduleSpeedCameraPOIRefresh(force: true, delaySeconds: 0.15)
            }
            if autoTeslaRouteSyncEnabled {
                scheduleTeslaRouteSync(force: true, delaySeconds: 0.2)
            }
            updateSpeedCameraAlerts()
        }
        .onDisappear {
            autoHideTask?.cancel()
            autoHideTask = nil
            followPulseTask?.cancel()
            followPulseTask = nil
            speedCameraRefreshTask?.cancel()
            speedCameraRefreshTask = nil
            teslaRouteSyncTask?.cancel()
            teslaRouteSyncTask = nil
            speedCameraAlertEngine.reset()
        }
        .onChange(of: vehicleLocation) { _, _ in
            model.updateVehicle(location: vehicleLocation, speedKph: vehicleSpeedKph)
            if model.route != nil {
                scheduleSpeedCameraPOIRefresh(force: false, delaySeconds: 0.8)
            }
            if autoTeslaRouteSyncEnabled {
                scheduleTeslaRouteSync(force: false, delaySeconds: 0.25)
            }
            updateSpeedCameraAlerts()
        }
        .onChange(of: vehicleSpeedKph) { _, _ in
            model.updateVehicle(location: vehicleLocation, speedKph: vehicleSpeedKph)
            updateSpeedCameraAlerts()
        }
        .onChange(of: model.routeRevision) { _, _ in
            if model.route != nil {
                scheduleSpeedCameraPOIRefresh(force: true, delaySeconds: 0.1)
            }
            updateSpeedCameraAlerts()
        }
        .onChange(of: kakaoConfig.restAPIKey) { _, _ in
            if model.route != nil {
                scheduleSpeedCameraPOIRefresh(force: true, delaySeconds: 0.1)
            }
            updateSpeedCameraAlerts()
        }
        .onChange(of: model.speedCameraRevision) { _, _ in
            updateSpeedCameraAlerts()
        }
        .onChange(of: teslaRouteSignature) { _, _ in
            if autoTeslaRouteSyncEnabled {
                scheduleTeslaRouteSync(force: true, delaySeconds: 0.12)
            }
        }
        .onChange(of: hudVisible) { _, visible in
            if !visible {
                searchFocused = false
            }
        }
    }

    private var minimalAssistBody: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Assist Navigation")
                            .font(.system(size: 21, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.black.opacity(0.88))
                        Text("지도 렌더링 없이 경량 주행 보조")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.black.opacity(0.56))
                    }

                    Spacer(minLength: 0)

                    Button {
                        Task {
                            await runSearch()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color.black.opacity(0.75))
                            .frame(width: 38, height: 38)
                            .background(
                                Circle()
                                    .fill(Color(red: 0.94, green: 0.95, blue: 0.98))
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isSearching)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(tossCardBackground())

                if kakaoConfig.restAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Kakao REST API key is missing")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.black.opacity(0.82))
                        Text("Account > Navigation (Kakao)에서 REST 키를 입력해 주세요.")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.black.opacity(0.62))
                    }
                    .padding(12)
                    .background(tossCardBackground())
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            TextField("목적지 검색", text: $model.query)
                                .focused($searchFocused)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .submitLabel(.search)
                                .onSubmit {
                                    Task { await runSearch() }
                                }
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color(red: 0.95, green: 0.96, blue: 0.99))
                                )
                                .foregroundStyle(Color.black.opacity(0.82))

                            Button(model.isSearching ? "..." : "Search") {
                                Task { await runSearch() }
                            }
                            .buttonStyle(SecondaryCarButtonStyle(fontSize: 14, height: 44, cornerRadius: 12))
                            .frame(width: 92)
                            .disabled(model.isSearching)
                        }

                        HStack(spacing: 8) {
                            minimalFavoriteButton(slot: .home)
                            minimalFavoriteButton(slot: .work)

                            if model.route != nil {
                                Button("경로 종료") {
                                    model.clearRoute()
                                }
                                .buttonStyle(SecondaryCarButtonStyle(fontSize: 13, height: 36, cornerRadius: 10))
                                .frame(width: 86)
                            }
                        }
                    }
                    .padding(12)
                    .background(tossCardBackground())
                }

                minimalDrivingCard

                if let status = destinationPushStatus {
                    Text(status.message)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(status.ok ? Color.green : Color.orange)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(tossCardBackground())
                }

                if let message = model.errorMessage {
                    Text(message)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.red.opacity(0.88))
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(tossCardBackground())
                }

                if !model.results.isEmpty {
                    minimalResultsList
                }
            }
            .padding(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(red: 0.97, green: 0.98, blue: 1.0))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.black.opacity(0.06), lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var minimalDrivingCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(Int(max(0, vehicleSpeedKph.rounded())))")
                    .font(.system(size: 46, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.black.opacity(0.90))
                Text("km/h")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.62))

                Spacer(minLength: 8)

                if let route = model.route {
                    Text(distanceDurationText(route: route))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.72))
                } else {
                    Text("경로 없음")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.55))
                }
            }

            HStack(spacing: 8) {
                Text(model.nextGuide?.guidance ?? "안내 대기 중")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.84))
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                Spacer(minLength: 8)
                if let meters = model.distanceToNextGuideMeters() {
                    Text("\(meters)m")
                        .font(.system(size: 36, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.blue.opacity(0.92))
                }
            }

            HStack(spacing: 8) {
                if let cameraMeters = model.distanceToNextSpeedCameraMeters() {
                    Label("과속 카메라 \(cameraMeters)m", systemImage: "camera.viewfinder")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.orange.opacity(0.92))
                }

                if let source = locationSourceLabel, !source.isEmpty {
                    Text("위치 소스: \(source)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.52))
                }
            }
        }
        .padding(12)
        .background(tossCardBackground())
    }

    private var minimalResultsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("검색 결과")
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.75))

            ForEach(model.results.prefix(5)) { place in
                VStack(alignment: .leading, spacing: 7) {
                    Text(place.name)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.85))
                    Text(place.address)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.55))
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Button("경로") {
                            Task { await startRoute(to: place) }
                        }
                        .buttonStyle(SecondaryCarButtonStyle(fontSize: 13, height: 34, cornerRadius: 10))

                        Button("Tesla") {
                            Task { await pushDestinationToTesla(place) }
                        }
                        .buttonStyle(SecondaryCarButtonStyle(fontSize: 13, height: 34, cornerRadius: 10))
                        .disabled(sendDestinationToVehicle == nil)

                        Button("집 저장") {
                            model.saveFavorite(.home, place: place)
                        }
                        .buttonStyle(SecondaryCarButtonStyle(fontSize: 11, height: 34, cornerRadius: 10))

                        Button("직장 저장") {
                            model.saveFavorite(.work, place: place)
                        }
                        .buttonStyle(SecondaryCarButtonStyle(fontSize: 11, height: 34, cornerRadius: 10))
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(red: 0.95, green: 0.96, blue: 0.99))
                )
            }
        }
        .padding(12)
        .background(tossCardBackground())
    }

    private func minimalFavoriteButton(slot: KakaoNavigationViewModel.FavoriteSlot) -> some View {
        let destination = model.favorite(for: slot)
        return Button {
            Task { await routeToFavorite(slot) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: slot == .home ? "house.fill" : "briefcase.fill")
                    .font(.system(size: 11, weight: .bold))
                VStack(alignment: .leading, spacing: 0) {
                    Text(slot.title)
                        .font(.system(size: 11, weight: .black, design: .rounded))
                    Text(destination?.name ?? "미설정")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(Color.black.opacity(destination == nil ? 0.46 : 0.75))
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(red: 0.94, green: 0.95, blue: 0.98))
            )
        }
        .buttonStyle(.plain)
        .disabled(destination == nil || model.isRouting)
    }

    private func tossCardBackground() -> some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
    }

    @ViewBuilder
    private func mapCanvas(resultsTopPadding: CGFloat, topInset: CGFloat) -> some View {
        let jsKey = kakaoConfig.javaScriptKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let useNative = preferNativeMapRenderer

        if minimalMode {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.black.opacity(0.28), Color.blue.opacity(0.20)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(alignment: .topLeading) {
                    if !model.results.isEmpty, model.route == nil {
                        resultsOverlay
                            .padding(12)
                            .padding(.top, max(topInset, resultsTopPadding))
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    Text("Assist mode: map disabled for stability")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.82))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.black.opacity(0.45))
                        )
                        .padding(10)
                }
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        } else {
            Group {
                if !useNative, !jsKey.isEmpty {
                    KakaoWebRouteMapView(
                        javaScriptKey: jsKey,
                        vehicleCoordinate: model.vehicleCoordinate,
                        vehicleSpeedKph: vehicleSpeedKph,
                        route: model.route,
                        followEnabled: model.isFollowModeEnabled,
                        routeRevision: model.routeRevision,
                        zoomOffset: model.zoomOffset,
                        zoomRevision: model.zoomRevision,
                        followPulse: model.followPulse
                    )
                } else {
                    KakaoRouteMapView(
                        vehicleCoordinate: model.vehicleCoordinate,
                        route: model.route,
                        followEnabled: model.isFollowModeEnabled,
                        routeRevision: model.routeRevision,
                        zoomOffset: model.zoomOffset,
                        zoomRevision: model.zoomRevision,
                        followPulse: model.followPulse
                    )
                }
            }
            .overlay(alignment: .topLeading) {
                if !model.results.isEmpty, model.route == nil {
                    resultsOverlay
                        .padding(12)
                        .padding(.top, max(topInset, resultsTopPadding))
                }
            }
            .overlay(alignment: .topTrailing) {
                VStack(alignment: .trailing, spacing: 8) {
                    followPill
                    zoomControls
                }
                .padding(.top, topInset + 8)
                .padding(.trailing, 12)
            }
            .overlay(alignment: .bottomTrailing) {
                HStack(spacing: 6) {
                    Image(systemName: "hand.draw.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text("Drag cards")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.white.opacity(0.82))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.black.opacity(0.48))
                )
                .padding(10)
            }
            .overlay(alignment: .bottomLeading) {
                Text(useNative ? "Map: Apple (stability mode)" : (jsKey.isEmpty ? "Map: Apple fallback (set Kakao JS key in Account)" : "Map: Kakao"))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.black.opacity(0.45))
                    )
                    .padding(10)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private var topPanelEstimatedHeight: CGFloat {
        var height: CGFloat = 220
        if kakaoConfig.restAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            height += 22
        } else {
            height += 28
        }
        if model.route == nil, model.results.isEmpty {
            height += 48
        }
        return height
    }

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Navigation")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text("Kakao API")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
            }

            Spacer()

            if model.isRouting || model.isSearching {
                ProgressView()
                    .tint(.white)
            }

            if !minimalMode {
                Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white.opacity(0.72))
            }

            Button {
                revealHUDAndScheduleAutoHide(extend: true)
                model.clearRoute()
            } label: {
                Label("Clear", systemImage: "xmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .buttonStyle(.plain)
            .disabled(model.route == nil && model.results.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(panelBackground())
    }

    private var followPill: some View {
        Button {
            model.isFollowModeEnabled.toggle()
            if model.isFollowModeEnabled {
                model.bumpFollowPulse()
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: model.isFollowModeEnabled ? "location.fill" : "location.slash")
                    .font(.system(size: 12, weight: .bold))
                Text(model.isFollowModeEnabled ? "Follow ON" : "Follow OFF")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(model.isFollowModeEnabled ? Color.blue.opacity(0.86) : Color.black.opacity(0.58))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var zoomControls: some View {
        HStack(spacing: 8) {
            Button {
                model.zoomOut()
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.black.opacity(0.55)))
            }
            .buttonStyle(.plain)

            Button {
                model.zoomIn()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.black.opacity(0.55)))
            }
            .buttonStyle(.plain)

            Button("1x") {
                model.resetZoom()
            }
            .font(.system(size: 11, weight: .heavy, design: .rounded))
            .foregroundStyle(.white.opacity(0.95))
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.black.opacity(0.52))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
            )
            .buttonStyle(.plain)
        }
    }

    private var missingKeyCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Kakao REST API key is missing.")
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            Text("Account > Navigation (Kakao)에서 REST 키를 입력해 주세요.")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.82))
        }
        .padding(12)
        .background(panelBackground())
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            TextField("목적지 검색", text: $model.query)
                .focused($searchFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit {
                    Task { await runSearch() }
                }
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.12))
                )
                .foregroundStyle(.white)
                .onTapGesture {
                    revealHUDAndScheduleAutoHide(extend: true)
                }

            Button(model.isSearching ? "..." : "Search") {
                Task { await runSearch() }
            }
            .buttonStyle(SecondaryCarButtonStyle(fontSize: 16, height: 48, cornerRadius: 12))
            .frame(width: 96)
            .disabled(model.isSearching)
        }
        .padding(10)
        .background(panelBackground())
    }

    private var compactHowToCard: some View {
        HStack(spacing: 8) {
            Text("검색 -> 결과 탭 -> 경로 표시")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))

            Spacer()

            Button("강남역") {
                model.query = "강남역"
                Task { await runSearch() }
            }
            .buttonStyle(SecondaryCarButtonStyle(fontSize: 13, height: 36, cornerRadius: 10))
            .frame(width: 70)

            Button("판교역") {
                model.query = "판교역"
                Task { await runSearch() }
            }
            .buttonStyle(SecondaryCarButtonStyle(fontSize: 13, height: 36, cornerRadius: 10))
            .frame(width: 70)
        }
        .padding(10)
        .background(panelBackground(opacity: 0.50))
    }

    private var favoriteDestinationsRow: some View {
        HStack(spacing: 8) {
            favoriteSlotButton(slot: .home)
            favoriteSlotButton(slot: .work)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(panelBackground(opacity: 0.50))
    }

    private func favoriteSlotButton(slot: KakaoNavigationViewModel.FavoriteSlot) -> some View {
        let destination = model.favorite(for: slot)
        return Button {
            Task { await routeToFavorite(slot) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: slot == .home ? "house.fill" : "briefcase.fill")
                    .font(.system(size: 12, weight: .bold))
                VStack(alignment: .leading, spacing: 0) {
                    Text(slot.title)
                        .font(.system(size: 12, weight: .black, design: .rounded))
                    Text(destination?.name ?? "미설정")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(.white.opacity(destination == nil ? 0.72 : 0.95))
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(destination == nil ? 0.08 : 0.16))
            )
        }
        .buttonStyle(.plain)
        .disabled(destination == nil || model.isRouting)
        .contextMenu {
            if destination != nil {
                Button("Tesla 순정 네비로 전송") {
                    Task { await sendFavoriteToTesla(slot) }
                }
            }
        }
    }

    private var routeInfo: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let message = model.errorMessage {
                Text(message)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.red.opacity(0.95))
            }

            if let status = destinationPushStatus {
                Text(status.message)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(status.ok ? .green.opacity(0.95) : .orange.opacity(0.95))
            }

            if let cameraText = speedCameraAlertEngine.latestAlertText {
                Text(cameraText)
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(.yellow.opacity(0.95))
            }

            if let source = locationSourceLabel, !source.isEmpty {
                Text("위치 소스: \(source)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
            }

            if minimalMode, let destination = teslaNavigation?.destination {
                let lat = String(format: "%.5f", destination.lat)
                let lon = String(format: "%.5f", destination.lon)
                Text("Tesla 경로 연동: \(lat), \(lon)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.green.opacity(0.9))
            }

            if model.route == nil {
                HStack(spacing: 10) {
                    Text("속도 \(Int(vehicleSpeedKph.rounded())) km/h")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.92))
                    Text("경로 없음")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.65))
                }
            }

            if model.vehicleCoordinate == nil, let wakeVehicle {
                Button {
                    revealHUDAndScheduleAutoHide(extend: true)
                    wakeVehicle()
                } label: {
                    Label("Wake vehicle", systemImage: "bolt.fill")
                }
                .buttonStyle(SecondaryCarButtonStyle(fontSize: 14, height: 40, cornerRadius: 12))
                .disabled(!networkMonitor.isConnected)
                .frame(maxWidth: 170)
            }
        }
        .padding(10)
        .background(panelBackground())
    }

    private var resultsOverlay: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Results")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))

            ScrollView(showsIndicators: false) {
                VStack(spacing: 8) {
                    ForEach(model.results) { place in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(place.name)
                                .font(.system(size: 16, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(place.address)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.75))
                                .frame(maxWidth: .infinity, alignment: .leading)

                            HStack(spacing: 8) {
                                Button {
                                    Task { await startRoute(to: place) }
                                } label: {
                                    Label("경로 보기", systemImage: "map.fill")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(SecondaryCarButtonStyle(fontSize: 13, height: 34, cornerRadius: 10))

                                Button {
                                    Task { await pushDestinationToTesla(place) }
                                } label: {
                                    Label("Tesla로 전송", systemImage: "paperplane.fill")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(SecondaryCarButtonStyle(fontSize: 13, height: 34, cornerRadius: 10))
                                .disabled(sendDestinationToVehicle == nil)
                            }
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(0.11))
                        )
                        .contextMenu {
                            Button("집으로 저장") {
                                model.saveFavorite(.home, place: place)
                            }
                            Button("직장으로 저장") {
                                model.saveFavorite(.work, place: place)
                            }
                            Button("Tesla 순정 네비로 전송") {
                                Task { await pushDestinationToTesla(place) }
                            }
                            if model.favorite(for: .home) != nil {
                                Button("집 저장 해제", role: .destructive) {
                                    model.clearFavorite(.home)
                                }
                            }
                            if model.favorite(for: .work) != nil {
                                Button("직장 저장 해제", role: .destructive) {
                                    model.clearFavorite(.work)
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: minimalMode ? 300 : 220)
        }
        .padding(12)
        .frame(maxWidth: minimalMode ? .infinity : 340, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.58))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
    }

    private func panelBackground(opacity: Double = 0.56) -> some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.black.opacity(opacity))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.13), lineWidth: 1)
            )
    }

    private func runSearch() async {
        revealHUDAndScheduleAutoHide(extend: true)
        guard networkMonitor.isConnected else {
            model.errorMessage = "Offline. Connect to your iPhone hotspot and try again."
            return
        }
        let key = kakaoConfig.restAPIKey
        let near = model.vehicleCoordinate
        await model.searchPlaces(restAPIKey: key, near: near)
        searchFocused = false
    }

    private func startRoute(to place: KakaoPlace) async {
        revealHUDAndScheduleAutoHide(extend: true)
        guard networkMonitor.isConnected else {
            model.errorMessage = "Offline. Connect to your iPhone hotspot and try again."
            return
        }
        guard let origin = model.vehicleCoordinate else {
            model.errorMessage = "Waiting for vehicle location (origin)."
            return
        }
        let key = kakaoConfig.restAPIKey
        await model.startRoute(restAPIKey: key, origin: origin, destination: place.coordinate)
        searchFocused = false
    }

    private func routeToFavorite(_ slot: KakaoNavigationViewModel.FavoriteSlot) async {
        revealHUDAndScheduleAutoHide(extend: true)
        guard networkMonitor.isConnected else {
            model.errorMessage = "Offline. Connect to your iPhone hotspot and try again."
            return
        }
        guard let origin = model.vehicleCoordinate else {
            model.errorMessage = "Waiting for vehicle location (origin)."
            return
        }
        guard let destination = model.favorite(for: slot) else {
            model.errorMessage = "\(slot.title) 목적지가 아직 저장되지 않았습니다."
            return
        }
        let key = kakaoConfig.restAPIKey
        await model.startRoute(restAPIKey: key, origin: origin, destination: destination.coordinate)
    }

    private func sendFavoriteToTesla(_ slot: KakaoNavigationViewModel.FavoriteSlot) async {
        guard let destination = model.favorite(for: slot) else {
            destinationPushStatus = (false, "\(slot.title) 목적지가 아직 저장되지 않았습니다.")
            return
        }

        let place = KakaoPlace(
            id: "\(slot.rawValue)-favorite",
            name: destination.name,
            coordinate: destination.coordinate,
            address: destination.address,
            categoryGroupCode: nil,
            categoryName: nil
        )
        await pushDestinationToTesla(place)
    }

    private func pushDestinationToTesla(_ place: KakaoPlace) async {
        revealHUDAndScheduleAutoHide(extend: true)
        guard networkMonitor.isConnected else {
            destinationPushStatus = (false, "Offline. Connect hotspot and retry.")
            return
        }
        guard let sendDestinationToVehicle else {
            destinationPushStatus = (false, "Destination push is unavailable in current mode.")
            return
        }

        let result = await sendDestinationToVehicle(place)
        destinationPushStatus = result
        if !result.ok {
            model.errorMessage = result.message
        }
    }

    private func updateSpeedCameraAlerts() {
        speedCameraAlertEngine.update(
            nextGuide: model.nextSpeedCameraGuide,
            distanceMeters: model.distanceToNextSpeedCameraMeters(),
            speedKph: vehicleSpeedKph,
            speedLimitKph: model.nextSpeedCameraLimitKph,
            isPro: SubscriptionManager.shared.effectiveIsPro
        )
    }

    private func scheduleSpeedCameraPOIRefresh(force: Bool, delaySeconds: Double) {
        if minimalMode && !speedCameraPOIEnabledInMinimalMode {
            return
        }
        if model.route == nil {
            return
        }
        speedCameraRefreshTask?.cancel()
        speedCameraRefreshTask = Task { @MainActor in
            if delaySeconds > 0 {
                let ns = UInt64(delaySeconds * 1_000_000_000)
                try? await Task.sleep(nanoseconds: ns)
            }
            if Task.isCancelled { return }
            await model.refreshSpeedCameraPOIsIfNeeded(restAPIKey: kakaoConfig.restAPIKey, force: force)
        }
    }

    private var teslaRouteSignature: String {
        guard let destination = teslaNavigation?.destination, destination.isValid else { return "" }
        let destinationName = teslaNavigation?.destinationName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return String(format: "%.5f,%.5f|%@", destination.lat, destination.lon, destinationName)
    }

    private func scheduleTeslaRouteSync(force: Bool, delaySeconds: Double) {
        guard autoTeslaRouteSyncEnabled else { return }
        guard minimalMode else { return }
        teslaRouteSyncTask?.cancel()
        teslaRouteSyncTask = Task { @MainActor in
            if delaySeconds > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
            }
            if Task.isCancelled { return }
            await syncRouteFromTeslaIfNeeded(force: force)
        }
    }

    private func syncRouteFromTeslaIfNeeded(force: Bool) async {
        guard minimalMode else { return }
        guard let nav = teslaNavigation, let destination = nav.destination, destination.isValid else { return }
        guard networkMonitor.isConnected else { return }

        let signature = teslaRouteSignature
        guard !signature.isEmpty else { return }
        if !force, signature == lastSyncedTeslaRouteSignature, model.route != nil {
            return
        }

        // Prevent route API churn when vehicle location updates rapidly.
        let now = Date()
        if !force, now.timeIntervalSince(lastTeslaRouteAttemptAt) < 8 {
            return
        }
        lastTeslaRouteAttemptAt = now

        let key = kakaoConfig.restAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        guard let origin = model.vehicleCoordinate else { return }

        await model.startRoute(restAPIKey: key, origin: origin, destination: destination.coordinate)
        if model.route != nil {
            lastSyncedTeslaRouteSignature = signature
        }
    }

    private func distanceDurationText(route: KakaoRoute) -> String {
        let km = route.distanceMeters.map { Double($0) / 1000.0 }
        let min = route.durationSeconds.map { Double($0) / 60.0 }
        switch (km, min) {
        case (nil, nil):
            return "Route"
        case (let km?, nil):
            return String(format: "%.1f km", km)
        case (nil, let min?):
            return "\(Int(min.rounded())) min"
        case (let km?, let min?):
            return String(format: "%.1f km · %d min", km, Int(min.rounded()))
        }
    }

    private func turnByTurnBanner(next: KakaoGuide?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(Int(max(0, vehicleSpeedKph.rounded())))")
                    .font(.system(size: 46, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)

                Text("km/h")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))

                if let route = model.route {
                    Text(distanceDurationText(route: route))
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                        .padding(.leading, 6)
                }

                Spacer(minLength: 10)
            }

                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                    Text(next?.guidance ?? "안내 계산중")
                        .font(.system(size: 44, weight: .heavy, design: .rounded))
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    Text("다음 안내")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.72))
                }
                .foregroundStyle(.white)

                Spacer(minLength: 10)

                if let meters = model.distanceToNextGuideMeters() {
                    Text("\(meters)m")
                        .font(.system(size: 50, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.96))
                }
            }

            if let cameraMeters = model.distanceToNextSpeedCameraMeters() {
                HStack(spacing: 7) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 13, weight: .black))
                    Text("과속 카메라 \(cameraMeters)m")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                    if let guide = model.nextSpeedCameraGuide {
                        Text(guide.id.hasPrefix("poi:") ? "POI" : "Route")
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.white.opacity(0.16))
                            )
                    }
                }
                .foregroundStyle(.yellow.opacity(0.95))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
        .onTapGesture {
            // A tap on the banner should keep HUD visible a bit longer.
            revealHUDAndScheduleAutoHide(extend: true)
        }
    }

    private func clampedTopPanelOffset(
        proposalX: CGFloat,
        proposalY: CGFloat,
        containerSize: CGSize,
        panelWidth: CGFloat,
        topInset: CGFloat
    ) -> CGSize {
        let safeHorizontal = max(0, containerSize.width - panelWidth - 16)
        let safeVertical = max(0, containerSize.height - topInset - topPanelEstimatedHeight - 16)
        let x = min(max(0, proposalX), safeHorizontal)
        let y = min(max(0, proposalY), safeVertical)
        return CGSize(width: x, height: y)
    }

    private func clampedTurnBannerOffset(
        proposalX: CGFloat,
        proposalY: CGFloat,
        containerSize: CGSize,
        baseTopInset: CGFloat,
        bannerWidth: CGFloat
    ) -> CGSize {
        let leadingBase: CGFloat = 64
        let trailingReserve: CGFloat = 132
        let maxX = max(0, containerSize.width - leadingBase - trailingReserve - bannerWidth)
        let maxY = max(0, containerSize.height - baseTopInset - 90)
        let x = min(max(0, proposalX), maxX)
        let y = min(max(0, proposalY), maxY)
        return CGSize(width: x, height: y)
    }

    private func startFollowPulseLoop() {
        followPulseTask?.cancel()
        followPulseTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                if Task.isCancelled { return }
                if model.isFollowModeEnabled, model.vehicleCoordinate != nil {
                    model.bumpFollowPulse()
                }
            }
        }
    }

    private func persistPanelOffsets() {
        let defaults = UserDefaults.standard
        defaults.set(topPanelOffset.width, forKey: topPanelXKey)
        defaults.set(topPanelOffset.height, forKey: topPanelYKey)
        defaults.set(turnBannerOffset.width, forKey: bannerXKey)
        defaults.set(turnBannerOffset.height, forKey: bannerYKey)
    }

    private func restoreOffsetsIfNeeded(
        containerSize: CGSize,
        panelWidth: CGFloat,
        topInset: CGFloat,
        bannerWidth: CGFloat
    ) {
        guard !didRestorePersistedOffsets else { return }
        didRestorePersistedOffsets = true

        let defaults = UserDefaults.standard
        let topX = CGFloat(defaults.double(forKey: topPanelXKey))
        let topY = CGFloat(defaults.double(forKey: topPanelYKey))
        let bannerX = CGFloat(defaults.double(forKey: bannerXKey))
        let bannerY = CGFloat(defaults.double(forKey: bannerYKey))

        topPanelOffset = clampedTopPanelOffset(
            proposalX: topX,
            proposalY: topY,
            containerSize: containerSize,
            panelWidth: panelWidth,
            topInset: topInset
        )
        topPanelAnchorOffset = topPanelOffset

        turnBannerOffset = clampedTurnBannerOffset(
            proposalX: bannerX,
            proposalY: bannerY,
            containerSize: containerSize,
            baseTopInset: topInset,
            bannerWidth: bannerWidth
        )
        turnBannerAnchorOffset = turnBannerOffset
    }

    private func clampPersistedOffsets(
        containerSize: CGSize,
        panelWidth: CGFloat,
        topInset: CGFloat,
        bannerWidth: CGFloat
    ) {
        topPanelOffset = clampedTopPanelOffset(
            proposalX: topPanelOffset.width,
            proposalY: topPanelOffset.height,
            containerSize: containerSize,
            panelWidth: panelWidth,
            topInset: topInset
        )
        topPanelAnchorOffset = topPanelOffset

        turnBannerOffset = clampedTurnBannerOffset(
            proposalX: turnBannerOffset.width,
            proposalY: turnBannerOffset.height,
            containerSize: containerSize,
            baseTopInset: topInset,
            bannerWidth: bannerWidth
        )
        turnBannerAnchorOffset = turnBannerOffset
        persistPanelOffsets()
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

private extension KakaoNavigationPaneView {
    /// Shows HUD and schedules auto-hide with a generous delay.
    func revealHUDAndScheduleAutoHide(extend: Bool = false) {
        if minimalMode {
            if !hudVisible { hudVisible = true }
            autoHideTask?.cancel()
            autoHideTask = nil
            return
        }

        // If user is actively typing in search, keep HUD visible.
        if searchFocused {
            if !hudVisible { hudVisible = true }
            autoHideTask?.cancel()
            autoHideTask = nil
            return
        }

        if !hudVisible {
            withAnimation(.easeInOut(duration: 0.18)) {
                hudVisible = true
            }
        }

        // Reset timer on any interaction.
        autoHideTask?.cancel()
        autoHideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(autoHideSeconds * 1_000_000_000))
            if Task.isCancelled { return }
            if searchFocused { return }
            withAnimation(.easeInOut(duration: 0.18)) {
                hudVisible = false
            }
        }

        if extend {
            // No-op: extend is handled by cancelling and rescheduling.
        }
    }
}

@MainActor
final class SpeedCameraAlertEngine: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var latestAlertText: String?

    private let thresholdsMeters = [1000, 500, 300, 150]
    private let synthesizer = AVSpeechSynthesizer()
    private var beepEngine: AVAudioEngine?
    private var beepPlayer: AVAudioPlayerNode?
    private var beepFormat: AVAudioFormat?
    private var didConfigureAudioSession = false
    private var deactivateAudioTask: Task<Void, Never>?
    private var currentGuideID: String?
    private var firedThresholds: Set<Int> = []
    private var lastSpokenAt: Date = .distantPast
    private var didWarnOverspeedForCurrentGuide = false
    private var lastOverspeedBeepAt: Date = .distantPast

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func reset() {
        currentGuideID = nil
        firedThresholds.removeAll()
        latestAlertText = nil
        didWarnOverspeedForCurrentGuide = false
        lastOverspeedBeepAt = .distantPast
    }

    func playDebugTest() {
        activateAudioSession()
        playDoubleBeep()

        let utterance = AVSpeechUtterance(string: "서브대시 음성 테스트입니다.")
        utterance.voice = AVSpeechSynthesisVoice(language: "ko-KR")
        utterance.rate = 0.46
        utterance.volume = 0.95
        synthesizer.speak(utterance)
    }

    func update(nextGuide: KakaoGuide?, distanceMeters: Int?, speedKph: Double, speedLimitKph: Int?, isPro: Bool) {
        guard let nextGuide, let distanceMeters, distanceMeters >= 0 else {
            reset()
            return
        }

        if currentGuideID != nextGuide.id {
            currentGuideID = nextGuide.id
            firedThresholds.removeAll()
            latestAlertText = nil
            didWarnOverspeedForCurrentGuide = false
        }

        if distanceMeters > 1_800 {
            latestAlertText = nil
            return
        }

        let limitForDisplay = isPro ? speedLimitKph : nil
        if let limit = limitForDisplay, limit > 0 {
            latestAlertText = "과속 카메라 \(distanceMeters)m · 제한 \(limit)"
        } else {
            latestAlertText = "과속 카메라 \(distanceMeters)m"
        }

        // Free plan: show minimal text only (no voice/beep, no limit display).
        guard isPro else { return }

        // Overspeed warning: within 500m and speed above limit. Keep beeping until the driver slows down.
        if let limit = speedLimitKph, limit > 0, distanceMeters <= 500 {
            let roundedSpeed = Int(max(0, speedKph.rounded()))
            if roundedSpeed >= limit + 1 {
                latestAlertText = "과속! 제한 \(limit) · \(distanceMeters)m"
                let now = Date()
                if now.timeIntervalSince(lastOverspeedBeepAt) >= 1.2 {
                    lastOverspeedBeepAt = now
                    activateAudioSession()
                    playDoubleBeep()
                    scheduleDeactivateAudioSession(after: 0.9)
                }
                if !didWarnOverspeedForCurrentGuide {
                    didWarnOverspeedForCurrentGuide = true
                }
            } else {
                // Reset the beep timer once we are back under the limit.
                lastOverspeedBeepAt = .distantPast
            }
        }

        let notFired = thresholdsMeters.filter { distanceMeters <= $0 && !firedThresholds.contains($0) }
        guard let stage = notFired.min() else { return }

        // If we jumped directly near the camera, suppress upper-level warnings.
        for threshold in thresholdsMeters where threshold >= stage {
            firedThresholds.insert(threshold)
        }

        let now = Date()
        guard now.timeIntervalSince(lastSpokenAt) >= 5 else { return }
        lastSpokenAt = now

        activateAudioSession()

        let roundedSpeed = Int(max(0, speedKph.rounded()))
        var text = "과속 단속 카메라 \(stage)미터 앞입니다"
        if stage <= 300, roundedSpeed >= 50 {
            text += ". 감속하세요"
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "ko-KR")
        utterance.rate = 0.46
        utterance.volume = 0.95
        synthesizer.speak(utterance)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            scheduleDeactivateAudioSession(after: 0.6)
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            scheduleDeactivateAudioSession(after: 0.6)
        }
    }

    private func configureAudioSessionIfNeeded() {
        guard !didConfigureAudioSession else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .mixWithOthers])
            didConfigureAudioSession = true
        } catch {
            // Non-fatal: speech can still work with the default session.
        }
    }

    private func activateAudioSession() {
        configureAudioSessionIfNeeded()
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            // Non-fatal
        }
    }

    private func scheduleDeactivateAudioSession(after seconds: Double) {
        deactivateAudioTask?.cancel()
        let nanos = UInt64(max(0.2, seconds) * 1_000_000_000.0)
        deactivateAudioTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: nanos)
            guard !self.synthesizer.isSpeaking else {
                self.scheduleDeactivateAudioSession(after: 0.8)
                return
            }
            do {
                try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
            } catch {
                // Non-fatal
            }
        }
    }

    private func playDoubleBeep() {
        activateAudioSession()

        let engine: AVAudioEngine
        let player: AVAudioPlayerNode
        let format: AVAudioFormat

        if let beepEngine, let beepPlayer, let beepFormat {
            engine = beepEngine
            player = beepPlayer
            format = beepFormat
        } else {
            let createdEngine = AVAudioEngine()
            let createdPlayer = AVAudioPlayerNode()
            let createdFormat = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!

            createdEngine.attach(createdPlayer)
            createdEngine.connect(createdPlayer, to: createdEngine.mainMixerNode, format: createdFormat)
            do {
                try createdEngine.start()
            } catch {
                return
            }
            createdPlayer.play()

            beepEngine = createdEngine
            beepPlayer = createdPlayer
            beepFormat = createdFormat

            engine = createdEngine
            player = createdPlayer
            format = createdFormat
        }

        guard engine.isRunning else { return }
        if !player.isPlaying {
            player.play()
        }

        let buffer = makeDoubleBeepBuffer(format: format)
        player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
    }

    private func makeDoubleBeepBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer {
        let sampleRate = format.sampleRate
        let beepSeconds = 0.12
        let gapSeconds = 0.06
        let totalSeconds = (beepSeconds * 2.0) + gapSeconds
        let totalFrames = AVAudioFrameCount(totalSeconds * sampleRate)

        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames)!
        buffer.frameLength = totalFrames

        guard let channel = buffer.floatChannelData?[0] else {
            return buffer
        }

        let freq1 = 880.0
        let freq2 = 660.0
        let amplitude = 0.22
        let attack = 0.015
        let release = 0.03

        func envelope(_ t: Double, _ duration: Double) -> Double {
            if t < 0 { return 0 }
            if t > duration { return 0 }
            let a = min(1.0, t / attack)
            let r = min(1.0, max(0.0, (duration - t) / release))
            return a * r
        }

        for i in 0..<Int(totalFrames) {
            let t = Double(i) / sampleRate
            var value = 0.0
            if t < beepSeconds {
                value = sin(2.0 * Double.pi * freq1 * t) * amplitude * envelope(t, beepSeconds)
            } else if t > (beepSeconds + gapSeconds) {
                let t2 = t - beepSeconds - gapSeconds
                value = sin(2.0 * Double.pi * freq2 * t2) * amplitude * envelope(t2, beepSeconds)
            } else {
                value = 0.0
            }
            channel[i] = Float(value)
        }

        return buffer
    }
}
