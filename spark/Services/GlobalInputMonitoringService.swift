//
//  GlobalInputMonitoringService.swift
//  spark
//
//  Created by Claude on 2026/3/16.
//

import Foundation
import Combine
import AppKit
import ApplicationServices

/// Real implementation of InputMonitoringService that monitors global input events across macOS applications
class GlobalInputMonitoringService: InputMonitoringService {

    // MARK: - Published Properties

    private let inputEventsSubject = PassthroughSubject<String, Never>()

    var inputEvents: AnyPublisher<String, Never> {
        inputEventsSubject.eraseToAnyPublisher()
    }

    private(set) var isMonitoring: Bool = false

    // MARK: - Private Properties

    private var monitoringTimer: Timer?
    private var lastFocusedElement: AXUIElement?
    private var lastActiveApp: NSRunningApplication?
    private var appSwitchObserver: NSObjectProtocol?

    // Poll focused element every 500ms to detect text changes
    private let pollingInterval: TimeInterval = 0.5

    // Debounce configuration
    private var debounceTimeout: TimeInterval
    private var debounceTimer: Timer?
    private var pendingText: String?

    // Track last observed text to prevent resetting debounce timer for unchanged text
    private var lastObservedText: String?

    // Auto-recovery configuration
    private var healthCheckTimer: Timer?
    private let healthCheckInterval: TimeInterval = 2.0 // Check every 2 seconds
    private let recoveryDelay: TimeInterval = 5.0 // Auto-recovery within 5 seconds
    private var lastHealthyCheck: Date?
    private var recoveryAttempts: Int = 0
    private let maxRecoveryAttempts: Int = 3

    // MARK: - Initialization

    /// Initializes the monitoring service with configurable debounce timeout
    /// - Parameter debounceTimeout: Time in seconds to wait after last input before triggering translation (default: 1.0s, range: 0.8-1.5s)
    init(debounceTimeout: TimeInterval = 1.0) {
        // Clamp debounce timeout to valid range (800ms - 1500ms)
        self.debounceTimeout = min(max(debounceTimeout, 0.8), 1.5)
    }

    // MARK: - Public Methods

    /// Updates the debounce timeout configuration
    /// - Parameter timeout: New debounce timeout in seconds (will be clamped to 0.8-1.5s range)
    func setDebounceTimeout(_ timeout: TimeInterval) {
        debounceTimeout = min(max(timeout, 0.8), 1.5)
        print("⏱️ Debounce timeout updated to: \(debounceTimeout)s")
    }

    func startMonitoring() {
        guard !isMonitoring else { return }

        // Verify accessibility permissions
        guard AXIsProcessTrusted() else {
            print("⚠️ Cannot start monitoring: Accessibility permission not granted")
            return
        }

        isMonitoring = true

        // Start monitoring active app switches
        observeAppSwitches()

        // Start polling for focused element text changes
        startPolling()

        // Start health check for auto-recovery
        startHealthCheck()

        // Reset recovery state
        lastHealthyCheck = Date()
        recoveryAttempts = 0

        print("✅ Input monitoring started")
    }

    func stopMonitoring() {
        guard isMonitoring else { return }

        isMonitoring = false

        // Stop polling
        stopPolling()

        // Stop observing app switches
        stopObservingAppSwitches()

        // Stop and clear debounce timer
        cancelDebounce()

        // Stop health check
        stopHealthCheck()

        // Clear state
        lastFocusedElement = nil
        lastActiveApp = nil
        lastHealthyCheck = nil
        recoveryAttempts = 0
        lastObservedText = nil

        print("🛑 Input monitoring stopped")
    }

    // MARK: - Private Methods - App Switch Monitoring

    private func observeAppSwitches() {
        // Observe when the active application changes
        appSwitchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }

