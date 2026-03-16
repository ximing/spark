//
//  TranslationResult.swift
//  spark
//
//  Created by Claude on 2026/3/16.
//

import Foundation

/// Represents a single translation result from Chinese to English
struct TranslationResult: Identifiable, Codable {
    let id: UUID
    let originalText: String
    let translatedText: String
    let timestamp: Date
    let modelName: String

    init(
        id: UUID = UUID(),
        originalText: String,
        translatedText: String,
        timestamp: Date = Date(),
        modelName: String
    ) {
        self.id = id
        self.originalText = originalText
        self.translatedText = translatedText
        self.timestamp = timestamp
        self.modelName = modelName
    }
}
