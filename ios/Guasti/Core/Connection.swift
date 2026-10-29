import Foundation
import Security

/// On és el pont amb Google (URL de l'Apps Script) i la clau per fer-lo servir.
@MainActor
final class Connection: ObservableObject {
    static let shared = Connection()

    @Published var baseURL: String {
        didSet { UserDefaults.standard.set(baseURL, forKey: "apiURL") }
    }
    @Published var apiKey: String {
        didSet { Keychain.set(apiKey, for: "apiKey") }
    }

    private init() {
        baseURL = UserDefaults.standard.string(forKey: "apiURL") ?? ""
        apiKey = Keychain.get("apiKey") ?? ""
    }

    var isConfigured: Bool { client != nil }

    var client: AppsScriptClient? {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty, let url = URL(string: trimmed), url.scheme == "https" else { return nil }
        return AppsScriptClient(baseURL: url, key: apiKey)
    }
}

enum Keychain {
    static func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String, for account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }
        var add = query
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }
}
