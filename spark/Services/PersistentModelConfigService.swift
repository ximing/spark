//
//  PersistentModelConfigService.swift
//  spark
//
//  Created by Claude on 2026/3/16.
//

import Foundation
import Combine
import Security

/// Real implementation of ModelConfigService with secure Keychain storage for API keys
class PersistentModelConfigService: ModelConfigService {

    // MARK: - Published State

    private let configurationsSubject = CurrentValueSubject<[ModelConfig], Never>([])

    var configurations: AnyPublisher<[ModelConfig], Never> {
        configurationsSubject.eraseToAnyPublisher()
    }

    private(set) var activeConfiguration: ModelConfig? {
        didSet {
            // Persist active configuration ID
            if let id = activeConfiguration?.id {
                UserDefaults.standard.set(id.uuidString, forKey: UserDefaultsKeys.activeConfigID)
            } else {
                UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.activeConfigID)
            }
        }
    }

    // MARK: - Constants

    private enum UserDefaultsKeys {
        static let modelConfigs = "spark.modelConfigs"
        static let activeConfigID = "spark.activeConfigID"
    }

    private enum KeychainKeys {
        static let service = "com.aimo.spark"
        static let accountPrefix = "model-apikey-"
    }

    // MARK: - Initialization

    init() {
        loadConfigurations()
    }

    // MARK: - Public Methods

    func saveConfiguration(_ config: ModelConfig, apiKey: String) throws {
        var configs = configurationsSubject.value

        // Check if updating existing config
        if let index = configs.firstIndex(where: { $0.id == config.id }) {
            configs[index] = config
        } else {
            configs.append(config)
        }

        // Save API key to Keychain
        try saveAPIKeyToKeychain(apiKey, for: config.id)

        // Save non-secret config metadata to UserDefaults
        try saveConfigsToUserDefaults(configs)

        // Update published state
        configurationsSubject.send(configs)

        // If this is the active config, update it
        if config.isActive {
            activeConfiguration = config
        }
    }

    func deleteConfiguration(id: UUID) throws {
        var configs = configurationsSubject.value

        // Remove from array
        configs.removeAll { $0.id == id }

        // Delete API key from Keychain
        deleteAPIKeyFromKeychain(for: id)

        // Save updated configs to UserDefaults
        try saveConfigsToUserDefaults(configs)

        // Update published state
        configurationsSubject.send(configs)

        // If deleted config was active, clear active config
        if activeConfiguration?.id == id {
            activeConfiguration = nil
        }
    }

    func setActiveConfiguration(id: UUID) throws {
        var configs = configurationsSubject.value

        // Find the config to activate
        guard configs.contains(where: { $0.id == id }) else {
            throw ModelConfigError.configNotFound
        }

        // Deactivate all configs and activate the selected one
        configs = configs.map { config in
            var updated = config
            updated.isActive = (config.id == id)
            return updated
        }

        // Save to UserDefaults
        try saveConfigsToUserDefaults(configs)

        // Update published state
        configurationsSubject.send(configs)

        // Update active config
        if let activeConfig = configs.first(where: { $0.id == id }) {
            activeConfiguration = activeConfig
        }
    }

    func getAPIKey(for id: UUID) -> String? {
        return loadAPIKeyFromKeychain(for: id)
    }

    // MARK: - Private Methods - Persistence

    private func loadConfigurations() {
        // Load configs from UserDefaults
        guard let data = UserDefaults.standard.data(forKey: UserDefaultsKeys.modelConfigs),
              let configs = try? JSONDecoder().decode([ModelConfig].self, from: data) else {
            configurationsSubject.send([])
            return
        }

        configurationsSubject.send(configs)

        // Restore active configuration
        if let activeIDString = UserDefaults.standard.string(forKey: UserDefaultsKeys.activeConfigID),
           let activeID = UUID(uuidString: activeIDString),
           let activeConfig = configs.first(where: { $0.id == activeID }) {
            activeConfiguration = activeConfig
        }
    }

    private func saveConfigsToUserDefaults(_ configs: [ModelConfig]) throws {
        let data = try JSONEncoder().encode(configs)
        UserDefaults.standard.set(data, forKey: UserDefaultsKeys.modelConfigs)
    }

    // MARK: - Private Methods - Keychain

    private func saveAPIKeyToKeychain(_ apiKey: String, for id: UUID) throws {
        let account = KeychainKeys.accountPrefix + id.uuidString

        // Delete existing key if present
        deleteAPIKeyFromKeychain(for: id)

        // Add new key
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainKeys.service,
            kSecAttrAccount as String: account,
            kSecValueData as String: apiKey.data(using: .utf8)!,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw ModelConfigError.keychainError(status)
        }
    }

    private func loadAPIKeyFromKeychain(for id: UUID) -> String? {
        let account = KeychainKeys.accountPrefix + id.uuidString

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainKeys.service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let apiKey = String(data: data, encoding: .utf8) else {
            return nil
        }

        return apiKey
    }

    private func deleteAPIKeyFromKeychain(for id: UUID) {
        let account = KeychainKeys.accountPrefix + id.uuidString

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainKeys.service,
            kSecAttrAccount as String: account
        ]

        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Errors

enum ModelConfigError: LocalizedError {
    case configNotFound
    case keychainError(OSStatus)

    var errorDescription: String? {
        switch self {
        case .configNotFound:
            return "Model configuration not found"
        case .keychainError(let status):
            return "Keychain error: \(status)"
        }
    }
}
