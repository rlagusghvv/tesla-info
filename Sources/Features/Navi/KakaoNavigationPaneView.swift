import CoreLocation
import SwiftUI

struct KakaoNavigationPaneView: View {
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    @EnvironmentObject private var kakaoConfig: KakaoConfigStore
    @ObservedObject var model: KakaoNavigationViewModel

    let vehicleLocation: VehicleLocation
    let vehicleSpeedKph: Double
    let wakeVehicle: (() -> Void)?

    @FocusState private var searchFocused: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                mapCanvas
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

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
                .frame(maxWidth: min(proxy.size.width * 0.64, 560), alignment: .topLeading)
            }
        }
        .onAppear {
            model.updateVehicle(location: vehicleLocation, speedKph: vehicleSpeedKph)
            if model.route == nil, model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                searchFocused = true
            }
        }
        .onChange(of: vehicleLocation) { _, _ in
            model.updateVehicle(location: vehicleLocation, speedKph: vehicleSpeedKph)
        }
        .onChange(of: vehicleSpeedKph) { _, _ in
            model.updateVehicle(location: vehicleLocation, speedKph: vehicleSpeedKph)
        }
    }

    private var mapCanvas: some View {
        let jsKey = kakaoConfig.javaScriptKey.trimmingCharacters(in: .whitespacesAndNewlines)

        return Group {
            if !jsKey.isEmpty {
                KakaoWebRouteMapView(
                    javaScriptKey: jsKey,
                    vehicleCoordinate: model.vehicleCoordinate,
                    route: model.route
                )
            } else {
                KakaoRouteMapView(
                    vehicleCoordinate: model.vehicleCoordinate,
                    route: model.route
                )
            }
        }
        .overlay(alignment: .topLeading) {
            if !model.results.isEmpty, model.route == nil {
                resultsOverlay
                    .padding(12)
                    .padding(.top, 170)
            }
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

            Button {
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
                HStack {
                    Text("다음: \(next.guidance)")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer()
                    if let meters = model.distanceToNextGuideMeters() {
                        Text("\(meters)m")
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
            } else if model.vehicleCoordinate == nil, let wakeVehicle {
                Button {
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
        guard networkMonitor.isConnected else {
            model.errorMessage = "Offline. Connect to your iPhone hotspot and try again."
            return
        }
        let key = kakaoConfig.restAPIKey
        let near = model.vehicleCoordinate
        await model.searchPlaces(restAPIKey: key, near: near)
    }

    private func startRoute(to place: KakaoPlace) async {
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
}
