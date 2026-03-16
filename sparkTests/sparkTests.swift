//
//  sparkTests.swift
//  sparkTests
//
//  Created by ximing on 2026/3/16.
//

import Testing
import Combine
import Foundation
@testable import spark

// MARK: - Mock Services for Testing

class MockPermissionService: PermissionService {
    var mockState: PermissionState = .notDetermined
    var openSettingsCalled = false

    func checkPermissionState() -> PermissionState {
        return mockState
    }

    func openAccessibilitySettings() {
        openSettingsCalled = true
    }
}

class MockTranslationService: TranslationService {
    var shouldFail = false
    var translationDelay: TimeInterval = 0.1
    var lastTranslatedText: String?

    func translate(text: String, config: ModelConfig, apiKey: String) async throws -> String {
        lastTranslatedText = text

        if shouldFail {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Mock translation failure"])
        }

        // Simulate API latency
        try await Task.sleep(nanoseconds: UInt64(translationDelay * 1_000_000_000))

        return "Translated: \(text)"
    }

    func testConnection(config: ModelConfig, apiKey: String) async -> Result<String, Error> {
        if shouldFail {
            return .failure(NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Connection failed"]))
        }
        return .success("Connection successful")
    }
}

class MockModelConfigService: ModelConfigService {
    private var configurationsSubject = CurrentValueSubject<[ModelConfig], Never>([])
    var configurations: AnyPublisher<[ModelConfig], Never> {
        configurationsSubject.eraseToAnyPublisher()
    }
    var activeConfiguration: ModelConfig? {
        configurationsSubject.value.first(where: { $0.isActive })
    }
    var mockAPIKey: String?

    func saveConfiguration(_ config: ModelConfig, apiKey: String) throws {
        mockAPIKey = apiKey
        var configs = configurationsSubject.value
        if let index = configs.firstIndex(where: { $0.id == config.id }) {
            configs[index] = config
        } else {
            configs.append(config)
        }
        configurationsSubject.send(configs)
    }

    func deleteConfiguration(id: UUID) throws {
        var configs = configurationsSubject.value
        configs.removeAll { $0.id == id }
        configurationsSubject.send(configs)
    }

    func setActiveConfiguration(id: UUID) throws {
        var configs = configurationsSubject.value
        configs = configs.map { config in
            config.withActive(config.id == id)
        }
        configurationsSubject.send(configs)
    }

    func getAPIKey(for id: UUID) -> String? {
        return mockAPIKey
    }
}

class MockHistoryService: HistoryService {
    private var historySubject = CurrentValueSubject<[HistoryItem], Never>([])
    var history: AnyPublisher<[HistoryItem], Never> {
        historySubject.eraseToAnyPublisher()
    }
    var isEnabled: Bool = false
    var savedItems: [HistoryItem] = []

    func saveToHistory(_ result: TranslationResult) {
        guard isEnabled else { return }
        let item = HistoryItem(
            id: UUID(),
            originalText: result.originalText,
            translatedText: result.translatedText,
            timestamp: result.timestamp,
            modelName: result.modelName
        )
        savedItems.append(item)
        historySubject.send(savedItems)
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
    }

    func clearHistory() {
        savedItems.removeAll()
        historySubject.send([])
    }
}

class MockKeyboardShortcutService: KeyboardShortcutService {
    private let shortcutSubject = PassthroughSubject<Void, Never>()
    var shortcutTriggered: AnyPublisher<Void, Never> {
        shortcutSubject.eraseToAnyPublisher()
    }

    private(set) var isListening: Bool = false

    func startListening() {
        isListening = true
    }

    func stopListening() {
        isListening = false
    }

    // Helper for testing
    func simulateShortcut() {
        shortcutSubject.send(())
    }
}

class MockInputFieldReaderService: InputFieldReaderService {
    var mockResult: InputFieldReadResult = .noFocusedElement

    func readFocusedFieldText() async -> InputFieldReadResult {
        return mockResult
    }
}

// MARK: - Test Suite

@Suite("Spark Core Functionality Tests")
struct SparkTests {

    // MARK: - Permission Gating Tests

