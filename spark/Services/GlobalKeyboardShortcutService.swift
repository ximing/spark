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
    private let settingsShortcutSubject = PassthroughSubject<Void, Never>()
    private var eventMonitor: Any?
    private var lastControlKeyPressTime: Date?
    private var lastDoubleTapKeyCode: UInt16?
    private let doublePressTolerance: TimeInterval = 0.4 // 400ms for double-tap

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

    /// Publisher for settings shortcut triggered events
    var settingsShortcutTriggered: AnyPublisher<Void, Never> {
        settingsShortcutSubject.eraseToAnyPublisher()
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
        lastDoubleTapKeyCode = nil
        isListening = false
    }

    // MARK: - Private Methods

    private func handleKeyEvent(_ event: NSEvent) {
        let shortcut = currentShortcut

        // Handle settings shortcut first (only regular key combinations, not double-tap)
        if let settingsShortcut = KeyboardShortcut.settingsShortcut,
           !settingsShortcut.isDoubleTapShortcut,
           settingsShortcut.matches(event: event) {
            settingsShortcutSubject.send(())
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .openSettingsRequested, object: nil)
            }
            return
        }

        // Handle double-Control or other double-tap shortcuts
        if shortcut == .doubleControl || (shortcut == .custom && shortcut.customShortcut?.isDoubleTapShortcut == true) {
            handleDoubleTapEvent(event)
        } else if shortcut == .custom {
            // Handle custom regular shortcut
            if let customShortcut = shortcut.customShortcut, customShortcut.matches(event: event) {
                shortcutSubject.send(())
            }
        } else {
            // Handle regular key combinations
            if shortcut.matches(event: event) {
                shortcutSubject.send(())
            }
        }
    }

    private func handleDoubleTapEvent(_ event: NSEvent) {
        // Check if this is a modifier key press using flagsChanged
        guard event.type == .flagsChanged else { return }

        // Get the specific key code for the current shortcut
        let targetKeyCode: UInt16
        if let customShortcut = currentShortcut.customShortcut, 
           let doubleTap = customShortcut.doubleTapKey {
            targetKeyCode = doubleTap.keyCode
        } else {
            // Default to Control (59 = Left Control, 62 = Right Control)
            targetKeyCode = 59
        }

        // Check if the target key is pressed
        let controlPressed = event.modifierFlags.contains(.control)
        let optionPressed = event.modifierFlags.contains(.option)
        let shiftPressed = event.modifierFlags.contains(.shift)
        let commandPressed = event.modifierFlags.contains(.command)

        var isTargetKeyPressed = false

        switch targetKeyCode {
        case 59, 62: // Control
            isTargetKeyPressed = controlPressed
        case 58, 61: // Option
            isTargetKeyPressed = optionPressed
        case 56, 60: // Shift
            isTargetKeyPressed = shiftPressed
        case 55: // Command
            isTargetKeyPressed = commandPressed
        default:
            isTargetKeyPressed = controlPressed
        }

        guard isTargetKeyPressed else { return }

        // Check for other modifiers - we want ONLY the target key pressed
        let hasOtherModifiers: Bool
        switch targetKeyCode {
        case 59, 62: // Control
            hasOtherModifiers = shiftPressed || commandPressed || optionPressed
        case 58, 61: // Option
            hasOtherModifiers = controlPressed || shiftPressed || commandPressed
        case 56, 60: // Shift
            hasOtherModifiers = controlPressed || optionPressed || commandPressed
        case 55: // Command
            hasOtherModifiers = controlPressed || optionPressed || shiftPressed
        default:
            hasOtherModifiers = true
        }

        guard !hasOtherModifiers else { return }

        let now = Date()

        // Check if this is a double-press of the same key
        if let lastKeyCode = lastDoubleTapKeyCode, 
           let lastPressTime = lastControlKeyPressTime,
           lastKeyCode == targetKeyCode {
            
            let timeSinceLastPress = now.timeIntervalSince(lastPressTime)

            if timeSinceLastPress <= doublePressTolerance {
                // Double-tap detected!
                shortcutSubject.send(())
                // Reset to avoid multiple triggers
                lastDoubleTapKeyCode = nil
                lastControlKeyPressTime = nil
                return
            }
        }

        // Record this as the first press
        lastDoubleTapKeyCode = targetKeyCode
        lastControlKeyPressTime = now
    }

    deinit {
        stopListening()
    }
}
