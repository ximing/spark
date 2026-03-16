//
//  AppState.swift
//  spark
//
//  Created by Claude on 2026/3/16.
//

import Foundation
import Combine
import AppKit

/// Runtime error types that can occur during app operation
enum RuntimeError: Equatable {
    case permissionMissing
    case modelUnavailable
    case translationFailed(String)
    case monitoringServiceFailed

    var message: String {
        switch self {
        case .permissionMissing:
            return "Accessibility permission is required to monitor input. Please grant permission in System Settings."
        case .modelUnavailable:
            return "No active model configured. Please configure a model in Settings to enable translation."
        case .translationFailed(let reason):
            return "Translation failed: \(reason)"
        case .monitoringServiceFailed:
            return "Input monitoring service has stopped unexpectedly. Please restart monitoring."
        }
    }

    var icon: String {
        switch self {
        case .permissionMissing:
            return "lock.shield.fill"
        case .modelUnavailable:
            return "brain.fill"
        case .translationFailed:
            return "exclamationmark.triangle.fill"
        case .monitoringServiceFailed:
            return "antenna.radiowaves.left.and.right.slash"
        }
    }
}

/// Central application state manager
@MainActor
class AppState: ObservableObject {
    @Published var permissionState: PermissionState = .notDetermined
    @Published var isMonitoring: Bool = false
    @Published var latestTranslation: TranslationResult?
    @Published var modelConfigurations: [ModelConfig] = []
    @Published var activeModelConfig: ModelConfig?
    @Published var historyItems: [HistoryItem] = []
    @Published var isHistoryEnabled: Bool = false
    @Published var runtimeError: RuntimeError?
    @Published var debounceTimeout: TimeInterval = 1.0 {
        didSet {
            // Update the monitoring service when debounce timeout changes
            environment.inputMonitoringService.setDebounceTimeout(debounceTimeout)
            // Persist the value
            UserDefaults.standard.set(debounceTimeout, forKey: "debounceTimeout")
        }
    }
    @Published var isTranslating: Bool = false
    @Published var showShortcutFeedback: Bool = false

    // Clipboard fallback state
    @Published var pendingClipboardText: String?

    // Latency tracking
    @Published var lastTranslationLatency: TimeInterval?
    private var inputEventTimestamp: Date?

    let environment: AppEnvironment
    private var cancellables = Set<AnyCancellable>()

    // Task management for translation pipeline
    private var currentTranslationTask: Task<Void, Never>?

    init(environment: AppEnvironment) {
        self.environment = environment

        // Load persisted debounce timeout (clamped to 800-1500ms range)
        let persistedTimeout = UserDefaults.standard.double(forKey: "debounceTimeout")
        if persistedTimeout > 0 {
            self.debounceTimeout = min(max(persistedTimeout, 0.8), 1.5)
        }

        setupBindings()
        // Check initial permission state
        checkPermissions()
    }

    private func setupBindings() {
        // Bind model configurations
        environment.modelConfigService.configurations
            .receive(on: DispatchQueue.main)
            .assign(to: &$modelConfigurations)

        // Bind history items
        environment.historyService.history
            .receive(on: DispatchQueue.main)
            .assign(to: &$historyItems)

        // Initialize history enabled state from service
        isHistoryEnabled = environment.historyService.isEnabled

        // Subscribe to input events from monitoring service
        environment.inputMonitoringService.inputEvents
            .receive(on: DispatchQueue.main)
            .sink { [weak self] text in
                self?.handleInputEvent(text)
            }
            .store(in: &cancellables)

        // Subscribe to keyboard shortcut events
        environment.keyboardShortcutService.shortcutTriggered
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.handleKeyboardShortcutTriggered()
            }
            .store(in: &cancellables)

