import CoreLocation
import Foundation

struct KakaoPlace: Identifiable {
    let id: String
    let name: String
    let coordinate: CLLocationCoordinate2D
    let address: String
}

struct KakaoRoute {
    let polyline: [CLLocationCoordinate2D]
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
