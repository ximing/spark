//
//  GlobalKeyboardShortcutService.swift
//  spark
//
//  Created by Claude on 2026/3/16.
//

import Foundation
import Combine
import AppKit
import Carbon

/// Implementation of KeyboardShortcutService that detects customizable keyboard shortcuts
class GlobalKeyboardShortcutService: KeyboardShortcutService {

    // MARK: - Properties

    private let shortcutSubject = PassthroughSubject<Void, Never>()
    private var eventMonitor: Any?
    private var lastControlKeyPressTime: Date?
    private let doublePressTolerance: TimeInterval = 0.3 // 300ms

    /// Current configured shortcut (loaded from UserDefaults)
    private var currentShortcut: KeyboardShortcut {
        if let rawValue = UserDefaults.standard.string(forKey: "keyboardShortcut"),
           let shortcut = KeyboardShortcut(rawValue: rawValue) {
            return shortcut
        }
        return .doubleControl // Default
    }

    var shortcutTriggered: AnyPublisher<Void, Never> {
        shortcutSubject.eraseToAnyPublisher()
    }

    private(set) var isListening: Bool = false

    // MARK: - Public Methods

    func startListening() {
        guard !isListening else { return }

        // Create a global event monitor for key down events
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            self?.handleKeyEvent(event)
        }

        isListening = true
    }

    func stopListening() {
        guard isListening else { return }

        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }

        lastControlKeyPressTime = nil
        isListening = false
    }

    // MARK: - Private Methods

    private func handleKeyEvent(_ event: NSEvent) {
        let shortcut = currentShortcut

        // Handle double-Control separately (requires timing logic)
        if shortcut == .doubleControl {
            handleDoubleControlEvent(event)
        } else {
            // Handle regular key combinations
            if shortcut.matches(event: event) {
                shortcutSubject.send(())
            }
        }
    }

    private func handleDoubleControlEvent(_ event: NSEvent) {
        // Check if this is a Control key press
        // We use flagsChanged event type to detect modifier keys
        guard event.type == .flagsChanged else { return }

        // Check if the Control key flag is set (pressed)
        let controlPressed = event.modifierFlags.contains(.control)

        // Ignore if Control is being released or if other modifiers are pressed
        guard controlPressed else {
            return
        }

        // Check for other modifiers - we want ONLY Control pressed
        let hasShift = event.modifierFlags.contains(.shift)
        let hasCommand = event.modifierFlags.contains(.command)
        let hasOption = event.modifierFlags.contains(.option)

        // If any other modifier is pressed, ignore this event
        guard !hasShift && !hasCommand && !hasOption else {
            return
        }

        let now = Date()

        // Check if this is a double-press
        if let lastPressTime = lastControlKeyPressTime {
            let timeSinceLastPress = now.timeIntervalSince(lastPressTime)

            if timeSinceLastPress <= doublePressTolerance {
                // Double-press detected!
                shortcutSubject.send(())
                // Reset the timer to avoid triggering multiple times
                lastControlKeyPressTime = nil
                return
            }
        }

        // Record this as the first press (or a new first press after timeout)
        lastControlKeyPressTime = now
    }

    deinit {
        stopListening()
    }
}
