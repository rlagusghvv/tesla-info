import MapKit
import SwiftUI

struct TelemetryMapView: View {
    let location: VehicleLocation

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var lastFocused: VehicleLocation?

    var body: some View {
        Group {
            if location.isValid {
                Map(position: $cameraPosition) {
                    Annotation("Tesla", coordinate: location.coordinate) {
                        ZStack {
                            Circle()
                                .fill(.blue)
                                .frame(width: 34, height: 34)
                            Image(systemName: "car.fill")
                                .foregroundStyle(.white)
                                .font(.system(size: 14, weight: .bold))
                        }
                    }
                }
                .mapStyle(.standard(elevation: .flat))
                .onAppear {
                    focus(location: location, force: true)
                }
                .onChange(of: location) { _, newLocation in
                    focus(location: newLocation, force: false)
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "location.slash")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white.opacity(0.9))

                    Text("Waiting for vehicle location")
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)

                    Text("If the car is asleep, tap Wake and try again.")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 18)
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
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func focus(location: VehicleLocation, force: Bool) {
        guard location.isValid else { return }

        if !force, let lastFocused {
            // Avoid thrashing the map camera for tiny/no coordinate changes.
            let d = abs(lastFocused.lat - location.lat) + abs(lastFocused.lon - location.lon)
            if d < 0.0002 { return }
        }
        lastFocused = location

        let region = MKCoordinateRegion(
            center: location.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        )
        var txn = Transaction()
        txn.animation = nil
        withTransaction(txn) {
            cameraPosition = .region(region)
        }
    }
}
