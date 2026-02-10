import MapKit
import SwiftUI

struct KakaoRouteMapView: View {
    let vehicleCoordinate: CLLocationCoordinate2D?
    let route: KakaoRoute?

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
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func focusIfNeeded(force: Bool) {
        if let route, !route.polyline.isEmpty {
            // Keep the camera stable while driving. Refocus only when forced (route changes or first appear).
            guard force else { return }
            guard let region = boundingRegion(for: route.polyline) else { return }
            var txn = Transaction()
            txn.animation = nil
            withTransaction(txn) {
                cameraPosition = .region(region)
            }
            return
        }

        guard let vehicleCoordinate else { return }

        if !force, let lastFocusedVehicle {
            let d = abs(lastFocusedVehicle.latitude - vehicleCoordinate.latitude)
                + abs(lastFocusedVehicle.longitude - vehicleCoordinate.longitude)
            if d < 0.0002 { return }
        }
        lastFocusedVehicle = vehicleCoordinate

        let region = MKCoordinateRegion(
            center: vehicleCoordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        )
        var txn = Transaction()
        txn.animation = nil
        withTransaction(txn) {
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

        let latDelta = max(0.01, (maxLat - minLat) * 1.35)
        let lonDelta = max(0.01, (maxLon - minLon) * 1.35)

        return MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
        )
    }
}
