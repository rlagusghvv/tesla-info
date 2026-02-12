import MapKit
import SwiftUI

struct KakaoRouteMapView: View {
    let vehicleCoordinate: CLLocationCoordinate2D?
    let route: KakaoRoute?
    let followEnabled: Bool
    let routeRevision: Int
    let zoomOffset: Int
    let zoomRevision: Int
    let followPulse: Int

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var lastFocusedVehicle: CLLocationCoordinate2D?

    var body: some View {
        Map(position: $cameraPosition) {
            if let route, !route.polyline.isEmpty {
                MapPolyline(coordinates: route.polyline)
                    .stroke(.blue, lineWidth: 6)
            }

            if let vehicleCoordinate {
                Annotation("Car", coordinate: vehicleCoordinate) {
                    ZStack {
                        Circle()
                            .fill(.blue)
                            .frame(width: 30, height: 30)
                        Image(systemName: "car.fill")
                            .foregroundStyle(.white)
                            .font(.system(size: 13, weight: .bold))
                    }
                }
            }
        }
        .mapStyle(.standard(elevation: .flat))
        .onAppear {
            focusIfNeeded(force: true)
        }
        .onChange(of: vehicleCoordinate?.latitude) { _, _ in
            focusIfNeeded(force: false)
        }
        .onChange(of: route?.polyline.count) { _, _ in
            focusIfNeeded(force: true)
        }
        .onChange(of: routeRevision) { _, _ in
            focusIfNeeded(force: true)
        }
        .onChange(of: zoomRevision) { _, _ in
            focusIfNeeded(force: true)
        }
        .onChange(of: followPulse) { _, _ in
            guard followEnabled else { return }
            focusIfNeeded(force: true)
        }
        .onChange(of: followEnabled) { _, enabled in
            if enabled {
                focusIfNeeded(force: true)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func focusIfNeeded(force: Bool) {
        if let route, !route.polyline.isEmpty, followEnabled, let vehicleCoordinate {
            if !force, let lastFocusedVehicle {
                let d = abs(lastFocusedVehicle.latitude - vehicleCoordinate.latitude)
                    + abs(lastFocusedVehicle.longitude - vehicleCoordinate.longitude)
                if d < 0.00003 { return }
            }
            lastFocusedVehicle = vehicleCoordinate

            let region = MKCoordinateRegion(
                center: vehicleCoordinate,
                span: MKCoordinateSpan(
                    latitudeDelta: clampedDelta(0.0048 * zoomMultiplier()),
                    longitudeDelta: clampedDelta(0.0048 * zoomMultiplier())
                )
            )
            withAnimation(.easeInOut(duration: 0.35)) {
                cameraPosition = .region(region)
            }
            return
        }

        if let route, !route.polyline.isEmpty {
            guard force else { return }
            guard let region = boundingRegion(for: route.polyline) else { return }
            withAnimation(.easeInOut(duration: 0.35)) {
                cameraPosition = .region(region)
            }
            return
        }

        guard let vehicleCoordinate else { return }

        if !force, let lastFocusedVehicle {
            let d = abs(lastFocusedVehicle.latitude - vehicleCoordinate.latitude)
                + abs(lastFocusedVehicle.longitude - vehicleCoordinate.longitude)
            if d < 0.00006 { return }
        }
        lastFocusedVehicle = vehicleCoordinate

        let region = MKCoordinateRegion(
            center: vehicleCoordinate,
            span: MKCoordinateSpan(
                latitudeDelta: clampedDelta(0.0075 * zoomMultiplier()),
                longitudeDelta: clampedDelta(0.0075 * zoomMultiplier())
            )
        )
        withAnimation(.easeInOut(duration: 0.35)) {
            cameraPosition = .region(region)
        }
    }

    private func boundingRegion(for coords: [CLLocationCoordinate2D]) -> MKCoordinateRegion? {
        guard let first = coords.first else { return nil }

        var minLat = first.latitude
        var maxLat = first.latitude
        var minLon = first.longitude
        var maxLon = first.longitude

        for c in coords.dropFirst() {
            minLat = min(minLat, c.latitude)
            maxLat = max(maxLat, c.latitude)
            minLon = min(minLon, c.longitude)
            maxLon = max(maxLon, c.longitude)
        }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2.0,
            longitude: (minLon + maxLon) / 2.0
        )

        let latDelta = clampedDelta(max(0.01, (maxLat - minLat) * 1.35) * zoomMultiplier())
        let lonDelta = clampedDelta(max(0.01, (maxLon - minLon) * 1.35) * zoomMultiplier())

        return MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
        )
    }

    private func zoomMultiplier() -> CLLocationDegrees {
        pow(1.35, Double(zoomOffset))
    }

    private func clampedDelta(_ raw: CLLocationDegrees) -> CLLocationDegrees {
        min(0.08, max(0.0016, raw))
    }
}