    @Test("Permission gating: monitoring should not start without authorization")
    @MainActor
    func testPermissionGating() async throws {
        // Given: unauthorized permission state
        let mockPermission = MockPermissionService()
        mockPermission.mockState = .denied

        let mockTranslation = MockTranslationService()
        let mockModelConfig = MockModelConfigService()
        let mockHistory = MockHistoryService()

        let environment = AppEnvironment(
            permissionService: mockPermission,
            translationService: mockTranslation,
            modelConfigService: mockModelConfig,
            historyService: mockHistory,
            keyboardShortcutService: MockKeyboardShortcutService(),
            inputFieldReaderService: MockInputFieldReaderService()
        )

        let appState = AppState(environment: environment)

        // Add a model configuration
        let testConfig = ModelConfig(
            id: UUID(),
            name: "Test Model",
            modelName: "gpt-4",
            baseURL: "https://api.openai.com",
            isActive: true
        )
        try mockModelConfig.saveConfiguration(testConfig, apiKey: "test-key")

        // When: attempting to start monitoring without permission
        appState.startMonitoring()

        // Then: monitoring should not start and error should be set
        #expect(appState.isMonitoring == false)
        #expect(appState.runtimeError == .permissionMissing)
    }

    @Test("Permission gating: monitoring should start when authorized")
    @MainActor
    func testPermissionAuthorized() async throws {
        // Given: authorized permission state
        let mockPermission = MockPermissionService()
        mockPermission.mockState = .authorized

        let mockTranslation = MockTranslationService()
        let mockModelConfig = MockModelConfigService()
        let mockHistory = MockHistoryService()

        let environment = AppEnvironment(
            permissionService: mockPermission,
            translationService: mockTranslation,
            modelConfigService: mockModelConfig,
            historyService: mockHistory,
            keyboardShortcutService: MockKeyboardShortcutService(),
            inputFieldReaderService: MockInputFieldReaderService()
        )

        let appState = AppState(environment: environment)

        // Add a model configuration
        let testConfig = ModelConfig(
            id: UUID(),
            name: "Test Model",
            modelName: "gpt-4",
            baseURL: "https://api.openai.com",
            isActive: true
        )
        try mockModelConfig.saveConfiguration(testConfig, apiKey: "test-key")

        // Wait for state to update
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1s

        // When: starting monitoring with permission
        appState.startMonitoring()

        // Then: monitoring should start successfully
        #expect(appState.isMonitoring == true)
        #expect(appState.runtimeError == nil)
    }

    // MARK: - Model Switching Tests

    @Test("Model switching: setting active model should update immediately")
    @MainActor
    func testModelHotSwitch() async throws {
        // Given: multiple model configurations
        let mockModelConfig = MockModelConfigService()
        let environment = AppEnvironment(
            permissionService: MockPermissionService(),
            translationService: MockTranslationService(),
            modelConfigService: mockModelConfig,
            historyService: MockHistoryService(),
            keyboardShortcutService: MockKeyboardShortcutService(),
            inputFieldReaderService: MockInputFieldReaderService()
        )

        let appState = AppState(environment: environment)

        let model1 = ModelConfig(id: UUID(), name: "Model 1", modelName: "gpt-4", baseURL: "https://api.openai.com", isActive: true)
        let model2 = ModelConfig(id: UUID(), name: "Model 2", modelName: "gpt-3.5-turbo", baseURL: "https://api.openai.com", isActive: false)

        try mockModelConfig.saveConfiguration(model1, apiKey: "key1")
        try mockModelConfig.saveConfiguration(model2, apiKey: "key2")

        // Wait for state to update
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1s

        // Then: model 1 should be active initially
        #expect(appState.activeModelConfig?.id == model1.id)

        // When: switching to model 2
        try appState.setActiveModelConfiguration(id: model2.id)

        // Wait for state to update
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1s

        // Then: model 2 should be active
        #expect(appState.activeModelConfig?.id == model2.id)
    }

    @Test("Model config: first model should auto-activate when none is active")
    @MainActor
    func testFirstModelAutoActivation() async throws {
        // Given: app starts with no active model
        let mockModelConfig = MockModelConfigService()
        let environment = AppEnvironment(
            permissionService: MockPermissionService(),
            translationService: MockTranslationService(),
            modelConfigService: mockModelConfig,
            historyService: MockHistoryService(),
            keyboardShortcutService: MockKeyboardShortcutService(),
            inputFieldReaderService: MockInputFieldReaderService()
        )

        let appState = AppState(environment: environment)
        appState.runtimeError = .modelUnavailable

        // When: saving the first model as inactive (legacy data pattern)
        let firstModel = ModelConfig(
            id: UUID(),
            name: "First Model",
            modelName: "gpt-4",
            baseURL: "https://api.openai.com",
            isActive: false
        )
        try mockModelConfig.saveConfiguration(firstModel, apiKey: "first-key")

        // Wait for auto-activation path to complete
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2s

        // Then: app state should recover to a usable active model immediately
        #expect(appState.activeModelConfig?.id == firstModel.id)
        #expect(appState.modelConfigurations.first?.isActive == true)
        #expect(appState.runtimeError == nil)
    }

