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
        VStack(spacing: 10) {
            header

            if kakaoConfig.restAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                missingKeyCard
            } else {
                searchBar
            }

            if model.route == nil, model.results.isEmpty {
                howToCard
            }

            routeInfo

            KakaoRouteMapView(
                vehicleCoordinate: model.vehicleCoordinate,
                route: model.route
            )
            .overlay(alignment: .topLeading) {
                if !model.results.isEmpty, model.route == nil {
                    resultsOverlay
                        .padding(12)
                }
            }
        }
        .onAppear {
            model.updateVehicle(location: vehicleLocation, speedKph: vehicleSpeedKph)
            if model.route == nil, model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // Make it obvious that typing a destination is the next step.
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

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("In-app Navigation")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text("Powered by Kakao APIs (MVP)")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
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
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .buttonStyle(.plain)
            .disabled(model.route == nil && model.results.isEmpty)
        }
    }

    private var missingKeyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Kakao REST API key is not set.")
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)

            Text("Open Account > Navigation (Kakao) and paste your REST API key.")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            TextField("Search destination (e.g., 강남역)", text: $model.query)
                .focused($searchFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit {
                    Task { await runSearch() }
                }
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.white.opacity(0.14), lineWidth: 1)
                        )
                )
                .foregroundStyle(.white)

            Button(model.isSearching ? "..." : "Search") {
                Task { await runSearch() }
            }
            .buttonStyle(SecondaryCarButtonStyle(fontSize: 18, height: 56, cornerRadius: 16))
            .frame(width: 110)
            .disabled(model.isSearching)
        }
    }

    private var howToCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How to start")
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))

            Text("1) Type a destination\n2) Tap Search\n3) Tap a result to draw the route")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)

            if model.vehicleCoordinate == nil {
                Text("Car location is not available yet. If it stays at 0,0, tap Wake in the side panel.")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Button("Try: 강남역") {
                    model.query = "강남역"
                    Task { await runSearch() }
                }
                .buttonStyle(SecondaryCarButtonStyle(fontSize: 16, height: 52, cornerRadius: 16))

                Button("Try: 판교역") {
                    model.query = "판교역"
                    Task { await runSearch() }
                }
                .buttonStyle(SecondaryCarButtonStyle(fontSize: 16, height: 52, cornerRadius: 16))
            }

            if model.vehicleCoordinate == nil, let wakeVehicle {
                Button {
                    wakeVehicle()
                } label: {
                    Label("Wake vehicle", systemImage: "bolt.fill")
                }
                .buttonStyle(SecondaryCarButtonStyle(fontSize: 16, height: 52, cornerRadius: 16))
                .disabled(!networkMonitor.isConnected)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
        )
    }

    private var routeInfo: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let message = model.errorMessage {
                Text(message)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.red.opacity(0.95))
            }

            HStack(spacing: 12) {
                Text("Speed \(Int(vehicleSpeedKph.rounded())) km/h")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))

                if let r = model.route {
                    Text(distanceDurationText(route: r))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                } else {
                    Text("No active route (search a destination)")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.65))
                }
            }

            if let next = model.nextGuide {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Next")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.7))
                        Text(next.guidance)
                            .font(.system(size: 18, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                    }

                    Spacer()

                    if let meters = model.distanceToNextGuideMeters() {
                        Text("\(meters)m")
                            .font(.system(size: 18, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
        )
    }

    private var resultsOverlay: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Results")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))

            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    ForEach(model.results) { place in
                        Button {
                            Task { await startRoute(to: place) }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(place.name)
                                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(place.address)
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.75))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color.white.opacity(0.10))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 260)
        }
        .padding(14)
        .frame(width: 360, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
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
