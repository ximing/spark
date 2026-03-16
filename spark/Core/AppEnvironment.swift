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
    let inputMonitoringService: InputMonitoringService
    let translationService: TranslationService
    let modelConfigService: ModelConfigService
    let historyService: HistoryService

    init(
        permissionService: PermissionService,
        inputMonitoringService: InputMonitoringService,
        translationService: TranslationService,
        modelConfigService: ModelConfigService,
        historyService: HistoryService
    ) {
        self.permissionService = permissionService
        self.inputMonitoringService = inputMonitoringService
        self.translationService = translationService
        self.modelConfigService = modelConfigService
        self.historyService = historyService
    }

    /// Creates a default production environment with real implementations
    static func production() -> AppEnvironment {
        // Real permission service implementation
        let permissionService = AccessibilityPermissionService()

        // TODO: Replace with real implementation once keyboard shortcut trigger is wired up
        // Using mock for now since GlobalInputMonitoringService was removed
        let inputMonitoringService = MockInputMonitoringService()

        // Real translation service implementation
        let translationService = AITranslationService()

        // Real model config service implementation
        let modelConfigService = PersistentModelConfigService()

        // Real history service implementation
        let historyService = PersistentHistoryService()

        return AppEnvironment(
            permissionService: permissionService,
            inputMonitoringService: inputMonitoringService,
            translationService: translationService,
            modelConfigService: modelConfigService,
            historyService: historyService
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

class MockInputMonitoringService: InputMonitoringService {
    var inputEvents: AnyPublisher<String, Never> {
        Empty().eraseToAnyPublisher()
    }

    var isMonitoring: Bool { false }

    func startMonitoring() {}
    func stopMonitoring() {}
    func setDebounceTimeout(_ timeout: TimeInterval) {}
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
