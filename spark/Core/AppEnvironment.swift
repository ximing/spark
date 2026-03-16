//
//  AppEnvironment.swift
//  spark
//
//  Created by Claude on 2026/3/16.
//

import Foundation

/// Lightweight dependency injection container for runtime service wiring
class AppEnvironment {
    let permissionService: PermissionService
    let translationService: TranslationService
    let modelConfigService: ModelConfigService
    let historyService: HistoryService
    let keyboardShortcutService: KeyboardShortcutService
    let inputFieldReaderService: InputFieldReaderService

    init(
        permissionService: PermissionService,
        translationService: TranslationService,
        modelConfigService: ModelConfigService,
        historyService: HistoryService,
        keyboardShortcutService: KeyboardShortcutService,
        inputFieldReaderService: InputFieldReaderService
    ) {
        self.permissionService = permissionService
        self.translationService = translationService
        self.modelConfigService = modelConfigService
        self.historyService = historyService
        self.keyboardShortcutService = keyboardShortcutService
        self.inputFieldReaderService = inputFieldReaderService
    }

    /// Creates a default production environment with real implementations
    static func production() -> AppEnvironment {
        // Real permission service implementation
        let permissionService = AccessibilityPermissionService()

        // Real translation service implementation
        let translationService = AITranslationService()

        // Real model config service implementation
        let modelConfigService = PersistentModelConfigService()

        // Real history service implementation
        let historyService = PersistentHistoryService()

        // Real keyboard shortcut service implementation
        let keyboardShortcutService = GlobalKeyboardShortcutService()

        // Real input field reader service implementation
        let inputFieldReaderService = AccessibilityInputFieldReaderService()

        return AppEnvironment(
            permissionService: permissionService,
            translationService: translationService,
            modelConfigService: modelConfigService,
            historyService: historyService,
            keyboardShortcutService: keyboardShortcutService,
            inputFieldReaderService: inputFieldReaderService
        )
    }
}

// MARK: - Mock Implementations (temporary)

import Combine

private class MockPermissionService: PermissionService {
    func checkPermissionState() -> PermissionState {
        .notDetermined
    }

    func openAccessibilitySettings() {}
}

private class MockModelConfigService: ModelConfigService {
    var configurations: AnyPublisher<[ModelConfig], Never> {
        Just([]).eraseToAnyPublisher()
    }

    var activeConfiguration: ModelConfig? { nil }

    func saveConfiguration(_ config: ModelConfig, apiKey: String) throws {}
    func deleteConfiguration(id: UUID) throws {}
    func setActiveConfiguration(id: UUID) throws {}
    func getAPIKey(for id: UUID) -> String? { nil }
}

private class MockHistoryService: HistoryService {
    var history: AnyPublisher<[HistoryItem], Never> {
        Just([]).eraseToAnyPublisher()
    }

    var isEnabled: Bool { false }

    func setEnabled(_ enabled: Bool) {}
    func saveToHistory(_ result: TranslationResult) {}
    func clearHistory() {}
}