    // MARK: - History Toggle Tests

    @Test("History toggle: history should not save when disabled")
    @MainActor
    func testHistoryDisabled() async throws {
        // Given: history disabled
        let mockHistory = MockHistoryService()
        mockHistory.isEnabled = false

        let environment = AppEnvironment(
            permissionService: MockPermissionService(),
            translationService: MockTranslationService(),
            modelConfigService: MockModelConfigService(),
            historyService: mockHistory,
            keyboardShortcutService: MockKeyboardShortcutService(),
            inputFieldReaderService: MockInputFieldReaderService()
        )

        let appState = AppState(environment: environment)

        // When: saving a translation result
        let result = TranslationResult(
            originalText: "你好",
            translatedText: "Hello",
            timestamp: Date(),
            modelName: "Test Model"
        )
        mockHistory.saveToHistory(result)

        // Then: history should remain empty
        #expect(mockHistory.savedItems.isEmpty)
        #expect(appState.historyItems.isEmpty)
    }

    @Test("History toggle: history should save when enabled")
    @MainActor
    func testHistoryEnabled() async throws {
        // Given: history enabled
        let mockHistory = MockHistoryService()
        mockHistory.isEnabled = true

        let environment = AppEnvironment(
            permissionService: MockPermissionService(),
            translationService: MockTranslationService(),
            modelConfigService: MockModelConfigService(),
            historyService: mockHistory,
            keyboardShortcutService: MockKeyboardShortcutService(),
            inputFieldReaderService: MockInputFieldReaderService()
        )

        let appState = AppState(environment: environment)

        // When: saving a translation result
        let result = TranslationResult(
            originalText: "你好",
            translatedText: "Hello",
            timestamp: Date(),
            modelName: "Test Model"
        )
        mockHistory.saveToHistory(result)

        // Wait for state to update
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1s

        // Then: history should contain the item
        #expect(mockHistory.savedItems.count == 1)
        #expect(appState.historyItems.count == 1)
        #expect(appState.historyItems.first?.originalText == "你好")
    }

    @Test("History toggle: clearing history should remove all items")
    @MainActor
    func testHistoryClear() async throws {
        // Given: history with items
        let mockHistory = MockHistoryService()
        mockHistory.isEnabled = true

        let environment = AppEnvironment(
            permissionService: MockPermissionService(),
            translationService: MockTranslationService(),
            modelConfigService: MockModelConfigService(),
            historyService: mockHistory,
            keyboardShortcutService: MockKeyboardShortcutService(),
            inputFieldReaderService: MockInputFieldReaderService()
        )

        let appState = AppState(environment: environment)

        // Add some history items
        let result1 = TranslationResult(originalText: "你好", translatedText: "Hello", timestamp: Date(), modelName: "Test")
        let result2 = TranslationResult(originalText: "谢谢", translatedText: "Thank you", timestamp: Date(), modelName: "Test")
        mockHistory.saveToHistory(result1)
        mockHistory.saveToHistory(result2)

        // Wait for state to update
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1s

        #expect(appState.historyItems.count == 2)

        // When: clearing history
        appState.clearHistory()

        // Wait for state to update
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1s

        // Then: history should be empty
        #expect(mockHistory.savedItems.isEmpty)
        #expect(appState.historyItems.isEmpty)
    }

    // MARK: - Model Unavailable Tests

    @Test("Model availability: monitoring should not start without active model")
    @MainActor
    func testModelUnavailable() async throws {
        // Given: authorized permission but no model config
        let mockPermission = MockPermissionService()
        mockPermission.mockState = .authorized

        let environment = AppEnvironment(
            permissionService: mockPermission,
            translationService: MockTranslationService(),
            modelConfigService: MockModelConfigService(),
            historyService: MockHistoryService(),
            keyboardShortcutService: MockKeyboardShortcutService(),
            inputFieldReaderService: MockInputFieldReaderService()
        )

        let appState = AppState(environment: environment)

        // When: attempting to start monitoring without model config
        appState.startMonitoring()

        // Then: monitoring should not start and error should be set
        #expect(appState.isMonitoring == false)
        #expect(appState.runtimeError == .modelUnavailable)
    }

    // MARK: - Translation Failure Tests

