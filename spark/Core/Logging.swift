//
//  Logging.swift
//  spark
//
//  Created by Claude on 2026/3/16.
//

import os.log

/// Centralized logging configuration for the Spark application
extension Logger {
    private static let subsystem = "com.aimo.spark"

    /// Logger for app state changes and lifecycle events
    static let appState = Logger(subsystem: subsystem, category: "AppState")

    /// Logger for translation service operations
    static let translation = Logger(subsystem: subsystem, category: "Translation")

    /// Logger for history service operations
    static let history = Logger(subsystem: subsystem, category: "History")

    /// Logger for settings and model configuration changes
    static let settings = Logger(subsystem: subsystem, category: "Settings")

    /// Logger for input monitoring and keyboard shortcut events
    static let input = Logger(subsystem: subsystem, category: "Input")
}
