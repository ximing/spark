//
//  InputFieldReaderService.swift
//  spark
//
//  Created by Claude on 2026/3/16.
//

import Foundation

/// Result type for input field text extraction
enum InputFieldReadResult {
    /// Successfully extracted text from the focused input field
    case success(String)

    /// No element is currently focused in the system
    case noFocusedElement

    /// Focused element has no text value (e.g., button, image, etc.)
    case noTextValue

    /// Focused element is a password field (security - should not read)
    case passwordField

    /// Failed to read due to an error
    case error(String)
}

/// Protocol for reading text from the currently focused input field
protocol InputFieldReaderService {
    /// Reads the full text value from the currently focused input field
    /// - Returns: InputFieldReadResult indicating success with text or specific failure reason
    func readFocusedFieldText() async -> InputFieldReadResult
}
