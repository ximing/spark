//
//  FloatingTranslationWindow.swift
//  spark
//
//  Created by Claude on 2026/3/16.
//

import SwiftUI
import AppKit
import os.log

/// Main history page shown on app launch.
struct FloatingTranslationView: View {
    @EnvironmentObject var appState: AppState
    let onOpenSettings: () -> Void

    @State private var showCopySuccess = false
    @State private var copiedItemId: UUID?

    init(onOpenSettings: @escaping () -> Void = {}) {
        self.onOpenSettings = onOpenSettings
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            Divider()

            historyContent

            // Loading indicator at bottom
            if appState.isTranslating {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 16, height: 16)
                    Text("Translating...")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack {
            // Top icon dropdown actions
            Menu {
                Button("Open Settings...", action: onOpenSettings)

                Button("Clear History", role: .destructive) {
                    appState.clearHistory()
                }
                .disabled(appState.historyItems.isEmpty)
            } label: {
                Image(systemName: "sparkles")
                    .foregroundColor(.blue)
                    .font(.headline)
            }
            .menuStyle(.borderlessButton)
            .help("More actions")

            Text("Translation History")
                .font(.headline)

            Spacer()

            // Dedicated settings entry on list page
            Button(action: onOpenSettings) {
                HStack(spacing: 4) {
                    Image(systemName: "gearshape.fill")
                    Text("Settings")
                }
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.gray.opacity(0.12))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .help("Open Settings")

            Text("\(appState.historyItems.count) items")
                .font(.caption)
                .foregroundColor(.secondary)

            // Shortcut trigger feedback indicator
            if appState.showShortcutFeedback {
                HStack(spacing: 4) {
                    Image(systemName: "keyboard.fill")
                        .foregroundColor(.blue)
                    Text("Shortcut")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                .transition(.scale.combined(with: .opacity))
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: appState.showShortcutFeedback)
            }

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
        }
    }

    @ViewBuilder
    private var historyContent: some View {
        if appState.historyItems.isEmpty {
            // Empty state
            VStack(spacing: 8) {
                Image(systemName: "text.magnifyingglass")
                    .font(.system(size: 32))
                    .foregroundColor(.secondary.opacity(0.5))
                Text("No translation history")
                    .font(.body)
                    .foregroundColor(.secondary)
                Text("Press keyboard shortcut to translate")
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.7))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // History list - newest first
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(appState.historyItems) { item in
                            HistoryItemRow(
                                item: item,
                                isCopied: copiedItemId == item.id,
                                onCopy: {
                                    copyTranslation(item.translatedText, itemId: item.id)
                                }
                            )
                            .id(item.id)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onChange(of: appState.historyItems.count) { _, _ in
                    // Scroll to top when new item is added
                    if let firstId = appState.historyItems.first?.id {
                        withAnimation {
                            proxy.scrollTo(firstId, anchor: .top)
                        }
                    }
                }
            }
        }
    }

    /// Copy translation text to clipboard
    private func copyTranslation(_ text: String, itemId: UUID) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        copiedItemId = itemId
        withAnimation(.easeInOut(duration: 0.2)) {
            showCopySuccess = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeInOut(duration: 0.2)) {
                showCopySuccess = false
                copiedItemId = nil
            }
        }

        Logger.history.debug("Copied translation to clipboard: \(text, privacy: .private)")
    }
}

/// Single history item row
private struct HistoryItemRow: View {
    let item: HistoryItem
    let isCopied: Bool
    let onCopy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Original text (Chinese)
            HStack(alignment: .top) {
                Text("原文:")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(width: 30, alignment: .leading)
                Text(item.originalText)
                    .font(.caption)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }

            // Translated text (English)
            HStack(alignment: .top) {
                Text("译文:")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(width: 30, alignment: .leading)
                Text(item.translatedText)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(Color(red: 0.26, green: 0.72, blue: 0.51))
                    .lineLimit(3)
                    .textSelection(.enabled)
            }

            // Footer: timestamp and copy button
            HStack {
                Text(item.timestamp, style: .relative)
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Spacer()

                Button(action: onCopy) {
                    HStack(spacing: 2) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                            .font(.caption2)
                        Text(isCopied ? "Copied" : "Copy")
                            .font(.caption2)
                    }
                    .foregroundColor(isCopied ? .green : .blue)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
}

#Preview("Empty State") {
    FloatingTranslationView()
        .environmentObject({
            let env = AppEnvironment.production()
            let state = AppState(environment: env)
            return state
        }())
        .frame(width: 400, height: 300)
}

#Preview("With History") {
    FloatingTranslationView()
        .environmentObject({
            let env = AppEnvironment.production()
            let state = AppState(environment: env)
            state.historyItems = [
                HistoryItem(
                    id: UUID(),
                    originalText: "你好，世界",
                    translatedText: "Hello, world",
                    timestamp: Date(),
                    modelName: "gpt-4"
                ),
                HistoryItem(
                    id: UUID(),
                    originalText: "今天天气真好",
                    translatedText: "The weather is nice today",
                    timestamp: Date().addingTimeInterval(-60),
                    modelName: "gpt-4"
                )
            ]
            return state
        }())
        .frame(width: 400, height: 300)
}
