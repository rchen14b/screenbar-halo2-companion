import Foundation
import Security

/// The bridge's hostname in UserDefaults; its API encryption key in the login Keychain.
enum Credentials {
    static let service = "io.github.rchen14b.ScreenBarHalo2"
    private static let hostKey = "bridgeHost"

    static var host: String {
        get { UserDefaults.standard.string(forKey: hostKey) ?? "screenbar-halo2.local" }
        set { UserDefaults.standard.set(newValue, forKey: hostKey) }
    }

    static var apiKey: String? {
        get {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: "apiKey",
                kSecReturnData as String: true,
            ]
            var item: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
                  let data = item as? Data
            else { return nil }
            return String(data: data, encoding: .utf8)
        }
        set {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: "apiKey",
            ]
            SecItemDelete(query as CFDictionary)
            guard let newValue, !newValue.isEmpty else { return }
            var item = query
            item[kSecValueData as String] = Data(newValue.utf8)
            SecItemAdd(item as CFDictionary, nil)
        }
    }
}