            if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                self.handleAppSwitch(to: app)
            }
        }

        // Initialize with current active app
        if let currentApp = NSWorkspace.shared.frontmostApplication {
            lastActiveApp = currentApp
        }
    }

    private func stopObservingAppSwitches() {
        if let observer = appSwitchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            appSwitchObserver = nil
        }
    }

    private func handleAppSwitch(to app: NSRunningApplication) {
        // Auto-reconnect: reset focused element when app switches
        if lastActiveApp?.processIdentifier != app.processIdentifier {
            print("🔄 App switched to: \(app.localizedName ?? "Unknown") - reconnecting monitoring")
            lastFocusedElement = nil
            lastActiveApp = app

            // Reset text tracking on app switch
            lastObservedText = nil

            // Immediately check the new app's focused element
            checkFocusedElement()
        }
    }

    // MARK: - Private Methods - Polling

    private func startPolling() {
        monitoringTimer = Timer.scheduledTimer(
            withTimeInterval: pollingInterval,
            repeats: true
        ) { [weak self] _ in
            self?.checkFocusedElement()
        }

        // Fire immediately
        checkFocusedElement()
    }

    private func stopPolling() {
        monitoringTimer?.invalidate()
        monitoringTimer = nil
    }

    private func checkFocusedElement() {
        guard isMonitoring else { return }

        // Get the system-wide focused UI element
        guard let focusedElement = getSystemFocusedElement() else {
            return
        }

        // Detect focused element change
        let elementChanged = !areElementsEqual(lastFocusedElement, focusedElement)
        if elementChanged {
            lastFocusedElement = focusedElement
            // Reset text tracking when focused element changes
            lastObservedText = nil
        }

        // Apply content filtering rules before debouncing
        if let text = getTextFromElement(focusedElement),
           shouldProcessInput(text, from: focusedElement) {
            // Only schedule debounce if text has changed from last observed value
            if text != lastObservedText {
                lastObservedText = text
                scheduleDebounce(for: text)
            }
            // If text is unchanged, let existing debounce timer continue
        }
    }

    // MARK: - Private Methods - Debounce

    /// Schedules a debounced emission of the input text
    /// - Parameter text: The input text to emit after debounce timeout
    private func scheduleDebounce(for text: String) {
        // Cancel any existing debounce timer
        cancelDebounce()

        // Store the pending text
        pendingText = text

        // Schedule new debounce timer
        debounceTimer = Timer.scheduledTimer(
            withTimeInterval: debounceTimeout,
            repeats: false
        ) { [weak self] _ in
            self?.emitDebouncedText()
        }
    }

    /// Emits the pending debounced text
    private func emitDebouncedText() {
        guard let text = pendingText else { return }

        // Emit the debounced text change event
        inputEventsSubject.send(text)
        print("⏱️ Debounced input emitted after \(debounceTimeout)s idle: \(text.prefix(50))...")

        // Clear pending text and reset observed text tracking
        pendingText = nil
        lastObservedText = nil
    }

    /// Cancels the current debounce timer and clears pending text
    private func cancelDebounce() {
        debounceTimer?.invalidate()
        debounceTimer = nil
        pendingText = nil
    }

    // MARK: - Private Methods - Content Filtering

    /// Applies filtering rules to determine if input should be processed
    /// - Parameters:
    ///   - text: The input text to evaluate
    ///   - element: The focused UI element
    /// - Returns: true if the input should be processed, false if it should be filtered out
    private func shouldProcessInput(_ text: String, from element: AXUIElement) -> Bool {
        // Rule 1: Filter out empty or whitespace-only input
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return false
        }

        // Rule 2: Detect and ignore secure/password fields
        if isSecureField(element) {
            print("🔒 Filtered: secure/password field detected")
            return false
        }

        // Rule 3: Ignore input from Spark's own UI
        if isInputFromSpark() {
            return false
        }

        return true
    }

    /// Checks if the given element is a secure text field (password field)
    private func isSecureField(_ element: AXUIElement) -> Bool {
        // Check the role description attribute
        if let roleDescription = getAttributeValue(element, attribute: kAXRoleDescriptionAttribute as CFString) as? String {
            // Password fields typically have "secure text field" or similar role descriptions
            let lowercased = roleDescription.lowercased()
            if lowercased.contains("secure") || lowercased.contains("password") {
                return true
            }
        }

        // Check the role attribute
        if let role = getAttributeValue(element, attribute: kAXRoleAttribute as CFString) as? String {
            // Check for secure text field role
            if role == "AXSecureTextField" {
                return true
            }
        }

        // Check the subrole attribute
        if let subrole = getAttributeValue(element, attribute: kAXSubroleAttribute as CFString) as? String {
            if subrole.lowercased().contains("secure") {
                return true
            }
        }

        return false
    }

    /// Checks if the current frontmost application is Spark itself
    private func isInputFromSpark() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return false
        }

        // Check if the bundle identifier matches Spark's bundle ID
        return app.bundleIdentifier == "com.aimo.spark"
    }

    // MARK: - Private Methods - Accessibility API

    /// Compares two AXUIElement instances for equality
    private func areElementsEqual(_ element1: AXUIElement?, _ element2: AXUIElement?) -> Bool {
        guard let e1 = element1, let e2 = element2 else {
            return element1 == nil && element2 == nil
        }
        return CFEqual(e1, e2)
    }

    private func getSystemFocusedElement() -> AXUIElement? {
        // Get the frontmost application
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return nil
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        // Get the focused UI element from the app
        var focusedElement: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )

        if result == .success, let element = focusedElement {
            return (element as! AXUIElement)
        }

        return nil
    }

    private func getTextFromElement(_ element: AXUIElement) -> String? {
        // Try to get the selected text first (what user is actively editing)
        if let selectedText = getAttributeValue(element, attribute: kAXSelectedTextAttribute as CFString) as? String,
           !selectedText.isEmpty {
            return selectedText
        }

        // Fall back to the full value of the element
        if let value = getAttributeValue(element, attribute: kAXValueAttribute as CFString) as? String {
            return value
        }

        return nil
    }

    private func getAttributeValue(_ element: AXUIElement, attribute: CFString) -> CFTypeRef? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)

        if result == .success {
            return value
        }

        return nil
    }

    // MARK: - Private Methods - Auto-Recovery

    /// Starts health check monitoring to detect service failures and trigger auto-recovery
    private func startHealthCheck() {
        healthCheckTimer = Timer.scheduledTimer(
            withTimeInterval: healthCheckInterval,
            repeats: true
        ) { [weak self] _ in
            self?.performHealthCheck()
        }
    }

    /// Stops health check monitoring
    private func stopHealthCheck() {
        healthCheckTimer?.invalidate()
        healthCheckTimer = nil
    }

    /// Performs a health check to verify the monitoring service is functioning correctly
    private func performHealthCheck() {
        guard isMonitoring else { return }

        // Check if polling timer is still active
        let isPollingHealthy = monitoringTimer != nil && monitoringTimer!.isValid

        // Check if app switch observer is still registered
        let isAppObserverHealthy = appSwitchObserver != nil

        // Check if accessibility permission is still granted
        let hasPermission = AXIsProcessTrusted()

        // Overall health status
        let isHealthy = isPollingHealthy && isAppObserverHealthy && hasPermission

        if isHealthy {
            // Update last healthy check timestamp
            lastHealthyCheck = Date()
            recoveryAttempts = 0
        } else {
            // Service is unhealthy, check if recovery is needed
            if let lastHealthy = lastHealthyCheck {
                let timeSinceHealthy = Date().timeIntervalSince(lastHealthy)

                if timeSinceHealthy >= recoveryDelay && recoveryAttempts < maxRecoveryAttempts {
                    print("⚠️ Monitoring service unhealthy for \(timeSinceHealthy)s, attempting recovery...")
                    attemptRecovery()
                } else if recoveryAttempts >= maxRecoveryAttempts {
                    print("❌ Monitoring service failed after \(maxRecoveryAttempts) recovery attempts")
                    // Stop monitoring to prevent further issues
                    stopMonitoring()
                }
            }
        }
    }

    /// Attempts to recover the monitoring service by restarting it
    private func attemptRecovery() {
        recoveryAttempts += 1
        print("🔄 Attempting monitoring service recovery (attempt \(recoveryAttempts)/\(maxRecoveryAttempts))...")

        // Stop current monitoring components
        stopPolling()
        stopObservingAppSwitches()
        cancelDebounce()

        // Clear state
        lastFocusedElement = nil
        lastActiveApp = nil
        lastObservedText = nil

        // Restart monitoring components
        observeAppSwitches()
        startPolling()

        // Update recovery state
        lastHealthyCheck = Date()

        print("✅ Monitoring service recovery completed")
    }
}
