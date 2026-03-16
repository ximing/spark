//
//  HistoryItem.swift
//  spark
//
//  Created by Claude on 2026/3/16.
//

import Foundation

/// Represents a stored translation history item (when history is enabled)
struct HistoryItem: Identifiable, Codable {
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

    /// Creates a history item from a translation result
    init(from result: TranslationResult) {
        self.id = result.id
        self.originalText = result.originalText
        self.translatedText = result.translatedText
        self.timestamp = result.timestamp
        self.modelName = result.modelName
    }
}
