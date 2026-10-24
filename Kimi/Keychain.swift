import Foundation
import Security

/// The AI Gateway key lives in the iPhone Keychain, never in plain settings.
enum Keychain {
    static let gateway = "ai-gateway-key"
    static let office = "office-key"   // key of the owner's AI office entry (kimi_api.py)
    static let speechkit = "speechkit-key"   // Yandex SpeechKit API key for the personal voices
    static let account = "kimy-account"      // kt_… token of the Kimy service account (brain and office on the server)
    private static let service = "games.kim.kimi"

    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func read(_ account: String = gateway) -> String {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    @discardableResult
    static func save(_ key: String, as account: String = gateway) -> Bool {
        SecItemDelete(query(account) as CFDictionary)
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        var q = query(account)
        q[kSecValueData as String] = Data(trimmed.utf8)
        // readable after the first unlock so Siri can ask Kimi while the phone is locked; never synced off this device
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }
}

enum Settings {
    /// How Kimy greets the owner on the home screen.
    static var name: String {
        get { UserDefaults.standard.string(forKey: "name") ?? "" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "name") }
    }
    static var model: String {
        get { UserDefaults.standard.string(forKey: "model").flatMap { $0.isEmpty ? nil : $0 } ?? KimiCore.defaultModel }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "model") }
    }
}

/// One question to the model. Shared by the chat screen and Siri.
func askKimi(history: [ChatMessage], voice: Bool, context: String = "") async throws -> String {
    // an own AI Gateway key goes straight to the gateway; everyone else thinks with the brain on the Kimy server
    let own = Keychain.read()
    let request = own.isEmpty
        ? try KimiCore.request(key: Keychain.read(Keychain.account), model: Settings.model, history: history, voice: voice, context: context, endpoint: Account.chat)
        : try KimiCore.request(key: own, model: Settings.model, history: history, voice: voice, context: context)
    let (data, response) = try await URLSession.shared.data(for: request)
    let code = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard (200..<300).contains(code) else { throw KimiCore.Failure.service(code, KimiCore.errorText(data)) }
    return try KimiCore.parseReply(data)
}

/// One office call: the key from the Keychain, the server's error text shown as is.
func callOffice(_ make: (String) throws -> URLRequest) async throws -> [String: Any] {
    let owner = Keychain.read(Keychain.office)
    Office.tenant = owner.isEmpty
    let (data, response) = try await URLSession.shared.data(for: try make(owner.isEmpty ? Keychain.read(Keychain.account) : owner))
    return try Office.check(data, (response as? HTTPURLResponse)?.statusCode ?? 0)
}

/// One call to the Kimy account (signup, status, office setup).
func callAccount(_ path: String, body: [String: Any]? = nil) async throws -> [String: Any] {
    let (data, response) = try await URLSession.shared.data(for: try Account.request(path, token: Keychain.read(Keychain.account), body: body))
    return try Office.check(data, (response as? HTTPURLResponse)?.statusCode ?? 0)
}

/// Owner of the server (office key) or a user with an own key never sees the welcome screen.
var isNewUser: Bool { Keychain.read().isEmpty && Keychain.read(Keychain.account).isEmpty && Keychain.read(Keychain.office).isEmpty }
