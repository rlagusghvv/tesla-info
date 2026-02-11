import Foundation

@MainActor
final class KakaoConfigStore: ObservableObject {
    static let shared = KakaoConfigStore()

    @Published var restAPIKey: String
    @Published var javaScriptKey: String

    private init() {
        restAPIKey = KeychainStore.getString(Keys.restAPIKey) ?? ""
        javaScriptKey = KeychainStore.getString(Keys.javaScriptKey) ?? ""
    }

    func save() {
        do {
            try KeychainStore.setString(restAPIKey.trimmingCharacters(in: .whitespacesAndNewlines), for: Keys.restAPIKey)
            try KeychainStore.setString(javaScriptKey.trimmingCharacters(in: .whitespacesAndNewlines), for: Keys.javaScriptKey)
        } catch {
            // Non-fatal; the UI can still continue with an in-memory key.
        }
    }

    private enum Keys {
        static let restAPIKey = "kakao.rest_api_key"
        static let javaScriptKey = "kakao.javascript_key"
    }
}
