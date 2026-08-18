import Foundation
import Security

/// A UUID persisted in the Keychain (not UserDefaults) so it survives app
/// deletion and reinstall — used to key the vision-proxy's daily scan quota,
/// which exists specifically to stop that quota being reset by reinstalling.
enum DeviceIdentifier {
    private static let service = "com.vibecoding.ProductScanner.deviceID"
    private static let account = "deviceID"

    static let current: String = read() ?? {
        let generated = UUID().uuidString
        save(generated)
        return generated
    }()

    private static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func save(_ value: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = Data(value.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attributes as CFDictionary, nil)
    }
}
