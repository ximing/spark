//
//  ClipboardBasedInputReaderService.swift
//  spark
//
//  Created by Claude on 2026/3/16.
//

import Foundation
import AppKit
import Carbon
import ApplicationServices
import os.log

/// Service that reads focused input field text by simulating keyboard shortcuts
/// This is more reliable than Accessibility API as it works across most macOS applications
final class ClipboardBasedInputReaderService: InputFieldReaderService {

    /// Store original clipboard content to restore after reading
    private var originalClipboardContent: String?

    /// Read focused field text by simulating Cmd+A (select all) + Cmd+C (copy)
    func readFocusedFieldText() async -> InputFieldReadResult {
        // Security check: Detect password fields before any clipboard operations
        if isFocusedElementPasswordField() {
            return .passwordField
        }

        // Save current clipboard content
        originalClipboardContent = NSPasteboard.general.string(forType: .string)

        // Clear clipboard before copying
        NSPasteboard.general.clearContents()

        // Small delay to ensure clipboard is ready
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms

        // First, press Escape to clear any existing selection
        simulateKeyPress(keyCode: CGKeyCode(kVK_Escape), flags: [])
        
        // Small delay
        try? await Task.sleep(nanoseconds: 30_000_000) // 30ms

        // Simulate Cmd+A - Select all
        simulateKeyPress(keyCode: CGKeyCode(kVK_ANSI_A), flags: .maskCommand)

        // Small delay
        try? await Task.sleep(nanoseconds: 30_000_000) // 30ms

        // Simulate Cmd+C - Copy
        simulateKeyPress(keyCode: CGKeyCode(kVK_ANSI_C), flags: .maskCommand)

        // Wait for copy to complete
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms

        // Read clipboard content
        let copiedContent = NSPasteboard.general.string(forType: .string)

        // Restore original clipboard content (optional - can be skipped for better UX)
        if let original = originalClipboardContent {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(original, forType: .string)
        }

        // Check if we got any content
        guard let text = copiedContent, !text.isEmpty else {
            return .noTextValue
        }

        // Press Escape to cancel the selection after copying
        simulateKeyPress(keyCode: CGKeyCode(kVK_Escape), flags: [])

        return .success(text)
    }
    
    /// Simulate a keyboard key press using CGEvent
    private func simulateKeyPress(keyCode: CGKeyCode, flags: CGEventFlags) {
        // Create key down event
        guard let keyDownEvent = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true) else {
            Logger.input.error("Failed to create key down event for keyCode: \(keyCode, privacy: .public)")
            return
        }
        keyDownEvent.flags = flags

        // Create key up event
        guard let keyUpEvent = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else {
            Logger.input.error("Failed to create key up event for keyCode: \(keyCode, privacy: .public)")
            return
        }
        keyUpEvent.flags = flags
        
        // Post the events
        keyDownEvent.post(tap: .cghidEventTap)
        keyUpEvent.post(tap: .cghidEventTap)
    }

    // MARK: - Password Field Detection

    /// Checks if the currently focused element is a password field
    /// - Returns: true if the focused element is a secure text field, false otherwise
    private func isFocusedElementPasswordField() -> Bool {
        // Get the system-wide accessibility object
        let systemWide = AXUIElementCreateSystemWide()

        // Get the currently focused UI element
        var focusedElement: CFTypeRef?
        let focusedResult = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )

        // Check if we successfully got a focused element
        guard focusedResult == .success, let focusedElement = focusedElement else {
            return false
        }

        let element = focusedElement as! AXUIElement
        return isPasswordField(element)
    }

    /// Checks if the given element is a password field
    /// - Parameter element: The AXUIElement to check
    /// - Returns: true if the element is a secure text field, false otherwise
    private func isPasswordField(_ element: AXUIElement) -> Bool {
        // Check the role description to see if it's a password field
        var roleDescription: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXRoleDescriptionAttribute as CFString,
            &roleDescription
        )

        if result == .success, let description = roleDescription as? String {
            // Common role descriptions for password fields
            let passwordIndicators = ["secure text field", "password", "secure"]
            return passwordIndicators.contains { description.lowercased().contains($0) }
        }

        // Also check the role attribute
        var role: CFTypeRef?
        let roleResult = AXUIElementCopyAttributeValue(
            element,
            kAXRoleAttribute as CFString,
            &role
        )

        if roleResult == .success, let roleString = role as? String {
            // In some cases, secure text fields have a specific role
            if roleString == "AXSecureTextField" {
                return true
            }
        }

        // Check for "is secure" attribute which some elements have
        var isSecure: CFTypeRef?
        let secureResult = AXUIElementCopyAttributeValue(
            element,
            "AXIsPasswordField" as CFString,
            &isSecure
        )

        if secureResult == .success, let secureValue = isSecure as? Bool {
            return secureValue
        }

        return false
    }
}
