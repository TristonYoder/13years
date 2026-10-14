// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import Foundation
import Security

enum KeychainStore {
    private static let service = "dev.7co.13years"

    static func setString(_ value: String?, forKey key: String) {
        guard let value, !value.isEmpty else {
            delete(forKey: key)
            return
        }
        set(Data(value.utf8), forKey: key)
    }

    static func string(forKey key: String) -> String? {
        guard let data = data(forKey: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func setCodable<T: Encodable>(_ value: T?, forKey key: String) {
        guard let value, let data = try? JSONEncoder().encode(value) else {
            delete(forKey: key)
            return
        }
        set(data, forKey: key)
    }

    static func codable<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func set(_ data: Data, forKey key: String) {
        let query = baseQuery(forKey: key)
        let attributesToUpdate: [String: Any] = [kSecValueData as String: data]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    private static func data(forKey key: String) -> Data? {
        var query = baseQuery(forKey: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    private static func delete(forKey key: String) {
        SecItemDelete(baseQuery(forKey: key) as CFDictionary)
    }

    private static func baseQuery(forKey key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }
}
