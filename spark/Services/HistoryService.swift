//
//  HistoryService.swift
//  spark
//
//  Created by Claude on 2026/3/16.
//

import Foundation
import Combine

/// Protocol for managing translation history
protocol HistoryService {
    /// Publisher that emits the current history items
    var history: AnyPublisher<[HistoryItem], Never> { get }

    /// Returns whether history recording is enabled
    var isEnabled: Bool { get }

    /// Enables or disables history recording
    /// - Parameter enabled: Whether to enable history
    func setEnabled(_ enabled: Bool)

    /// Saves a translation result to history (only if enabled)
    /// - Parameter result: The translation result to save
    func saveToHistory(_ result: TranslationResult)

    /// Clears all history items
    func clearHistory()
}
