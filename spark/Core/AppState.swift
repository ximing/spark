//
//  AppState.swift
//  spark
//
//  Created by Claude on 2026/3/16.
//

import Foundation
import Combine
import AppKit
import os.log

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
    @Published var isTranslating: Bool = false
    @Published var showShortcutFeedback: Bool = false

    // Latency tracking
    @Published var lastTranslationLatency: TimeInterval?
    private var inputEventTimestamp: Date?

    let environment: AppEnvironment
    private var cancellables = Set<AnyCancellable>()

    // Task management for translation pipeline
    private var currentTranslationTask: Task<Void, Never>?

    init(environment: AppEnvironment) {
        self.environment = environment

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

        // Subscribe to keyboard shortcut events
        environment.keyboardShortcutService.shortcutTriggered
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                Task { [weak self] in
                    await self?.handleKeyboardShortcutTriggered()
                }
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
                        Logger.appState.warning("Failed to auto-activate fallback model: \(error.localizedDescription, privacy: .public)")
                    }
                }

                let newActiveConfig = configs.first(where: { $0.isActive }) ?? configs.first
                let hadNoActiveConfig = self.activeModelConfig == nil
                self.activeModelConfig = newActiveConfig

                if newActiveConfig != nil, self.runtimeError == .modelUnavailable {
                    self.runtimeError = nil
                }

                if hadNoActiveConfig,
                   newActiveConfig != nil,
                   self.permissionState.isAuthorized {
                    // Notify that monitoring should start - the actual start is handled by startMonitoring()
                    // which is the single entry point for starting the keyboard shortcut listener
                }
            }
            .store(in: &cancellables)
    }

    /// Starts the keyboard shortcut listener (always on when permission and model are ready)
    private func startShortcutListener() {
        // Update monitoring state
        isMonitoring = true
        // Start listening for keyboard shortcuts
        environment.keyboardShortcutService.startListening()
        Logger.appState.info("Keyboard shortcut listener started")
    }

    /// Handles incoming input events from the keyboard shortcut trigger
    private func handleInputEvent(_ text: String) {
        // Record timestamp when input event arrives
        inputEventTimestamp = Date()

        Logger.input.debug("Input event received: \(text.prefix(50), privacy: .private)")

        // Trigger translation if we have an active model config
        guard let activeConfig = activeModelConfig else {
            Logger.translation.warning("Translation skipped: no active model config")
            runtimeError = .modelUnavailable
            return
        }

        // Get API key from secure storage
        guard let apiKey = getAPIKey(for: activeConfig.id) else {
            Logger.translation.warning("Translation skipped: no API key found for active model")
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
                    Logger.translation.debug("Translation cancelled (newer translation in progress)")
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
                        Logger.translation.info("Translation latency: \(String(format: "%.3f", latency), privacy: .public)s")
                    }

                    // Add to history if enabled
                    if let translation = self.latestTranslation {
                        environment.historyService.saveToHistory(translation)
                    }

                    // Clear loading state
                    self.isTranslating = false

                    Logger.translation.info("Translation completed: \(translatedText.prefix(50), privacy: .public)...")
                }
            } catch {
                // Check if task was cancelled
                guard !Task.isCancelled else {
                    Logger.translation.debug("Translation cancelled (newer translation in progress)")
                    return
                }

                // Handle translation failures without crashing
                await MainActor.run {
                    self.isTranslating = false
                    self.runtimeError = .translationFailed(error.localizedDescription)
                    Logger.translation.error("Translation failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    /// Handles keyboard shortcut trigger events
    private func handleKeyboardShortcutTriggered() async {
        Logger.input.info("Keyboard shortcut triggered")

        // Show shortcut feedback indicator
        showShortcutFeedback = true

        // Auto-reset feedback indicator after 500ms
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.showShortcutFeedback = false
        }

        // Check if we have an active model configuration
        guard activeModelConfig != nil else {
            Logger.input.warning("Shortcut translation skipped: no active model config")
            runtimeError = .modelUnavailable
            return
        }

        // Read text from the currently focused input field (async)
        let readResult = await environment.inputFieldReaderService.readFocusedFieldText()

        switch readResult {
        case .success(let text):
            // Check if the text is not empty
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                Logger.input.warning("Shortcut translation skipped: focused field is empty")
                return
            }

            Logger.input.debug("Read text from focused field: \(text.prefix(50), privacy: .private)")
            // Pass the extracted text to the existing translation pipeline
            handleInputEvent(text)

        case .noFocusedElement, .noTextValue:
            Logger.input.warning("Shortcut translation skipped: no text in focused field")

        case .passwordField:
            Logger.input.info("Shortcut translation skipped: password field detected (security)")

        case .error(let message):
            Logger.input.error("Shortcut translation failed: \(message, privacy: .public)")
            runtimeError = .translationFailed("Could not read focused field: \(message)")
        }
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

        isMonitoring = true

        // Start listening for keyboard shortcuts
        environment.keyboardShortcutService.startListening()
    }

    /// Stops input monitoring
    func stopMonitoring() {
        isMonitoring = false

        // Stop listening for keyboard shortcuts
        environment.keyboardShortcutService.stopListening()
    }

    /// Restarts the keyboard shortcut service after configuration changes
    func restartKeyboardShortcutService() {
        // Stop the existing listener
        environment.keyboardShortcutService.stopListening()

        // Only restart if we have permission and an active model config
        if permissionState.isAuthorized, activeModelConfig != nil {
            isMonitoring = true
            environment.keyboardShortcutService.startListening()
            Logger.appState.info("Keyboard shortcut service restarted")
        } else {
            isMonitoring = false
            Logger.appState.warning("Keyboard shortcut service not restarted: permission or model missing")
        }
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
