//
//  FloatingWindowManager.swift
//  spark
//
//  Created by Claude on 2026/3/16.
//

import SwiftUI
import AppKit

/// Manages the lifecycle of the floating translation window
@MainActor
class FloatingWindowManager: ObservableObject {
    private var floatingWindow: FloatingTranslationWindow?
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    /// Shows the floating translation window
    func showFloatingWindow() {
        guard floatingWindow == nil else { return }

        let window = FloatingTranslationWindow()
        let hostingView = NSHostingView(rootView: FloatingTranslationView().environmentObject(appState))
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)

        // Immediately resign key status to prevent stealing focus
        window.orderFront(nil)

        self.floatingWindow = window
    }

    /// Hides the floating translation window
    func hideFloatingWindow() {
        floatingWindow?.close()
        floatingWindow = nil
    }

    /// Checks if the floating window is currently visible
    var isVisible: Bool {
        return floatingWindow != nil && floatingWindow?.isVisible == true
    }
}
