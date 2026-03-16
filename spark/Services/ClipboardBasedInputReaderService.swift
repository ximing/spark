//
//  ClipboardBasedInputReaderService.swift
//  spark
//
//  Created by Claude on 2026/3/16.
//

import Foundation
import AppKit
import Carbon

/// Service that reads focused input field text by simulating keyboard shortcuts
/// This is more reliable than Accessibility API as it works across most macOS applications
final class ClipboardBasedInputReaderService: InputFieldReaderService {

    /// Store original clipboard content to restore after reading
    private var originalClipboardContent: String?

    /// Read focused field text by simulating Cmd+A (select all) + Cmd+C (copy)
    func readFocusedFieldText() async -> InputFieldReadResult {
        // Save current clipboard content
        originalClipboardContent = NSPasteboard.general.string(forType: .string)

        // Clear clipboard before copying
        NSPasteboard.general.clearContents()

        // Small delay to ensure clipboard is ready
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms

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

        return .success(text)
    }
    
    /// Simulate a keyboard key press using CGEvent
    private func simulateKeyPress(keyCode: CGKeyCode, flags: CGEventFlags) {
        // Create key down event
        guard let keyDownEvent = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true) else {
            print("Failed to create key down event for keyCode: \(keyCode)")
            return
        }
        keyDownEvent.flags = flags
        
        // Create key up event
        guard let keyUpEvent = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else {
            print("Failed to create key up event for keyCode: \(keyCode)")
            return
        }
        keyUpEvent.flags = flags
        
        // Post the events
        keyDownEvent.post(tap: .cghidEventTap)
        keyUpEvent.post(tap: .cghidEventTap)
    }
}