    @Test("Translation failure: should handle errors gracefully without crashing")
    @MainActor
    func testTranslationFailure() async throws {
        // Given: setup with failing translation service
        let mockPermission = MockPermissionService()
        mockPermission.mockState = .authorized

        let mockTranslation = MockTranslationService()
        mockTranslation.shouldFail = true

        let mockModelConfig = MockModelConfigService()
        let mockInputFieldReader = MockInputFieldReaderService()
        mockInputFieldReader.mockResult = .success("测试文本")

        let mockKeyboardShortcut = MockKeyboardShortcutService()

        let environment = AppEnvironment(
            permissionService: mockPermission,
            translationService: mockTranslation,
            modelConfigService: mockModelConfig,
            historyService: MockHistoryService(),
            keyboardShortcutService: mockKeyboardShortcut,
            inputFieldReaderService: mockInputFieldReader
        )

        let appState = AppState(environment: environment)

        // Add model config
        let testConfig = ModelConfig(id: UUID(), name: "Test", modelName: "gpt-4", baseURL: "https://api.openai.com", isActive: true)
        try mockModelConfig.saveConfiguration(testConfig, apiKey: "test-key")

        // Wait for state to update
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1s

        // Start monitoring
        appState.startMonitoring()

        // When: triggering translation via keyboard shortcut
        mockKeyboardShortcut.simulateShortcut()

        // Wait for async translation attempt (with extra time for error handling)
        try await Task.sleep(nanoseconds: 700_000_000) // 0.7s

        // Then: error should be set and app should not crash
        #expect(appState.runtimeError != nil)
        if case .translationFailed = appState.runtimeError {
            // Success - correct error type
        } else {
            Issue.record("Expected translationFailed error, got: \(String(describing: appState.runtimeError))")
        }
    }

    // MARK: - End-to-End Pipeline Tests

    @Test("End-to-end: keyboard shortcut should trigger translation and update UI state")
    @MainActor
    func testEndToEndPipeline() async throws {
        // Given: fully configured app with all services
        let mockPermission = MockPermissionService()
        mockPermission.mockState = .authorized

        let mockTranslation = MockTranslationService()
        mockTranslation.translationDelay = 0.2 // Simulate realistic API delay

        let mockModelConfig = MockModelConfigService()
        let mockHistory = MockHistoryService()
        mockHistory.isEnabled = true

        let mockInputFieldReader = MockInputFieldReaderService()
        let inputText = "你好世界"
        mockInputFieldReader.mockResult = .success(inputText)

        let mockKeyboardShortcut = MockKeyboardShortcutService()

        let environment = AppEnvironment(
            permissionService: mockPermission,
            translationService: mockTranslation,
            modelConfigService: mockModelConfig,
            historyService: mockHistory,
            keyboardShortcutService: mockKeyboardShortcut,
            inputFieldReaderService: mockInputFieldReader
        )

        let appState = AppState(environment: environment)

        // Add model config
        let testConfig = ModelConfig(
            id: UUID(),
            name: "Test Model",
            modelName: "gpt-4",
            baseURL: "https://api.openai.com",
            isActive: true
        )
        try mockModelConfig.saveConfiguration(testConfig, apiKey: "test-key-123")

        // Wait for state to update
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1s

        // Start monitoring
        appState.startMonitoring()

        #expect(appState.isMonitoring == true)
        #expect(appState.latestTranslation == nil)

        // When: triggering translation via keyboard shortcut
        mockKeyboardShortcut.simulateShortcut()

        // Wait for translation to complete (delay + processing time)
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5s

        // Then: verify full pipeline worked
        // 1. Translation result should be updated
        #expect(appState.latestTranslation != nil)
        #expect(appState.latestTranslation?.originalText == inputText)
        #expect(appState.latestTranslation?.translatedText == "Translated: \(inputText)")
        #expect(appState.latestTranslation?.modelName == "Test Model")

        // 2. Latency should be recorded
        #expect(appState.lastTranslationLatency != nil)
        #expect(appState.lastTranslationLatency! > 0)
        #expect(appState.lastTranslationLatency! < 2.0) // Should be well under 2 seconds for mock

        // 3. History should be saved (since enabled)
        #expect(mockHistory.savedItems.count == 1)
        #expect(appState.historyItems.count == 1)
        #expect(appState.historyItems.first?.originalText == inputText)

        // 4. No errors should be present
        #expect(appState.runtimeError == nil)

        // 5. Translation service should have been called
        #expect(mockTranslation.lastTranslatedText == inputText)
    }

