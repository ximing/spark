//
//  PersistentHistoryService.swift
//  spark
//
//  Created by Claude on 2026/3/16.
//

import Foundation
import Combine

/// Persistent implementation of HistoryService with local-only storage
class PersistentHistoryService: HistoryService {
    private let historySubject = CurrentValueSubject<[HistoryItem], Never>([])
    private let userDefaultsKey = "com.aimo.spark.translationHistory"
    private let isEnabledKey = "com.aimo.spark.historyEnabled"

    var history: AnyPublisher<[HistoryItem], Never> {
        historySubject.eraseToAnyPublisher()
    }

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: isEnabledKey)
    }

    init() {
        // Load existing history from UserDefaults
        loadHistory()
    }

    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: isEnabledKey)
        print("📚 History recording \(enabled ? "enabled" : "disabled")")

        // If disabling, optionally clear existing history
        // For now, we keep existing history when disabling
    }

    func saveToHistory(_ result: TranslationResult) {
        // Only save if history is enabled
        guard isEnabled else {
            print("📚 History recording disabled, not saving translation")
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

        print("📚 Saved to history: \(result.originalText.prefix(30))... -> \(result.translatedText.prefix(30))...")
    }

    func clearHistory() {
        // Clear in-memory history
        historySubject.send([])

        // Clear persisted history
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)

        print("📚 History cleared")
    }

    // MARK: - Private Methods

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
            print("📚 No existing history found")
            return
        }

        do {
            let decoder = JSONDecoder()
            let items = try decoder.decode([HistoryItem].self, from: data)
            historySubject.send(items)
            print("📚 Loaded \(items.count) history items from storage")
        } catch {
            print("📚 Failed to load history: \(error.localizedDescription)")
        }
    }

    private func persistHistory(_ items: [HistoryItem]) {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(items)
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        } catch {
            print("📚 Failed to persist history: \(error.localizedDescription)")
        }
    }
}
