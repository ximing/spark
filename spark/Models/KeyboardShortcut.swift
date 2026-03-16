//
//  KeyboardShortcut.swift
//  spark
//
//  Created by Claude on 2026/3/16.
//

import Foundation
import AppKit

/// Supported keyboard shortcuts for triggering translation
enum KeyboardShortcut: String, CaseIterable, Codable {
    case doubleControl = "double_control"
    case cmdShiftT = "cmd_shift_t"
    case cmdOptionT = "cmd_option_t"
    case cmdShiftSpace = "cmd_shift_space"
    case cmdOptionSpace = "cmd_option_space"

    /// Display name for the shortcut
    var displayName: String {
        switch self {
        case .doubleControl:
            return "Double Control"
        case .cmdShiftT:
            return "⌘⇧T"
        case .cmdOptionT:
            return "⌘⌥T"
        case .cmdShiftSpace:
            return "⌘⇧Space"
        case .cmdOptionSpace:
            return "⌘⌥Space"
        }
    }

    /// Detailed description of the shortcut
    var description: String {
        switch self {
        case .doubleControl:
            return "Press Control key twice quickly"
        case .cmdShiftT:
            return "Press Command + Shift + T"
        case .cmdOptionT:
            return "Press Command + Option + T"
        case .cmdShiftSpace:
            return "Press Command + Shift + Space"
        case .cmdOptionSpace:
            return "Press Command + Option + Space"
        }
    }

    /// Returns true if the event matches this shortcut
    func matches(event: NSEvent) -> Bool {
        switch self {
        case .doubleControl:
            // This case is handled specially with timing logic
            return false

        case .cmdShiftT:
            return event.type == .keyDown &&
                   event.modifierFlags.contains(.command) &&
                   event.modifierFlags.contains(.shift) &&
                   event.charactersIgnoringModifiers?.lowercased() == "t"

        case .cmdOptionT:
            return event.type == .keyDown &&
                   event.modifierFlags.contains(.command) &&
                   event.modifierFlags.contains(.option) &&
                   event.charactersIgnoringModifiers?.lowercased() == "t"

        case .cmdShiftSpace:
            return event.type == .keyDown &&
                   event.modifierFlags.contains(.command) &&
                   event.modifierFlags.contains(.shift) &&
                   event.keyCode == 49 // Space key

        case .cmdOptionSpace:
            return event.type == .keyDown &&
                   event.modifierFlags.contains(.command) &&
                   event.modifierFlags.contains(.option) &&
                   event.keyCode == 49 // Space key
        }
    }
}
