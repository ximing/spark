//
//  PermissionState.swift
//  spark
//
//  Created by Claude on 2026/3/16.
//

import Foundation

/// Represents the current state of macOS accessibility permissions
enum PermissionState: Equatable {
    case notDetermined
    case denied
    case authorized
    case unknown

    var isAuthorized: Bool {
        self == .authorized
    }
}
