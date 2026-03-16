//
//  FloatingTranslationWindow.swift
//  spark
//
//  Created by Claude on 2026/3/16.
//

import SwiftUI
import AppKit

/// A floating window that displays translation results without stealing focus
class FloatingTranslationWindow: NSWindow {

    init() {
        super.init(
            contentRect: NSRect(x: 100, y: 100, width: 400, height: 150),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        // Configure window to float above other content
        self.level = .floating

        // Prevent window from stealing focus
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        // Make window non-activating (doesn't steal focus)
        self.isMovableByWindowBackground = true

        // Set title
        self.title = "Translation"

        // Position window in top-right area of screen
        if let screenFrame = NSScreen.main?.visibleFrame {
            let windowFrame = self.frame
            let x = screenFrame.maxX - windowFrame.width - 20
            let y = screenFrame.maxY - windowFrame.height - 20
            self.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }

    /// Override to prevent window from becoming key (stealing focus)
    override var canBecomeKey: Bool {
        return false
    }

    /// Override to prevent window from becoming main
    override var canBecomeMain: Bool {
        return false
    }
}

/// SwiftUI view for the floating translation window content
struct FloatingTranslationView: View {
    @EnvironmentObject var appState: AppState
    @State private var showCopySuccess = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "text.bubble.fill")
                    .foregroundColor(.blue)
                Text("Translation")
                    .font(.headline)
                Spacer()

                // Copy success indicator
                if showCopySuccess {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Copied")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    .transition(.opacity)
                }

                // Copy button (only show when translation exists)
                if appState.latestTranslation != nil {
                    Button(action: copyTranslation) {
                        Image(systemName: "doc.on.doc")
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                    .help("Copy translation")
                }

                if appState.isMonitoring {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                }
            }

            Divider()

            // Translation content
            if let translation = appState.latestTranslation {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        // Original text (optional, can be removed if too verbose)
                        Text("Original:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(translation.originalText)
                            .font(.body)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)

                        // Translation
                        Text("English:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(translation.translatedText)
                            .font(.body)
                            .fontWeight(.medium)
                            .textSelection(.enabled)

                        // Timestamp
                        Text(translation.timestamp, style: .relative)
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        // Loading indicator (shown when new translation is in progress)
                        if appState.isTranslating {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .frame(width: 16, height: 16)
                                Text("Translating new input...")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                            .padding(.top, 4)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                // Empty state or loading state
                VStack(spacing: 8) {
                    if appState.isTranslating {
                        // Loading indicator for first translation
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Translating...")
                            .font(.body)
                            .foregroundColor(.secondary)
                    } else {
                        // Waiting for input
                        Image(systemName: "text.magnifyingglass")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("Waiting for input...")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Copy the current translation to the system clipboard
    private func copyTranslation() {
        guard let translation = appState.latestTranslation else { return }

        // Write to system clipboard using NSPasteboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(translation.translatedText, forType: .string)

        // Show success feedback
        withAnimation(.easeInOut(duration: 0.2)) {
            showCopySuccess = true
        }

        // Auto-dismiss success feedback after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeInOut(duration: 0.2)) {
                showCopySuccess = false
            }
        }

        print("[FloatingTranslationView] Copied translation to clipboard: \(translation.translatedText)")
    }
}

#Preview("Empty State") {
    FloatingTranslationView()
        .environmentObject({
            let env = AppEnvironment.production()
            let state = AppState(environment: env)
            state.isMonitoring = false
            return state
        }())
        .frame(width: 400, height: 150)
}

#Preview("With Translation") {
    FloatingTranslationView()
        .environmentObject({
            let env = AppEnvironment.production()
            let state = AppState(environment: env)
            state.isMonitoring = true
            state.latestTranslation = TranslationResult(
                originalText: "你好，世界",
                translatedText: "Hello, world",
                timestamp: Date(),
                modelName: "gpt-4"
            )
            return state
        }())
        .frame(width: 400, height: 150)
}
