import Foundation
import Security

enum KeychainStore {
    private static let service = "com.kimhyeonho.teslasubdash"

    static func getString(_ key: String) -> String? {
        guard let data = getData(key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func setString(_ value: String, for key: String) throws {
        try setData(Data(value.utf8), for: key)
    }

    static func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }

    private static func getData(_ key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else {
            return nil
        }
        return item as? Data
    }

    private static func setData(_ data: Data, for key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let existsStatus = SecItemCopyMatching(query as CFDictionary, nil)
        if existsStatus == errSecSuccess {
            let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            guard status == errSecSuccess else {
                throw KeychainError.updateFailed(status)
            }
            return
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.addFailed(status)
        }
    }
}

enum KeychainError: LocalizedError {
    case addFailed(OSStatus)
    case updateFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .addFailed(let status):
            return "Keychain add failed (\(status))."
        case .updateFailed(let status):
            return "Keychain update failed (\(status))."
        }
    }
}

