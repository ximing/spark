//
//  KeyboardShortcutService.swift
//  spark
//
//  Created by Claude on 2026/3/16.
//

import Foundation
import Combine

/// Protocol for detecting global keyboard shortcuts
protocol KeyboardShortcutService {
    /// Publisher that emits when the configured keyboard shortcut is detected
    var shortcutTriggered: AnyPublisher<Void, Never> { get }

    /// Starts listening for keyboard shortcuts
    func startListening()

    /// Stops listening for keyboard shortcuts
    func stopListening()

    /// Returns whether the service is currently listening
    var isListening: Bool { get }
}