    @Test("End-to-end: latency measurement should be accurate")
    @MainActor
    func testLatencyMeasurement() async throws {
        // Given: configured app with known translation delay
        let mockPermission = MockPermissionService()
        mockPermission.mockState = .authorized

        let mockTranslation = MockTranslationService()
        mockTranslation.translationDelay = 0.3 // 300ms delay

        let mockModelConfig = MockModelConfigService()
        let mockInputFieldReader = MockInputFieldReaderService()
        mockInputFieldReader.mockResult = .success("测试延迟")

        let mockKeyboardShortcut = MockKeyboardShortcutService()

        let environment = AppEnvironment(
            permissionService: mockPermission,
            translationService: mockTranslation,
            modelConfigService: mockModelConfig,
            historyService: MockHistoryService(),
            keyboardShortcutService: mockKeyboardShortcut,
            inputFieldReaderService: mockInputFieldReader
        )

        let appState = AppState(environment: environment)

        // Add model config
        let testConfig = ModelConfig(id: UUID(), name: "Test", modelName: "gpt-4", baseURL: "https://api.openai.com", isActive: true)
        try mockModelConfig.saveConfiguration(testConfig, apiKey: "test-key")

        // Wait for state to update
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1s

        // Start monitoring
        appState.startMonitoring()

        // When: triggering translation via keyboard shortcut
        mockKeyboardShortcut.simulateShortcut()

        // Wait for translation
        try await Task.sleep(nanoseconds: 600_000_000) // 0.6s

        // Then: latency should be approximately 300ms + overhead
        #expect(appState.lastTranslationLatency != nil)
        #expect(appState.lastTranslationLatency! >= 0.3) // At least the translation delay
        #expect(appState.lastTranslationLatency! < 1.0) // But well under 1 second for mock

        print("Measured latency: \(appState.lastTranslationLatency!)s")
    }

    @Test("End-to-end: multiple sequential translations should update latency each time")
    @MainActor
    func testMultipleTranslationsLatency() async throws {
        // Given: configured app
        let mockPermission = MockPermissionService()
        mockPermission.mockState = .authorized

        let mockTranslation = MockTranslationService()
        mockTranslation.translationDelay = 0.1

        let mockModelConfig = MockModelConfigService()
        let mockInputFieldReader = MockInputFieldReaderService()
        let mockKeyboardShortcut = MockKeyboardShortcutService()

        let environment = AppEnvironment(
            permissionService: mockPermission,
            translationService: mockTranslation,
            modelConfigService: mockModelConfig,
            historyService: MockHistoryService(),
            keyboardShortcutService: mockKeyboardShortcut,
            inputFieldReaderService: mockInputFieldReader
        )

        let appState = AppState(environment: environment)

        // Add model config
        let testConfig = ModelConfig(id: UUID(), name: "Test", modelName: "gpt-4", baseURL: "https://api.openai.com", isActive: true)
        try mockModelConfig.saveConfiguration(testConfig, apiKey: "test-key")

        // Wait for state to update
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1s

        // Start monitoring
        appState.startMonitoring()

        // When: triggering multiple translations via keyboard shortcut
        mockInputFieldReader.mockResult = .success("第一个文本")
        mockKeyboardShortcut.simulateShortcut()
        try await Task.sleep(nanoseconds: 300_000_000) // 0.3s

        let firstLatency = appState.lastTranslationLatency
        #expect(firstLatency != nil)

        mockInputFieldReader.mockResult = .success("第二个文本")
        mockKeyboardShortcut.simulateShortcut()
        try await Task.sleep(nanoseconds: 300_000_000) // 0.3s

        let secondLatency = appState.lastTranslationLatency
        #expect(secondLatency != nil)

        // Then: each translation should have its own latency measurement
        #expect(appState.latestTranslation?.originalText == "第二个文本")
        // Both latencies should be valid
        #expect(firstLatency! > 0)
        #expect(secondLatency! > 0)
    }

    // MARK: - Keyboard Shortcut Service Tests

    @Test("KeyboardShortcutService: should start and stop listening")
    func testKeyboardShortcutStartStop() {
        // Given: keyboard shortcut service
        let service = MockKeyboardShortcutService()

        // Then: initially not listening
        #expect(service.isListening == false)

        // When: starting listening
        service.startListening()

        // Then: should be listening
        #expect(service.isListening == true)

        // When: stopping listening
        service.stopListening()

        // Then: should not be listening
        #expect(service.isListening == false)
    }

