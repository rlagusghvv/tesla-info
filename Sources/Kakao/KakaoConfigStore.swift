import Foundation

@MainActor
final class KakaoConfigStore: ObservableObject {
    static let shared = KakaoConfigStore()

    @Published var restAPIKey: String

    private init() {
        restAPIKey = KeychainStore.getString(Keys.restAPIKey) ?? ""
    }

    func save() {
        do {
            try KeychainStore.setString(restAPIKey.trimmingCharacters(in: .whitespacesAndNewlines), for: Keys.restAPIKey)
        } catch {
            // Non-fatal; the UI can still continue with an in-memory key.
        }
    }

    private enum Keys {
        static let restAPIKey = "kakao.rest_api_key"
    }
}

