import Foundation
import Security

/// The AI Gateway key lives in the iPhone Keychain, never in plain settings.
enum Keychain {
    private static let account = "ai-gateway-key"
    private static let service = "games.kim.kimi"

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func read() -> String {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    @discardableResult
    static func save(_ key: String) -> Bool {
        SecItemDelete(query as CFDictionary)
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        var q = query
        q[kSecValueData as String] = Data(trimmed.utf8)
        // readable after the first unlock so Siri can ask Kimi while the phone is locked; never synced off this device
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }
}

enum Settings {
    static var model: String {
        get { UserDefaults.standard.string(forKey: "model").flatMap { $0.isEmpty ? nil : $0 } ?? KimiCore.defaultModel }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "model") }
    }
}

/// One question to the model. Shared by the chat screen and Siri.
func askKimi(history: [ChatMessage], voice: Bool) async throws -> String {
    let request = try KimiCore.request(key: Keychain.read(), model: Settings.model, history: history, voice: voice)
    let (data, response) = try await URLSession.shared.data(for: request)
    let code = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard (200..<300).contains(code) else { throw KimiCore.Failure.service(code, KimiCore.errorText(data)) }
    return try KimiCore.parseReply(data)
}