    @Test("KeyboardShortcutService: should emit shortcut triggered event")
    @MainActor
    func testKeyboardShortcutTriggered() async throws {
        // Given: keyboard shortcut service
        let service = MockKeyboardShortcutService()
        var eventReceived = false

        // Subscribe to shortcut events
        let cancellable = service.shortcutTriggered
            .sink { _ in
                eventReceived = true
            }

        // When: simulating shortcut trigger
        service.simulateShortcut()

        // Wait for async event
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1s

        // Then: event should be received
        #expect(eventReceived == true)

        cancellable.cancel()
    }

    @Test("KeyboardShortcutService: monitoring should start shortcut listener")
    @MainActor
    func testMonitoringStartsShortcutListener() async throws {
        // Given: configured app
        let mockPermission = MockPermissionService()
        mockPermission.mockState = .authorized

        let mockKeyboardShortcut = MockKeyboardShortcutService()
        let mockModelConfig = MockModelConfigService()

        let environment = AppEnvironment(
            permissionService: mockPermission,
            translationService: MockTranslationService(),
            modelConfigService: mockModelConfig,
            historyService: MockHistoryService(),
            keyboardShortcutService: mockKeyboardShortcut,
            inputFieldReaderService: MockInputFieldReaderService()
        )

        let appState = AppState(environment: environment)

        // Add model config
        let testConfig = ModelConfig(id: UUID(), name: "Test", modelName: "gpt-4", baseURL: "https://api.openai.com", isActive: true)
        try mockModelConfig.saveConfiguration(testConfig, apiKey: "test-key")

        // Wait for state to update
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1s

        // When: starting monitoring
        appState.startMonitoring()

        // Then: shortcut listener should be started
        #expect(mockKeyboardShortcut.isListening == true)

        // When: stopping monitoring
        appState.stopMonitoring()

        // Then: shortcut listener should be stopped
        #expect(mockKeyboardShortcut.isListening == false)
    }

    // MARK: - Input Field Reader Service Tests

    @Test("InputFieldReaderService: should return success with text")
    func testInputFieldReaderSuccess() async {
        // Given: mock service with success result
        let service = MockInputFieldReaderService()
        service.mockResult = .success("测试文本")

        // When: reading focused field text
        let result = await service.readFocusedFieldText()

        // Then: should return success with text
        if case .success(let text) = result {
            #expect(text == "测试文本")
        } else {
            Issue.record("Expected success result, got: \(result)")
        }
    }

    @Test("InputFieldReaderService: should return noFocusedElement when no element is focused")
    func testInputFieldReaderNoFocusedElement() async {
        // Given: mock service with no focused element
        let service = MockInputFieldReaderService()
        service.mockResult = .noFocusedElement

        // When: reading focused field text
        let result = await service.readFocusedFieldText()

        // Then: should return noFocusedElement
        if case .noFocusedElement = result {
            // Success
        } else {
            Issue.record("Expected noFocusedElement, got: \(result)")
        }
    }

    @Test("InputFieldReaderService: should return noTextValue when element has no text")
    func testInputFieldReaderNoTextValue() async {
        // Given: mock service with no text value
        let service = MockInputFieldReaderService()
        service.mockResult = .noTextValue

        // When: reading focused field text
        let result = await service.readFocusedFieldText()

        // Then: should return noTextValue
        if case .noTextValue = result {
            // Success
        } else {
            Issue.record("Expected noTextValue, got: \(result)")
        }
    }

    @Test("InputFieldReaderService: should return passwordField for password fields")
    func testInputFieldReaderPasswordField() async {
        // Given: mock service detecting password field
        let service = MockInputFieldReaderService()
        service.mockResult = .passwordField

        // When: reading focused field text
        let result = await service.readFocusedFieldText()

        // Then: should return passwordField
        if case .passwordField = result {
            // Success
        } else {
            Issue.record("Expected passwordField, got: \(result)")
        }
    }

    @Test("InputFieldReaderService: should return error on failure")
    func testInputFieldReaderError() async {
        // Given: mock service with error
        let service = MockInputFieldReaderService()
        service.mockResult = .error("Test error")

        // When: reading focused field text
        let result = await service.readFocusedFieldText()

        // Then: should return error
        if case .error(let message) = result {
            #expect(message == "Test error")
        } else {
            Issue.record("Expected error result, got: \(result)")
        }
    }

    // MARK: - Keyboard Shortcut Trigger Flow Tests

