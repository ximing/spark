//
//  ContentView.swift
//  spark
//
//  Created by ximing on 2026/3/16.
//
//  Note: This view is no longer used in the app startup flow.
//  The app now launches directly into FloatingTranslationView (history list page).
//  This file is kept for reference and unit test compatibility.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var showingSettings = false

    var body: some View {
        VStack(spacing: 20) {
            // Settings button in top-right corner
            HStack {
                Spacer()
                Button(action: { showingSettings = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "gearshape.fill")
                        Text("Settings")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.gray.opacity(0.1))
                    .foregroundColor(.primary)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)

            // Error banner
            if let error = appState.runtimeError {
                ErrorBanner(error: error, onDismiss: {
                    appState.dismissError()
                })
                .padding(.horizontal)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .imageScale(.large)
                .foregroundStyle(.green)
                .font(.system(size: 48))

            Text("Spark is Ready")
                .font(.title)
                .fontWeight(.bold)

            Text("Press keyboard shortcut to translate text in any input field.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            // Status indicator - showing current status
            HStack(spacing: 8) {
                Image(systemName: appState.activeModelConfig != nil ? "keyboard" : "exclamationmark.triangle")
                    .foregroundColor(appState.activeModelConfig != nil ? .green : .orange)
                Text(appState.activeModelConfig != nil ? "Ready - Use keyboard shortcut to translate" : "Configure a model in Settings")
                    .font(.body)
                    .foregroundColor(appState.activeModelConfig != nil ? .primary : .orange)
            }

            Spacer()
        }
        .padding()
        .sheet(isPresented: $showingSettings) {
            ModelSettingsView()
        }
    }
}

#Preview("Main App") {
    ContentView()
        .environmentObject({
            let env = AppEnvironment.production()
            let state = AppState(environment: env)
            return state
        }())
}

// MARK: - Error Banner Component

private struct ErrorBanner: View {
    let error: RuntimeError
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: error.icon)
                .font(.system(size: 20))
                .foregroundColor(.white)

            Text(error.message)
                .font(.body)
                .foregroundColor(.white)
                .multilineTextAlignment(.leading)

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.white.opacity(0.8))
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding()
        .background(errorBackgroundColor)
        .cornerRadius(8)
    }

    private var errorBackgroundColor: Color {
        switch error {
        case .permissionMissing:
            return Color.orange
        case .modelUnavailable:
            return Color.blue
        case .translationFailed:
            return Color.red
        case .monitoringServiceFailed:
            return Color.purple
        }
    }
}
