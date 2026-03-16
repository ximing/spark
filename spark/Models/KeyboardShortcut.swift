//
//  KeyboardShortcut.swift
//  spark
//
//  Created by Claude on 2026/3/16.
//

import Foundation
import AppKit
import Carbon

/// Represents a double-tap key shortcut (e.g., double-tap Control, double-tap Option)
struct DoubleTapShortcut: Codable, Equatable, Hashable {
    /// The key code for the modifier key
    let keyCode: UInt16
    
    /// Display name for the shortcut
    var displayName: String {
        return "\(keyName) Double Tap"
    }
    
    /// Description of the shortcut
    var description: String {
        return "Double-tap \(keyName) key"
    }
    
    /// Key name
    var keyName: String {
        switch keyCode {
        case 59: return "Control"  // Left Control
        case 62: return "Control"  // Right Control
        case 58: return "Option"   // Left Option
        case 61: return "Option"   // Right Option
        case 56: return "Shift"    // Left Shift
        case 60: return "Shift"    // Right Shift
        case 55: return "Command"  // Command
        default: return "Key"
        }
    }
    
    /// Check if flags changed event matches this double-tap shortcut
    func matches(event: NSEvent, lastPressTime: Date?, tolerance: TimeInterval) -> Bool {
        guard event.type == .flagsChanged else { return false }
        
        // Check if the specific modifier key is pressed
        let controlPressed = event.modifierFlags.contains(.control)
        let optionPressed = event.modifierFlags.contains(.option)
        let shiftPressed = event.modifierFlags.contains(.shift)
        let commandPressed = event.modifierFlags.contains(.command)
        
        var isTargetKeyPressed = false
        var targetKeyName = ""
        
        switch keyCode {
        case 59, 62: // Control
            isTargetKeyPressed = controlPressed
            targetKeyName = "Control"
        case 58, 61: // Option
            isTargetKeyPressed = optionPressed
            targetKeyName = "Option"
        case 56, 60: // Shift
            isTargetKeyPressed = shiftPressed
            targetKeyName = "Shift"
        case 55: // Command
            isTargetKeyPressed = commandPressed
            targetKeyName = "Command"
        default:
            return false
        }
        
        // Only respond when the target key is pressed (not released)
        guard isTargetKeyPressed else { return false }
        
        // Check for other modifiers - we want ONLY the target modifier
        let hasOtherModifiers = (controlPressed && targetKeyName != "Control") ||
                                 (optionPressed && targetKeyName != "Option") ||
                                 (shiftPressed && targetKeyName != "Shift") ||
                                 (commandPressed && targetKeyName != "Command")
        
        guard !hasOtherModifiers else { return false }
        
        // Check if this is a double-tap
        if let lastTime = lastPressTime {
            let timeSinceLastPress = Date().timeIntervalSince(lastTime)
            if timeSinceLastPress <= tolerance {
                return true
            }
        }
        
        return false
    }
}

/// Represents a custom keyboard shortcut with key code and modifiers
struct CustomKeyboardShortcut: Codable, Equatable, Hashable {
    /// The virtual key code
    let keyCode: UInt16
    
    /// The modifier flags (Command, Shift, Option, Control)
    let modifiers: UInt
    
    /// Whether this is a double-tap shortcut
    let isDoubleTap: Bool
    
    /// For double-tap: the key being double-tapped
    let doubleTapKey: DoubleTapShortcut?
    
    /// Display name for the shortcut
    var displayName: String {
        if isDoubleTap, let doubleTap = doubleTapKey {
            return doubleTap.displayName
        }
        
        var parts: [String] = []
        
        if modifiers & UInt(NSEvent.ModifierFlags.control.rawValue) != 0 {
            parts.append("⌃")
        }
        if modifiers & UInt(NSEvent.ModifierFlags.option.rawValue) != 0 {
            parts.append("⌥")
        }
        if modifiers & UInt(NSEvent.ModifierFlags.shift.rawValue) != 0 {
            parts.append("⇧")
        }
        if modifiers & UInt(NSEvent.ModifierFlags.command.rawValue) != 0 {
            parts.append("⌘")
        }
        
        parts.append(keyCodeToString(keyCode))
        
        return parts.joined()
    }
    
