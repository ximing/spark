//
//  AccessibilityPermissionService.swift
//  spark
//
//  Created by Claude on 2026/3/16.
//

import Foundation
import AppKit
import ApplicationServices

/// Real implementation of PermissionService that checks macOS accessibility permissions
class AccessibilityPermissionService: PermissionService {

    /// Checks the current accessibility permission state
    func checkPermissionState() -> PermissionState {
        // Check if the app is trusted to use accessibility features
        let isTrusted = AXIsProcessTrusted()

        if isTrusted {
            return .authorized
        } else {
            // On macOS, we can't distinguish between "not determined" and "denied"
            // after the first check, so we return notDetermined for unauthorized state
            return .notDetermined
        }
    }

    /// Opens macOS System Settings to the Privacy & Security > Accessibility page
    func openAccessibilitySettings() {
        // Modern macOS (13+) uses x-apple.systempreferences URL scheme
        // This opens directly to Privacy & Security > Accessibility
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