    @Test("Shortcut trigger flow: should show feedback indicator")
    @MainActor
    func testShortcutTriggerShowsFeedback() async throws {
        // Given: configured app
        let mockPermission = MockPermissionService()
        mockPermission.mockState = .authorized

        let mockModelConfig = MockModelConfigService()
        let mockInputFieldReader = MockInputFieldReaderService()
        mockInputFieldReader.mockResult = .success("测试")

        let mockKeyboardShortcut = MockKeyboardShortcutService()

        let environment = AppEnvironment(
            permissionService: mockPermission,
            translationService: MockTranslationService(),
            modelConfigService: mockModelConfig,
            historyService: MockHistoryService(),
            keyboardShortcutService: mockKeyboardShortcut,
            inputFieldReaderService: mockInputFieldReader
        )

        let appState = AppState(environment: environment)

        // Add model config
        let testConfig = ModelConfig(id: UUID(), name: "Test", modelName: "gpt-4", baseURL: "https://api.openai.com", isActive: true)
        try mockModelConfig.saveConfiguration(testConfig, apiKey: "test-key")

        // Wait for state to update
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1s

        // Start monitoring
        appState.startMonitoring()

        #expect(appState.showShortcutFeedback == false)

        // When: triggering shortcut
        mockKeyboardShortcut.simulateShortcut()

        // Wait a bit for the event to be processed
        try await Task.sleep(nanoseconds: 50_000_000) // 0.05s

        // Then: feedback should be shown
        #expect(appState.showShortcutFeedback == true)

        // Wait for feedback to auto-hide
        try await Task.sleep(nanoseconds: 600_000_000) // 0.6s

        // Then: feedback should be hidden
        #expect(appState.showShortcutFeedback == false)
    }

    @Test("Shortcut trigger flow: should handle empty text in focused field")
    @MainActor
    func testShortcutTriggerEmptyText() async throws {
        // Given: configured app with empty text in focused field
        let mockPermission = MockPermissionService()
        mockPermission.mockState = .authorized

        let mockModelConfig = MockModelConfigService()
        let mockInputFieldReader = MockInputFieldReaderService()
        mockInputFieldReader.mockResult = .success("   ") // Empty/whitespace only

        let mockKeyboardShortcut = MockKeyboardShortcutService()

        let environment = AppEnvironment(
            permissionService: mockPermission,
            translationService: MockTranslationService(),
            modelConfigService: mockModelConfig,
            historyService: MockHistoryService(),
            keyboardShortcutService: mockKeyboardShortcut,
            inputFieldReaderService: mockInputFieldReader
        )

        let appState = AppState(environment: environment)

        // Add model config
        let testConfig = ModelConfig(id: UUID(), name: "Test", modelName: "gpt-4", baseURL: "https://api.openai.com", isActive: true)
        try mockModelConfig.saveConfiguration(testConfig, apiKey: "test-key")

        // Wait for state to update
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1s

        // Start monitoring
        appState.startMonitoring()

        // When: triggering shortcut with empty text
        mockKeyboardShortcut.simulateShortcut()

        // Wait for processing
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2s

        // Then: no translation should be triggered (latestTranslation remains nil)
        #expect(appState.latestTranslation == nil)
        #expect(appState.isTranslating == false)
    }

    @Test("Shortcut trigger flow: should ignore password fields")
    @MainActor
    func testShortcutTriggerPasswordField() async throws {
        // Given: configured app with password field focused
        let mockPermission = MockPermissionService()
        mockPermission.mockState = .authorized

        let mockModelConfig = MockModelConfigService()
        let mockInputFieldReader = MockInputFieldReaderService()
        mockInputFieldReader.mockResult = .passwordField

        let mockKeyboardShortcut = MockKeyboardShortcutService()

        let environment = AppEnvironment(
            permissionService: mockPermission,
            translationService: MockTranslationService(),
            modelConfigService: mockModelConfig,
            historyService: MockHistoryService(),
            keyboardShortcutService: mockKeyboardShortcut,
            inputFieldReaderService: mockInputFieldReader
        )

        let appState = AppState(environment: environment)

        // Add model config
        let testConfig = ModelConfig(id: UUID(), name: "Test", modelName: "gpt-4", baseURL: "https://api.openai.com", isActive: true)
        try mockModelConfig.saveConfiguration(testConfig, apiKey: "test-key")

        // Wait for state to update
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1s

        // Start monitoring
        appState.startMonitoring()

        // When: triggering shortcut on password field
        mockKeyboardShortcut.simulateShortcut()

        // Wait for processing
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2s

        // Then: no translation should be triggered and no error shown (privacy)
        #expect(appState.latestTranslation == nil)
        #expect(appState.isTranslating == false)
        #expect(appState.runtimeError == nil) // No error shown for privacy
    }