    /// Description of the shortcut
    var description: String {
        if isDoubleTap, let doubleTap = doubleTapKey {
            return doubleTap.description
        }
        
        var parts: [String] = []
        
        if modifiers & UInt(NSEvent.ModifierFlags.control.rawValue) != 0 {
            parts.append("Control")
        }
        if modifiers & UInt(NSEvent.ModifierFlags.option.rawValue) != 0 {
            parts.append("Option")
        }
        if modifiers & UInt(NSEvent.ModifierFlags.shift.rawValue) != 0 {
            parts.append("Shift")
        }
        if modifiers & UInt(NSEvent.ModifierFlags.command.rawValue) != 0 {
            parts.append("Command")
        }
        
        let keyName = keyCodeToString(keyCode)
        if parts.isEmpty {
            return keyName
        } else {
            return parts.joined(separator: " + ") + " + " + keyName
        }
    }
    
    /// Convert key code to string representation
    private func keyCodeToString(_ keyCode: UInt16) -> String {
        switch keyCode {
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 22: return "6"
        case 23: return "5"
        case 24: return "="
        case 25: return "9"
        case 26: return "7"
        case 27: return "-"
        case 28: return "8"
        case 29: return "0"
        case 30: return "]"
        case 31: return "O"
        case 32: return "U"
        case 33: return "["
        case 34: return "I"
        case 35: return "P"
        case 36: return "Return"
        case 37: return "L"
        case 38: return "J"
        case 39: return "'"
        case 40: return "K"
        case 41: return ";"
        case 42: return "\\"
        case 43: return ","
        case 44: return "/"
        case 45: return "N"
        case 46: return "M"
        case 47: return "."
        case 48: return "Tab"
        case 49: return "Space"
        case 50: return "`"
        case 51: return "Delete"
        case 53: return "Escape"
        // Modifier key codes
        case 55: return "Command"
        case 56: return "Shift"
        case 57: return "CapsLock"
        case 58: return "Option"
        case 59: return "Control"
        case 60: return "Right Shift"
        case 61: return "Right Option"
        case 62: return "Right Control"
        case 63: return "Function"
        // Function keys
        case 122: return "F1"
        case 120: return "F2"
        case 99: return "F3"
        case 118: return "F4"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        // Arrow keys
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        // Other
        case 115: return "Home"
        case 116: return "PageUp"
        case 117: return "ForwardDelete"
        case 119: return "End"
        case 121: return "PageDown"
        default: return "Key\(keyCode)"
        }
    }
    
    /// Create from NSEvent (for regular key combinations)
    init?(from event: NSEvent) {
        // Only accept keyDown events
        guard event.type == .keyDown else { return nil }
        
        // Must have at least one modifier (Command, Option, or Control)
        let hasValidModifier = event.modifierFlags.contains(.command) ||
                               event.modifierFlags.contains(.option) ||
                               event.modifierFlags.contains(.control)
        
        guard hasValidModifier else { return nil }
        
        self.keyCode = event.keyCode
        self.isDoubleTap = false
        self.doubleTapKey = nil
        
        var modifierBits: UInt = 0
        if event.modifierFlags.contains(.command) {
            modifierBits |= UInt(NSEvent.ModifierFlags.command.rawValue)
        }
        if event.modifierFlags.contains(.option) {
            modifierBits |= UInt(NSEvent.ModifierFlags.option.rawValue)
        }
        if event.modifierFlags.contains(.shift) {
            modifierBits |= UInt(NSEvent.ModifierFlags.shift.rawValue)
        }
        if event.modifierFlags.contains(.control) {
            modifierBits |= UInt(NSEvent.ModifierFlags.control.rawValue)
        }
        self.modifiers = modifierBits
    }
    
    /// Create a double-tap shortcut
    init(doubleTap: DoubleTapShortcut) {
        self.keyCode = doubleTap.keyCode
        self.modifiers = 0
        self.isDoubleTap = true
        self.doubleTapKey = doubleTap
    }
    
    /// Create manually
    init(keyCode: UInt16, modifiers: UInt) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.isDoubleTap = false
        self.doubleTapKey = nil
    }
    
    /// Check if this shortcut matches an NSEvent (for regular shortcuts)
    func matches(event: NSEvent) -> Bool {
        guard !isDoubleTap else { return false }
        guard event.type == .keyDown else { return false }
        guard event.keyCode == keyCode else { return false }
        
        let eventModifiers = event.modifierFlags
        
        // Check each modifier - must match exactly
        let expectedCommand = (modifiers & UInt(NSEvent.ModifierFlags.command.rawValue)) != 0
        let expectedOption = (modifiers & UInt(NSEvent.ModifierFlags.option.rawValue)) != 0
        let expectedShift = (modifiers & UInt(NSEvent.ModifierFlags.shift.rawValue)) != 0
        let expectedControl = (modifiers & UInt(NSEvent.ModifierFlags.control.rawValue)) != 0
        
        let hasCommand = eventModifiers.contains(.command)
        let hasOption = eventModifiers.contains(.option)
        let hasShift = eventModifiers.contains(.shift)
        let hasControl = eventModifiers.contains(.control)
        
        return hasCommand == expectedCommand &&
               hasOption == expectedOption &&
               hasShift == expectedShift &&
               hasControl == expectedControl
    }
    
    /// Check if this is a double-tap shortcut
    var isDoubleTapShortcut: Bool {
        return isDoubleTap
    }
}

