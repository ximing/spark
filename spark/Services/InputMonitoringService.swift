//
//  InputMonitoringService.swift
//  spark
//
//  Created by Claude on 2026/3/16.
//

import Foundation
import Combine

/// Protocol for monitoring global input events across macOS applications
protocol InputMonitoringService {
    /// Publisher that emits text changes from the currently focused input (after debounce)
    var inputEvents: AnyPublisher<String, Never> { get }

    /// Starts monitoring global input events
    func startMonitoring()

    /// Stops monitoring global input events
    func stopMonitoring()

    /// Returns whether monitoring is currently active
    var isMonitoring: Bool { get }

    /// Updates the debounce timeout configuration
    /// - Parameter timeout: New debounce timeout in seconds (should be clamped to 0.8-1.5s range)
    func setDebounceTimeout(_ timeout: TimeInterval)
}
