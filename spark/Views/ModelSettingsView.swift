//
//  ModelSettingsView.swift
//  spark
//
//  Created by Claude on 2026/3/16.
//

import SwiftUI
import os.log

struct ModelSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var showingAddEdit = false
    @State private var editingConfig: ModelConfig?
    @State private var testingConfigId: UUID?
    @State private var testResult: String?
    @State private var testError: String?
    @State private var selectedShortcut: KeyboardShortcut = {
        if let rawValue = UserDefaults.standard.string(forKey: "keyboardShortcut"),
           let shortcut = KeyboardShortcut(rawValue: rawValue) {
            return shortcut
        }
        return .doubleControl
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Text("Model Settings")
                    .font(.title)
                    .fontWeight(.bold)

                Spacer()

                Button(action: {
                    editingConfig = nil
                    showingAddEdit = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                        Text("Add Model")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }

            Divider()

            // Active Model Section
            if let activeConfig = appState.activeModelConfig {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Active Model")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    ModelConfigRow(
                        config: activeConfig,
                        isActive: true,
                        isTesting: testingConfigId == activeConfig.id,
                        testResult: testingConfigId == activeConfig.id ? testResult : nil,
                        testError: testingConfigId == activeConfig.id ? testError : nil,
                        onEdit: {
                            editingConfig = activeConfig
                            showingAddEdit = true
                        },
                        onTest: {
                            testConnection(for: activeConfig)
                        },
                        onSetActive: nil,
                        onDelete: nil
                    )
                }
                .padding(.bottom, 16)
            }

            // Available Models Section
            let inactiveConfigs = appState.modelConfigurations.filter { !$0.isActive }
            if !inactiveConfigs.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Available Models")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    ForEach(inactiveConfigs) { config in
                        ModelConfigRow(
                            config: config,
                            isActive: false,
                            isTesting: testingConfigId == config.id,
                            testResult: testingConfigId == config.id ? testResult : nil,
                            testError: testingConfigId == config.id ? testError : nil,
                            onEdit: {
                                editingConfig = config
                                showingAddEdit = true
                            },
                            onTest: {
                                testConnection(for: config)
                            },
                            onSetActive: {
                                setActive(config)
                            },
                            onDelete: {
                                deleteConfig(config)
                            }
                        )
                    }
                }
            }

            // Empty State
            if appState.modelConfigurations.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 64))
                        .foregroundColor(.secondary)

                    Text("No Models Configured")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("Add your first AI model to start translating")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            }

            // Keyboard Shortcut Settings Section
            if !appState.modelConfigurations.isEmpty {
                Divider()
                    .padding(.vertical, 8)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Keyboard Shortcut")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    KeyboardShortcutRecorder(
                        selectedShortcut: $selectedShortcut,
                        onShortcutChanged: {
                            restartKeyboardShortcutService()
                        }
                    )
                }
            }

            // Settings Shortcut Section
            if !appState.modelConfigurations.isEmpty {
                Divider()
                    .padding(.vertical, 8)

                SettingsShortcutRecorder()
            }

            // History Settings Section
            if !appState.modelConfigurations.isEmpty {
                Divider()
                    .padding(.vertical, 8)

                VStack(alignment: .leading, spacing: 12) {
                    Text("History Settings")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 16) {
                        // History Toggle
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Save local history")
                                    .font(.subheadline)
                                    .fontWeight(.medium)

                                Text("When enabled, translation history is stored locally on this device only")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Toggle("", isOn: Binding(
                                get: { appState.isHistoryEnabled },
                                set: { appState.setHistoryEnabled($0) }
                            ))
                            .labelsHidden()
                        }

                        // Clear History Button (only shown when history exists)
                        if !appState.historyItems.isEmpty {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Clear history")
                                        .font(.subheadline)
                                        .fontWeight(.medium)

                                    Text("\(appState.historyItems.count) translation\(appState.historyItems.count == 1 ? "" : "s") stored")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Button(action: {
                                    appState.clearHistory()
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "trash")
                                        Text("Clear All")
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.red.opacity(0.1))
                                    .foregroundColor(.red)
                                    .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(12)
                }
            }

            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 720, minHeight: 520)
        .sheet(isPresented: $showingAddEdit) {
            ModelEditView(config: editingConfig)
        }
    }

    private func testConnection(for config: ModelConfig) {
        guard let apiKey = appState.getAPIKey(for: config.id), !apiKey.isEmpty else {
            testError = "API key not found"
            return
        }

        testingConfigId = config.id
        testResult = nil
        testError = nil

        Task {
            let result = await appState.environment.translationService.testConnection(
                config: config,
                apiKey: apiKey
            )

            await MainActor.run {
                switch result {
                case .success(let message):
                    testResult = message
                    testError = nil
                case .failure(let error):
                    testResult = nil
                    testError = error.localizedDescription
                }

                // Clear test results after 3 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    if testingConfigId == config.id {
                        testingConfigId = nil
                        testResult = nil
                        testError = nil
                    }
                }
            }
        }
    }

    private func setActive(_ config: ModelConfig) {
        do {
            try appState.setActiveModelConfiguration(id: config.id)
        } catch {
            Logger.settings.error("Failed to set active model: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func deleteConfig(_ config: ModelConfig) {
        do {
            try appState.deleteModelConfiguration(id: config.id)
        } catch {
            Logger.settings.error("Failed to delete model: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func restartKeyboardShortcutService() {
        // Restart the keyboard shortcut service through AppState
        appState.restartKeyboardShortcutService()
    }
}

// MARK: - Model Config Row

private struct ModelConfigRow: View {
    let config: ModelConfig
    let isActive: Bool
    let isTesting: Bool
    let testResult: String?
    let testError: String?
    let onEdit: () -> Void
    let onTest: () -> Void
    let onSetActive: (() -> Void)?
    let onDelete: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(config.name)
                            .font(.headline)

                        if isActive {
                            Text("ACTIVE")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.green)
                                .cornerRadius(4)
                        }
                    }

                    Text("Model: \(config.modelName)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    if let baseURL = config.baseURL, !baseURL.isEmpty {
                        Text("Base URL: \(baseURL)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                HStack(spacing: 8) {
                    // Test Connection Button
                    Button(action: onTest) {
                        HStack(spacing: 4) {
                            if isTesting {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .frame(width: 12, height: 12)
                            } else {
                                Image(systemName: "network")
                            }
                            Text("Test")
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .disabled(isTesting)

                    // Edit Button
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .padding(6)
                            .background(Color.gray.opacity(0.1))
                            .foregroundColor(.primary)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)

                    // Set Active Button (only for inactive configs)
                    if let setActive = onSetActive {
                        Button(action: setActive) {
                            Image(systemName: "checkmark.circle")
                                .padding(6)
                                .background(Color.green.opacity(0.1))
                                .foregroundColor(.green)
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }

                    // Delete Button (only for inactive configs)
                    if let delete = onDelete {
                        Button(action: delete) {
                            Image(systemName: "trash")
                                .padding(6)
                                .background(Color.red.opacity(0.1))
                                .foregroundColor(.red)
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Test Result Feedback
            if let result = testResult {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(result)
                        .font(.caption)
                        .foregroundColor(.green)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.green.opacity(0.1))
                .cornerRadius(6)
            }

            if let error = testError {
                HStack(spacing: 8) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.red.opacity(0.1))
                .cornerRadius(6)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
}

// MARK: - Model Edit View

private struct ModelEditView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    let config: ModelConfig?

    @State private var name: String = ""
    @State private var modelName: String = ""
    @State private var baseURL: String = ""
    @State private var apiKey: String = ""
    @State private var showApiKey: Bool = false
    @State private var saveError: String?

    var isEditing: Bool {
        config != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(isEditing ? "Edit Model" : "Add Model")
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color.gray.opacity(0.05))

            // Form
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Name Field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Name")
                            .font(.headline)
                        Text("A friendly name for this model configuration")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("e.g., GPT-4 Turbo", text: $name)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Model Name Field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Model Name")
                            .font(.headline)
                        Text("The exact model identifier from your provider")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("e.g., gpt-4-turbo-preview", text: $modelName)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Base URL Field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Base URL (Optional)")
                            .font(.headline)
                        Text("Custom API endpoint. Leave empty for OpenAI default.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("e.g., https://api.openai.com", text: $baseURL)
                            .textFieldStyle(.roundedBorder)
                    }

                    // API Key Field
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("API Key")
                                .font(.headline)
                            Spacer()
                            if isEditing {
                                Text("Leave empty to keep existing key")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Text("Your API key will be stored securely in macOS Keychain")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack {
                            if showApiKey {
                                TextField("sk-...", text: $apiKey)
                                    .textFieldStyle(.roundedBorder)
                            } else {
                                SecureField("sk-...", text: $apiKey)
                                    .textFieldStyle(.roundedBorder)
                            }

                            Button(action: { showApiKey.toggle() }) {
                                Image(systemName: showApiKey ? "eye.slash" : "eye")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Error Message
                    if let error = saveError {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
                .padding()
            }

            // Footer Buttons
            HStack(spacing: 12) {
                Button(action: { dismiss() }) {
                    Text("Cancel")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.gray.opacity(0.1))
                        .foregroundColor(.primary)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)

                Button(action: saveConfig) {
                    Text("Save")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(canSave ? Color.blue : Color.gray.opacity(0.3))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
            }
            .padding()
            .background(Color.gray.opacity(0.05))
        }
        .frame(width: 500, height: 600)
        .onAppear {
            if let config = config {
                name = config.name
                modelName = config.modelName
                baseURL = config.baseURL ?? ""
                apiKey = "" // Don't pre-fill API key for security
            }
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !modelName.trimmingCharacters(in: .whitespaces).isEmpty &&
        (isEditing || !apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    private func saveConfig() {
        saveError = nil

        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedModelName = modelName.trimmingCharacters(in: .whitespaces)
        let trimmedBaseURL = baseURL.trimmingCharacters(in: .whitespaces)
        let trimmedApiKey = apiKey.trimmingCharacters(in: .whitespaces)

        // Validation
        guard !trimmedName.isEmpty else {
            saveError = "Name is required"
            return
        }

        guard !trimmedModelName.isEmpty else {
            saveError = "Model name is required"
            return
        }

        // For new configs, API key is required
        // For editing, API key is optional (keeps existing if empty)
        if !isEditing && trimmedApiKey.isEmpty {
            saveError = "API key is required"
            return
        }

        let newConfig = ModelConfig(
            id: config?.id ?? UUID(),
            name: trimmedName,
            modelName: trimmedModelName,
            baseURL: trimmedBaseURL.isEmpty ? nil : trimmedBaseURL,
            isActive: config?.isActive ?? (appState.activeModelConfig == nil)
        )

        do {
            // Only update API key if provided
            let keyToSave = isEditing && trimmedApiKey.isEmpty
                ? (appState.getAPIKey(for: newConfig.id) ?? "")
                : trimmedApiKey

            try appState.saveModelConfiguration(newConfig, apiKey: keyToSave)
            dismiss()
        } catch {
            saveError = "Failed to save: \(error.localizedDescription)"
        }
    }
}

// MARK: - Settings Shortcut Recorder

private struct SettingsShortcutRecorder: View {
    @State private var isRecording: Bool = false
    @State private var recordedShortcut: CustomKeyboardShortcut?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerView

            recordButton

            if let error = errorMessage {
                errorView(message: error)
            }

            if let shortcut = recordedShortcut {
                currentShortcutView(shortcut)
            }

            hintView
        }
        .padding(12)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
        .onAppear { loadCurrentShortcut() }
        .onDisappear { stopRecording() }
    }

    // MARK: - Subviews

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Open Settings Shortcut")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("Press a key combination to open settings globally")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if recordedShortcut != nil {
                clearButton
            }
        }
    }

    private var clearButton: some View {
        Button(action: clearShortcut) {
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle.fill")
                Text("Clear")
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
    }

    private var recordButton: some View {
        Button(action: {
            if !isRecording {
                startRecording()
            }
        }) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Key Combination")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)

                    if isRecording {
                        Text("Press your desired key combination...")
                            .font(.caption)
                            .foregroundColor(.red)
                    } else if let shortcut = recordedShortcut {
                        Text(shortcut.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Click to record (e.g., ⌘⇧S)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Image(systemName: isRecording ? "record.circle" : "circle")
                    .foregroundColor(isRecording ? .red : .secondary)
            }
            .padding(10)
            .background(isRecording ? Color.red.opacity(0.1) : Color.gray.opacity(0.05))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isRecording ? Color.red : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private func errorView(message: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text(message)
                .font(.caption)
                .foregroundColor(.orange)
        }
    }

    private func currentShortcutView(_ shortcut: CustomKeyboardShortcut) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
            Text("Current: \(shortcut.displayName)")
                .font(.caption)
                .foregroundColor(.green)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.green.opacity(0.1))
        .cornerRadius(6)
    }

    private var hintView: some View {
        Text("💡 This shortcut will open the Settings window from anywhere")
            .font(.caption)
            .foregroundColor(.secondary)
    }

    // MARK: - Logic

    private func loadCurrentShortcut() {
        if let shortcut = KeyboardShortcut.settingsShortcut {
            recordedShortcut = shortcut
        }
    }

    private func startRecording() {
        errorMessage = nil
        isRecording = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            SettingsShortcutRecorderHelper.shared.start(
                isRecording: { [self] in self.isRecording },
                onRecorded: { [self] shortcut in self.handleRecordedShortcut(shortcut) },
                onCancel: { [self] in self.stopRecording() }
            )
        }
    }

    private func handleRecordedShortcut(_ shortcut: CustomKeyboardShortcut) {
        let hasModifier = shortcut.modifiers & UInt(NSEvent.ModifierFlags.command.rawValue) != 0 ||
                          shortcut.modifiers & UInt(NSEvent.ModifierFlags.option.rawValue) != 0 ||
                          shortcut.modifiers & UInt(NSEvent.ModifierFlags.control.rawValue) != 0

        if !hasModifier {
            errorMessage = "Please use a shortcut with at least one modifier (⌘, ⌥, or ⌃)"
            return
        }

        stopRecording()
        recordedShortcut = shortcut
        KeyboardShortcut.settingsShortcut = shortcut
    }

    private func stopRecording() {
        SettingsShortcutRecorderHelper.shared.stop()
        isRecording = false
    }

    private func clearShortcut() {
        recordedShortcut = nil
        KeyboardShortcut.settingsShortcut = nil
    }
}

// MARK: - Settings Shortcut Recorder Helper

private class SettingsShortcutRecorderHelper {
    static let shared = SettingsShortcutRecorderHelper()

    private var onShortcutRecorded: ((CustomKeyboardShortcut) -> Void)?
    private var onCancel: (() -> Void)?

    private var eventMonitor: Any?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private var isRecordingCheck: (() -> Bool)?

    func start(isRecording: @escaping () -> Bool,
               onRecorded: @escaping (CustomKeyboardShortcut) -> Void,
               onCancel: @escaping () -> Void) {
        self.isRecordingCheck = isRecording
        self.onShortcutRecorded = onRecorded
        self.onCancel = onCancel

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.isRecordingCheck?() == true else { return event }
            return self.handleEvent(event)
        }

        setupCGEventTap()
    }

    func stop() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil

        onShortcutRecorded = nil
        onCancel = nil
    }

    private func handleEvent(_ event: NSEvent) -> NSEvent? {
        if event.keyCode == 53 {
            DispatchQueue.main.async { self.onCancel?() }
            return nil
        }

        if let shortcut = CustomKeyboardShortcut(from: event) {
            DispatchQueue.main.async { self.onShortcutRecorded?(shortcut) }
            return nil
        }

        return event
    }

    private func setupCGEventTap() {
        // Use global event tap for system-wide recording
        let eventMask = (1 << CGEventType.keyDown.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { proxy, type, event, refcon in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let helper = Unmanaged<SettingsShortcutRecorderHelper>.fromOpaque(refcon).takeUnretainedValue()

                if helper.isRecordingCheck?() == true {
                    let nsEvent = NSEvent(cgEvent: event)
                    if let nsEvent = nsEvent,
                       nsEvent.type == .keyDown,
                       nsEvent.keyCode != 53 {
                        if let shortcut = CustomKeyboardShortcut(from: nsEvent) {
                            DispatchQueue.main.async { helper.onShortcutRecorded?(shortcut) }
                            return nil
                        }
                    }
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Logger.settings.error("Failed to create event tap for settings shortcut recorder")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }
}

// MARK: - Previews

#Preview("Empty State") {
    ModelSettingsView()
        .environmentObject({
            let env = AppEnvironment.production()
            let state = AppState(environment: env)
            return state
        }())
}

#Preview("Configured State") {
    ModelSettingsView()
        .environmentObject({
            let env = AppEnvironment.production()
            let state = AppState(environment: env)

            // Add some mock configurations
            let config1 = ModelConfig(
                id: UUID(),
                name: "GPT-4 Turbo",
                modelName: "gpt-4-turbo-preview",
                baseURL: nil,
                isActive: true
            )
            let config2 = ModelConfig(
                id: UUID(),
                name: "Claude 3 Opus",
                modelName: "claude-3-opus-20240229",
                baseURL: "https://api.anthropic.com",
                isActive: false
            )

            // Manually set configurations for preview
            state.modelConfigurations = [config1, config2]
            state.activeModelConfig = config1

            return state
        }())
}
