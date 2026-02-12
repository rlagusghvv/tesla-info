import CoreLocation
import SwiftUI

struct KakaoNavigationPaneView: View {
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    @EnvironmentObject private var kakaoConfig: KakaoConfigStore
    @ObservedObject var model: KakaoNavigationViewModel

    let vehicleLocation: VehicleLocation
    let vehicleSpeedKph: Double
    let wakeVehicle: (() -> Void)?

    /// Controls whether overlays (HUD/search/results/route info) are visible.
    @Binding var hudVisible: Bool

    @FocusState private var searchFocused: Bool
    @State private var topPanelOffset: CGSize = .zero
    @State private var topPanelAnchorOffset: CGSize = .zero
    @State private var turnBannerOffset: CGSize = .zero
    @State private var turnBannerAnchorOffset: CGSize = .zero

    @State private var autoHideTask: Task<Void, Never>?

    private let autoHideSeconds: Double = 14

    var body: some View {
        GeometryReader { proxy in
            let panelWidth = min(proxy.size.width * 0.64, 560)
            let topInset = max(24.0, proxy.safeAreaInsets.top + 16)
            let resultsTopPadding = topInset + topPanelEstimatedHeight + topPanelOffset.height + 10
            let turnBannerWidth = max(180.0, min(proxy.size.width - 188, 560))

            ZStack(alignment: .topLeading) {
                mapCanvas(resultsTopPadding: resultsTopPadding, topInset: topInset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        revealHUDAndScheduleAutoHide()
                    }

                // Minimal turn-by-turn banner (keeps navigation feeling alive even when HUD is hidden)
                if let next = model.nextGuide, model.route != nil {
                    turnByTurnBanner(next: next)
                        .frame(maxWidth: turnBannerWidth, alignment: .leading)
                        .padding(.top, topInset + 2 + turnBannerOffset.height)
                        .padding(.leading, 64 + turnBannerOffset.width)
                        .padding(.trailing, 110)
                        .gesture(
                            DragGesture(minimumDistance: 2, coordinateSpace: .local)
                                .onChanged { value in
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
                .padding(.top, topInset + 6)
                .padding(.leading, 10)
                .opacity(hudVisible ? 0.55 : 1.0)
            }
            .animation(.easeInOut(duration: 0.18), value: hudVisible)
        }
        .onAppear {
            model.updateVehicle(location: vehicleLocation, speedKph: vehicleSpeedKph)
            searchFocused = false
            topPanelOffset = .zero
            topPanelAnchorOffset = .zero
            turnBannerOffset = .zero
            turnBannerAnchorOffset = .zero
            revealHUDAndScheduleAutoHide()
        }
        .onDisappear {
            autoHideTask?.cancel()
            autoHideTask = nil
        }
        .onChange(of: vehicleLocation) { _, _ in
            model.updateVehicle(location: vehicleLocation, speedKph: vehicleSpeedKph)
        }
        .onChange(of: vehicleSpeedKph) { _, _ in
            model.updateVehicle(location: vehicleLocation, speedKph: vehicleSpeedKph)
        }
    }

    private func mapCanvas(resultsTopPadding: CGFloat, topInset: CGFloat) -> some View {
        let jsKey = kakaoConfig.javaScriptKey.trimmingCharacters(in: .whitespacesAndNewlines)

        return Group {
            if !jsKey.isEmpty {
                KakaoWebRouteMapView(
                    javaScriptKey: jsKey,
                    vehicleCoordinate: model.vehicleCoordinate,
                    vehicleSpeedKph: vehicleSpeedKph,
                    route: model.route,
                    followEnabled: model.isFollowModeEnabled,
                    routeRevision: model.routeRevision
                )
            } else {
                KakaoRouteMapView(
                    vehicleCoordinate: model.vehicleCoordinate,
                    route: model.route,
                    followEnabled: model.isFollowModeEnabled,
                    routeRevision: model.routeRevision
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
            followPill
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
            Text(jsKey.isEmpty ? "Map: Apple fallback (set Kakao JS key in Account)" : "Map: Kakao")
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

            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white.opacity(0.72))

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

    private var routeInfo: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let message = model.errorMessage {
                Text(message)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.red.opacity(0.95))
            }

            HStack(spacing: 10) {
                Text("속도 \(Int(vehicleSpeedKph.rounded())) km/h")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))

                if let r = model.route {
                    Text(distanceDurationText(route: r))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                } else {
                    Text("경로 없음")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.65))
                }
            }

            if let next = model.nextGuide {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(next.guidance)
                            .font(.system(size: 18, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Spacer()
                        if let meters = model.distanceToNextGuideMeters() {
                            Text("\(meters)m")
                                .font(.system(size: 18, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white.opacity(0.9))
                        }
                    }
                    Text("다음 안내")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.65))
                }
            } else if model.vehicleCoordinate == nil, let wakeVehicle {
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
                        Button {
                            Task { await startRoute(to: place) }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(place.name)
                                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(place.address)
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.75))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.white.opacity(0.11))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 220)
        }
        .padding(12)
        .frame(width: 340, alignment: .leading)
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

    private func turnByTurnBanner(next: KakaoGuide) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(next.guidance)
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("다음 안내")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
            }

            Spacer(minLength: 10)

            if let meters = model.distanceToNextGuideMeters() {
                Text("\(meters)m")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.95))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.55))
                .overlay(
                    Capsule(style: .continuous)
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
        let trailingReserve: CGFloat = 110
        let maxX = max(0, containerSize.width - leadingBase - trailingReserve - bannerWidth)
        let maxY = max(0, containerSize.height - baseTopInset - 90)
        let x = min(max(0, proposalX), maxX)
        let y = min(max(0, proposalY), maxY)
        return CGSize(width: x, height: y)
    }
}

private extension KakaoNavigationPaneView {
    /// Shows HUD and schedules auto-hide with a generous delay.
    func revealHUDAndScheduleAutoHide(extend: Bool = false) {
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
