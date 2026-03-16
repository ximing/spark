//
//  TranslationService.swift
//  spark
//
//  Created by Claude on 2026/3/16.
//

import Foundation

/// Service for translating Chinese text to English using AI models
protocol TranslationService {
    /// Translate Chinese text to English
    /// - Parameters:
    ///   - text: The Chinese text to translate
    ///   - config: Model configuration with API credentials
    ///   - apiKey: API key for authentication (from Keychain)
    /// - Returns: The English translation
    /// - Throws: Translation errors
    func translate(text: String, config: ModelConfig, apiKey: String) async throws -> String

    /// Test connection to the configured AI model
    /// - Parameters:
    ///   - config: Model configuration to test
    ///   - apiKey: API key for authentication (from Keychain)
    /// - Returns: Success or failure message
    func testConnection(config: ModelConfig, apiKey: String) async -> Result<String, Error>
}

/// Mock implementation for testing and development
class MockTranslationService: TranslationService {
    func translate(text: String, config: ModelConfig, apiKey: String) async throws -> String {
        // Simulate network delay
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5s
        return "Mock translation of: \(text)"
    }

    func testConnection(config: ModelConfig, apiKey: String) async -> Result<String, Error> {
        // Simulate network delay
        try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s
        return .success("Connection test successful (mock)")
    }
}
