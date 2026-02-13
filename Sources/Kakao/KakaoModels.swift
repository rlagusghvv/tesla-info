import CoreLocation
import Foundation

struct KakaoPlace: Identifiable {
    let id: String
    let name: String
    let coordinate: CLLocationCoordinate2D
    let address: String
    let categoryGroupCode: String?
    let categoryName: String?
}

struct KakaoRoute {
    let polyline: [CLLocationCoordinate2D]
    // Higher resolution polyline for matching (speed cameras, progress, etc).
    // Keep `polyline` lightweight for MapKit rendering on smaller devices.
    let polylineDense: [CLLocationCoordinate2D]
    let guides: [KakaoGuide]
    let distanceMeters: Int?
    let durationSeconds: Int?
}

struct KakaoGuide: Identifiable {
    let id: String
    let name: String
    let guidance: String
    let coordinate: CLLocationCoordinate2D
    let distanceMeters: Int?
    let durationSeconds: Int?
    let type: Int?
}
