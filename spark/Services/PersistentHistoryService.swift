//
//  PersistentHistoryService.swift
//  spark
//
//  Created by Claude on 2026/3/16.
//

import Foundation
import Combine
import os.log

/// Persistent implementation of HistoryService with local-only storage
class PersistentHistoryService: HistoryService {
    private let historySubject = CurrentValueSubject<[HistoryItem], Never>([])
    private let userDefaultsKey = "com.aimo.spark.translationHistory"
    private let isEnabledKey = "com.aimo.spark.historyEnabled"

    var history: AnyPublisher<[HistoryItem], Never> {
        historySubject.eraseToAnyPublisher()
    }

    var isEnabled: Bool {
        if UserDefaults.standard.object(forKey: isEnabledKey) == nil {
            // First launch - disable history by default per PRD FR-011
            UserDefaults.standard.set(false, forKey: isEnabledKey)
            return false
        }
        return UserDefaults.standard.bool(forKey: isEnabledKey)
    }

    init() {
        // Load existing history from UserDefaults
        loadHistory()
        Logger.history.info("History service initialized, isEnabled: \(self.isEnabled, privacy: .public)")
    }

    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: isEnabledKey)
        Logger.history.info("History recording \(enabled ? "enabled" : "disabled")")

        // If disabling, optionally clear existing history
        // For now, we keep existing history when disabling
    }

    func saveToHistory(_ result: TranslationResult) {
        // Only save if history is enabled
        guard isEnabled else {
            Logger.history.debug("History recording disabled, not saving translation")
            return
        }

        let historyItem = HistoryItem(from: result)
        var currentHistory = historySubject.value

        // Add new item at the beginning (most recent first)
        currentHistory.insert(historyItem, at: 0)

        // Persist to UserDefaults
        persistHistory(currentHistory)

        // Emit updated history
        historySubject.send(currentHistory)

        Logger.history.debug("Saved to history: \(result.originalText.prefix(30), privacy: .private)... -> \(result.translatedText.prefix(30), privacy: .public)...")
    }

    func clearHistory() {
        // Clear in-memory history
        historySubject.send([])

        // Clear persisted history
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)

        Logger.history.info("History cleared")
    }

    // MARK: - Private Methods

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
            Logger.history.debug("No existing history found")
            return
        }

        do {
            let decoder = JSONDecoder()
            let items = try decoder.decode([HistoryItem].self, from: data)
            historySubject.send(items)
            Logger.history.info("Loaded \(items.count, privacy: .public) history items from storage")
        } catch {
            Logger.history.error("Failed to load history: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func persistHistory(_ items: [HistoryItem]) {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(items)
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        } catch {
            Logger.history.error("Failed to persist history: \(error.localizedDescription, privacy: .public)")
        }
    }
}