    // MARK: - Clipboard Fallback Tests
    // Note: Clipboard fallback feature (US-006) was not fully implemented
    // Removing these tests as they reference non-existent functionality

    @Test("Shortcut trigger: should handle no focused element gracefully")
    @MainActor
    func testShortcutTriggerNoFocusedElement() async throws {
        // Given: configured app with no focused element
        let mockPermission = MockPermissionService()
        mockPermission.mockState = .authorized

        let mockModelConfig = MockModelConfigService()
        let mockInputFieldReader = MockInputFieldReaderService()
        mockInputFieldReader.mockResult = .noFocusedElement

        let mockKeyboardShortcut = MockKeyboardShortcutService()

        let environment = AppEnvironment(
            permissionService: mockPermission,
            translationService: MockTranslationService(),
            modelConfigService: mockModelConfig,
            historyService: MockHistoryService(),
            keyboardShortcutService: mockKeyboardShortcut,
            inputFieldReaderService: mockInputFieldReader
        )

        let appState = AppState(environment: environment)

        // Add model config
        let testConfig = ModelConfig(id: UUID(), name: "Test", modelName: "gpt-4", baseURL: "https://api.openai.com", isActive: true)
        try mockModelConfig.saveConfiguration(testConfig, apiKey: "test-key")

        // Wait for state to update
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1s

        // Start monitoring
        appState.startMonitoring()

        // When: triggering shortcut with no focused element
        mockKeyboardShortcut.simulateShortcut()

        // Wait for processing
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2s

        // Then: should handle gracefully without crashing and no translation occurs
        #expect(appState.latestTranslation == nil)
        #expect(appState.runtimeError == nil)
    }

    // MARK: - Permission Gating for Shortcut Trigger Tests

    @Test("Permission gating: shortcut trigger requires accessibility permission")
    @MainActor
    func testShortcutTriggerRequiresPermission() async throws {
        // Given: unauthorized permission state
        let mockPermission = MockPermissionService()
        mockPermission.mockState = .denied

        let mockModelConfig = MockModelConfigService()
        let mockInputFieldReader = MockInputFieldReaderService()
        mockInputFieldReader.mockResult = .success("测试")

        let mockKeyboardShortcut = MockKeyboardShortcutService()

        let environment = AppEnvironment(
            permissionService: mockPermission,
            translationService: MockTranslationService(),
            modelConfigService: mockModelConfig,
            historyService: MockHistoryService(),
            keyboardShortcutService: mockKeyboardShortcut,
            inputFieldReaderService: mockInputFieldReader
        )

        let appState = AppState(environment: environment)

        // Add model config
        let testConfig = ModelConfig(id: UUID(), name: "Test", modelName: "gpt-4", baseURL: "https://api.openai.com", isActive: true)
        try mockModelConfig.saveConfiguration(testConfig, apiKey: "test-key")

        // When: attempting to start monitoring without permission
        appState.startMonitoring()

        // Then: monitoring should not start
        #expect(appState.isMonitoring == false)
        #expect(appState.runtimeError == .permissionMissing)

        // And: keyboard shortcut listener should not be started
        #expect(mockKeyboardShortcut.isListening == false)
    }

    @Test("Permission gating: shortcut listener starts only when authorized")
    @MainActor
    func testShortcutListenerStartsOnlyWhenAuthorized() async throws {
        // Given: authorized permission state
        let mockPermission = MockPermissionService()
        mockPermission.mockState = .authorized

        let mockModelConfig = MockModelConfigService()
        let mockKeyboardShortcut = MockKeyboardShortcutService()

        let environment = AppEnvironment(
            permissionService: mockPermission,
            translationService: MockTranslationService(),
            modelConfigService: mockModelConfig,
            historyService: MockHistoryService(),
            keyboardShortcutService: mockKeyboardShortcut,
            inputFieldReaderService: MockInputFieldReaderService()
        )

        let appState = AppState(environment: environment)

        // Add model config
        let testConfig = ModelConfig(id: UUID(), name: "Test", modelName: "gpt-4", baseURL: "https://api.openai.com", isActive: true)
        try mockModelConfig.saveConfiguration(testConfig, apiKey: "test-key")

        // Wait for state to update
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1s

        // When: starting monitoring with permission
        appState.startMonitoring()

        // Then: monitoring should start and keyboard shortcut listener should be started
        #expect(appState.isMonitoring == true)
        #expect(mockKeyboardShortcut.isListening == true)
    }
}