        // Track active model configuration changes and auto-start monitoring
        environment.modelConfigService.configurations
            .receive(on: DispatchQueue.main)
            .sink { [weak self] configs in
                guard let self = self else { return }

                // Keep legacy data compatible: when configs exist but none are active,
                // auto-activate the first one to unblock monitoring immediately.
                if !configs.isEmpty,
                   configs.first(where: { $0.isActive }) == nil,
                   let fallbackConfig = configs.first {
                    do {
                        try self.environment.modelConfigService.setActiveConfiguration(id: fallbackConfig.id)
                        return
                    } catch {
                        print("⚠️ Failed to auto-activate fallback model: \(error)")
                    }
                }

                let newActiveConfig = configs.first(where: { $0.isActive }) ?? configs.first
                let hadNoActiveConfig = self.activeModelConfig == nil
                self.activeModelConfig = newActiveConfig

                if newActiveConfig != nil, self.runtimeError == .modelUnavailable {
                    self.runtimeError = nil
                }

                // Auto-start monitoring if permission is granted, we just got an active model,
                // and monitoring is not already running (Refs #3)
                if hadNoActiveConfig,
                   newActiveConfig != nil,
                   self.permissionState.isAuthorized,
                   !self.isMonitoring {
                    // Small delay to ensure model config is fully loaded
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        self.startMonitoring()
                    }
                }
            }
            .store(in: &cancellables)
    }

    /// Handles incoming input events from the monitoring service
    private func handleInputEvent(_ text: String) {
        // Record timestamp when input event arrives (after debounce)
        inputEventTimestamp = Date()

        print("📝 Input event received: \(text.prefix(50))...")

        // Trigger translation if monitoring is active and we have an active model config
        guard isMonitoring else {
            print("⚠️ Translation skipped: monitoring not active")
            return
        }

        guard let activeConfig = activeModelConfig else {
            print("⚠️ Translation skipped: no active model config")
            runtimeError = .modelUnavailable
            return
        }

        // Get API key from secure storage
        guard let apiKey = getAPIKey(for: activeConfig.id) else {
            print("⚠️ Translation skipped: no API key found for active model")
            runtimeError = .modelUnavailable
            return
        }

        // Clear any previous errors before attempting translation
        runtimeError = nil

        // Cancel any in-flight translation task to prevent race conditions
        currentTranslationTask?.cancel()

        // Set loading state before starting translation
        isTranslating = true

        // Trigger translation asynchronously
        currentTranslationTask = Task {
            do {
                let translatedText = try await environment.translationService.translate(
                    text: text,
                    config: activeConfig,
                    apiKey: apiKey
                )

                // Check if task was cancelled before updating UI
                guard !Task.isCancelled else {
                    print("⚠️ Translation cancelled (newer translation in progress)")
                    return
                }

                // Update state on main actor
                await MainActor.run {
                    self.latestTranslation = TranslationResult(
                        originalText: text,
                        translatedText: translatedText,
                        timestamp: Date(),
                        modelName: activeConfig.name
                    )

                    // Calculate latency from input event to translation display
                    if let startTime = self.inputEventTimestamp {
                        let latency = Date().timeIntervalSince(startTime)
                        self.lastTranslationLatency = latency
                        print("⏱️ Translation latency: \(String(format: "%.3f", latency))s")
                    }

                    // Add to history if enabled
                    if let translation = self.latestTranslation {
                        environment.historyService.saveToHistory(translation)
                    }

                    // Clear loading state
                    self.isTranslating = false

                    print("✅ Translation completed: \(translatedText.prefix(50))...")
                }
            } catch {
                // Check if task was cancelled
                guard !Task.isCancelled else {
                    print("⚠️ Translation cancelled (newer translation in progress)")
                    return
                }

                // Handle translation failures without crashing
                await MainActor.run {
                    self.isTranslating = false
                    self.runtimeError = .translationFailed(error.localizedDescription)
                    print("❌ Translation failed: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Handles keyboard shortcut trigger events
    private func handleKeyboardShortcutTriggered() {
        print("⌨️ Keyboard shortcut triggered")

        // Show shortcut feedback indicator
        showShortcutFeedback = true

        // Auto-reset feedback indicator after 500ms
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.showShortcutFeedback = false
        }

        // Check if we have an active model configuration
        guard activeModelConfig != nil else {
            print("⚠️ Shortcut translation skipped: no active model config")
            runtimeError = .modelUnavailable
            return
        }

        // Read text from the currently focused input field
        let readResult = environment.inputFieldReaderService.readFocusedFieldText()

        switch readResult {
        case .success(let text):
            // Check if the text is not empty
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                print("⚠️ Shortcut translation skipped: focused field is empty")
                tryClipboardFallback()
                return
            }

            print("📖 Read text from focused field: \(text.prefix(50))...")
            // Pass the extracted text to the existing translation pipeline
            handleInputEvent(text)

        case .noFocusedElement:
            print("⚠️ Shortcut translation skipped: no focused element")
            tryClipboardFallback()

        case .noTextValue:
            print("⚠️ Shortcut translation skipped: focused element has no text value")
            tryClipboardFallback()

        case .passwordField:
            print("🔒 Shortcut translation skipped: password field detected (security)")
            // Don't show error to user for privacy/security reasons

        case .error(let message):
            print("❌ Shortcut translation failed: \(message)")
            // Show error to user for actual failures
            runtimeError = .translationFailed("Could not read focused field: \(message)")
        }
    }

    /// Attempts to use clipboard content as a fallback when focused field reading fails
    private func tryClipboardFallback() {
        // Try to read from clipboard
        guard let clipboardText = NSPasteboard.general.string(forType: .string) else {
            print("⚠️ Clipboard fallback skipped: no text in clipboard")
            return
        }

        // Check if clipboard text is not empty
        let trimmedText = clipboardText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            print("⚠️ Clipboard fallback skipped: clipboard text is empty")
            return
        }

        print("📋 Clipboard text available: \(trimmedText.prefix(50))...")
        // Store the clipboard text and trigger confirmation dialog
        pendingClipboardText = trimmedText
    }

    /// Confirms and uses the clipboard text for translation
    func useClipboardText() {
        guard let text = pendingClipboardText else { return }
        print("✅ User confirmed clipboard usage")
        pendingClipboardText = nil
        handleInputEvent(text)
    }

    /// Cancels the clipboard fallback
    func cancelClipboardFallback() {
        print("❌ User cancelled clipboard usage")
        pendingClipboardText = nil
    }

    /// Checks and updates permission state
    func checkPermissions() {
        permissionState = environment.permissionService.checkPermissionState()
    }

    /// Opens system accessibility settings
    func openAccessibilitySettings() {
        environment.permissionService.openAccessibilitySettings()
    }

    /// Starts observing permission state changes (useful after opening system settings)
    func observePermissionChanges() {
        // Poll permission state every 2 seconds when waiting for authorization
        guard !permissionState.isAuthorized else { return }

        Timer.publish(every: 2.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                let newState = self.environment.permissionService.checkPermissionState()
                if newState != self.permissionState {
                    self.permissionState = newState
                }
            }
            .store(in: &cancellables)
    }

    /// Starts input monitoring
    func startMonitoring() {
        // Check permission state before starting
        guard permissionState.isAuthorized else {
            runtimeError = .permissionMissing
            return
        }

        // Check if we have an active model configuration
        guard activeModelConfig != nil else {
            runtimeError = .modelUnavailable
            return
        }

        // Clear any previous errors
        runtimeError = nil

        environment.inputMonitoringService.startMonitoring()
        isMonitoring = environment.inputMonitoringService.isMonitoring

        // Start listening for keyboard shortcuts
        environment.keyboardShortcutService.startListening()
    }

    /// Stops input monitoring
    func stopMonitoring() {
        environment.inputMonitoringService.stopMonitoring()
        isMonitoring = environment.inputMonitoringService.isMonitoring

        // Stop listening for keyboard shortcuts
        environment.keyboardShortcutService.stopListening()
    }

    // MARK: - Model Configuration Management

    /// Saves or updates a model configuration with its API key
    func saveModelConfiguration(_ config: ModelConfig, apiKey: String) throws {
        try environment.modelConfigService.saveConfiguration(config, apiKey: apiKey)
    }

    /// Deletes a model configuration
    func deleteModelConfiguration(id: UUID) throws {
        try environment.modelConfigService.deleteConfiguration(id: id)
    }

    /// Sets a model configuration as active (hot-switch)
    func setActiveModelConfiguration(id: UUID) throws {
        try environment.modelConfigService.setActiveConfiguration(id: id)
    }

    /// Retrieves the API key for a model configuration
    func getAPIKey(for id: UUID) -> String? {
        return environment.modelConfigService.getAPIKey(for: id)
    }

    // MARK: - History Management

    /// Enables or disables history recording
    func setHistoryEnabled(_ enabled: Bool) {
        environment.historyService.setEnabled(enabled)
        isHistoryEnabled = enabled
    }

    /// Clears all history items
    func clearHistory() {
        environment.historyService.clearHistory()
    }

    // MARK: - Error Management

    /// Dismisses the current runtime error
    func dismissError() {
        runtimeError = nil
    }
}
