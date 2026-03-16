//
//  AccessibilityInputFieldReaderService.swift
//  spark
//
//  Created by Claude on 2026/3/16.
//

import Foundation
import ApplicationServices

/// Implementation of InputFieldReaderService using macOS Accessibility API
class AccessibilityInputFieldReaderService: InputFieldReaderService {

    func readFocusedFieldText() -> InputFieldReadResult {
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
        guard focusedResult == .success else {
            return .noFocusedElement
        }

        guard let focusedElement = focusedElement else {
            return .noFocusedElement
        }

        // Cast to AXUIElement
        let element = focusedElement as! AXUIElement

        // Check if this is a password field first (security check)
        if isPasswordField(element) {
            return .passwordField
        }

        // Try to get the text value from the element
        var value: CFTypeRef?
        let valueResult = AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &value
        )

        // Handle different result codes
        switch valueResult {
        case .success:
            // Successfully got the value
            if let textValue = value as? String {
                return .success(textValue)
            } else {
                // Value exists but is not a string
                return .noTextValue
            }

        case .attributeUnsupported:
            // Element doesn't support value attribute
            return .noTextValue

        case .notImplemented:
            return .error("Accessibility API not implemented for this element")

        case .illegalArgument:
            return .error("Invalid argument to Accessibility API")

        case .invalidUIElement:
            return .error("Focused element is invalid")

        case .cannotComplete:
            return .error("Cannot complete reading operation")

        case .notEnoughPrecision:
            return .error("Not enough precision in value")

        case .failure:
            return .error("Failed to read focused element value")

        case .apiDisabled:
            return .error("Accessibility API is disabled")

        case .noValue:
            // Element has value attribute but no actual value
            return .noTextValue

        case .invalidUIElementObserver:
            return .error("Invalid UI element observer")

        case .actionUnsupported:
            return .error("Action not supported")

        case .notificationUnsupported:
            return .error("Notification not supported")

        case .notificationAlreadyRegistered:
            return .error("Notification already registered")

        case .notificationNotRegistered:
            return .error("Notification not registered")

        case .parameterizedAttributeUnsupported:
            return .error("Parameterized attribute not supported")

        @unknown default:
            return .error("Unknown Accessibility API error")
        }
    }

    // MARK: - Private Methods

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
