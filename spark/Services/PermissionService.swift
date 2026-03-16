//
//  PermissionService.swift
//  spark
//
//  Created by Claude on 2026/3/16.
//

import Foundation

/// Protocol for managing macOS accessibility permissions
protocol PermissionService {
    /// Returns the current accessibility permission state
    func checkPermissionState() -> PermissionState

    /// Opens macOS System Settings to the Accessibility permissions page
    func openAccessibilitySettings()
}
