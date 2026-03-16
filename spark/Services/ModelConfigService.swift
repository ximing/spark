//
//  ModelConfigService.swift
//  spark
//
//  Created by Claude on 2026/3/16.
//

import Foundation
import Combine

/// Protocol for managing model configurations and API keys
protocol ModelConfigService {
    /// Publisher that emits the list of available model configurations
    var configurations: AnyPublisher<[ModelConfig], Never> { get }

    /// Returns the currently active model configuration, if any
    var activeConfiguration: ModelConfig? { get }

    /// Adds or updates a model configuration
    /// - Parameters:
    ///   - config: The model configuration
    ///   - apiKey: The API key (stored securely in Keychain)
    func saveConfiguration(_ config: ModelConfig, apiKey: String) throws

    /// Deletes a model configuration
    /// - Parameter id: The configuration ID to delete
    func deleteConfiguration(id: UUID) throws

    /// Sets a configuration as the active one
    /// - Parameter id: The configuration ID to activate
    func setActiveConfiguration(id: UUID) throws

    /// Retrieves the API key for a configuration from Keychain
    /// - Parameter id: The configuration ID
    /// - Returns: The API key, if found
    func getAPIKey(for id: UUID) -> String?
}