/// Supported keyboard shortcuts for triggering translation
enum KeyboardShortcut: String, Codable {
    case doubleControl = "double_control"
    case custom = "custom"
    
    /// Custom keyboard shortcut (only used when type is .custom)
    var customShortcut: CustomKeyboardShortcut? {
        get {
            guard let data = UserDefaults.standard.data(forKey: "customKeyboardShortcut"),
                  let shortcut = try? JSONDecoder().decode(CustomKeyboardShortcut.self, from: data) else {
                return nil
            }
            return shortcut
        }
        set {
            if let newValue = newValue,
               let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: "customKeyboardShortcut")
            } else {
                UserDefaults.standard.removeObject(forKey: "customKeyboardShortcut")
            }
        }
    }
    
    /// Custom keyboard shortcut for opening settings
    static var settingsShortcut: CustomKeyboardShortcut? {
        get {
            guard let data = UserDefaults.standard.data(forKey: "settingsKeyboardShortcut"),
                  let shortcut = try? JSONDecoder().decode(CustomKeyboardShortcut.self, from: data) else {
                return nil
            }
            return shortcut
        }
        set {
            if let newValue = newValue,
               let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: "settingsKeyboardShortcut")
            } else {
                UserDefaults.standard.removeObject(forKey: "settingsKeyboardShortcut")
            }
        }
    }
    
    /// Display name for the shortcut
    var displayName: String {
        switch self {
        case .doubleControl:
            return "Double Control"
        case .custom:
            return customShortcut?.displayName ?? "Custom"
        }
    }
    
    /// Detailed description of the shortcut
    var description: String {
        switch self {
        case .doubleControl:
            return "Press Control key twice quickly"
        case .custom:
            return customShortcut?.description ?? "Click to record a custom shortcut"
        }
    }
    
    /// Returns true if the event matches this shortcut
    func matches(event: NSEvent) -> Bool {
        switch self {
        case .doubleControl:
            // This case is handled specially with timing logic
            return false
        case .custom:
            return customShortcut?.matches(event: event) ?? false
        }
    }
    
    /// Check if this is a double-tap shortcut (for flagsChanged events)
    func matchesDoubleTap(event: NSEvent, lastPressTime: Date?, tolerance: TimeInterval) -> Bool {
        switch self {
        case .doubleControl:
            // Handle double Control specifically
            if let shortcut = customShortcut, shortcut.isDoubleTapShortcut {
                return shortcut.doubleTapKey?.matches(event: event, lastPressTime: lastPressTime, tolerance: tolerance) ?? false
            }
            // Legacy: double Control
            return event.type == .flagsChanged && 
                   event.modifierFlags.contains(.control) &&
                   !event.modifierFlags.contains(.shift) &&
                   !event.modifierFlags.contains(.command) &&
                   !event.modifierFlags.contains(.option)
        case .custom:
            if let shortcut = customShortcut, shortcut.isDoubleTapShortcut {
                return shortcut.doubleTapKey?.matches(event: event, lastPressTime: lastPressTime, tolerance: tolerance) ?? false
            }
            return false
        }
    }
    
    /// All available preset shortcuts
    static let allPresets: [KeyboardShortcut] = [.doubleControl]
    
    /// Set custom shortcut
    static func setCustomShortcut(_ shortcut: CustomKeyboardShortcut) {
        UserDefaults.standard.set(KeyboardShortcut.custom.rawValue, forKey: "keyboardShortcut")
        // Store the custom shortcut
        if let data = try? JSONEncoder().encode(shortcut) {
            UserDefaults.standard.set(data, forKey: "customKeyboardShortcut")
        }
    }
    
    /// Set double-tap shortcut
    static func setDoubleTapShortcut(_ doubleTapKey: DoubleTapShortcut) {
        let shortcut = CustomKeyboardShortcut(doubleTap: doubleTapKey)
        setCustomShortcut(shortcut)
    }
    
    /// Clear custom shortcut
    static func clearCustomShortcut() {
        UserDefaults.standard.removeObject(forKey: "customKeyboardShortcut")
    }
}
