//
//  ContentView.swift
//  spark
//
//  Created by ximing on 2026/3/16.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var hasCheckedPermission = false
    @State private var showingSettings = false

    var body: some View {
        Group {
            if appState.permissionState.isAuthorized {
                // Main app view after permission is granted
                mainAppView
                    .transition(.opacity)
            } else {
                // Show onboarding for first-launch or when permission is missing
                PermissionOnboardingView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: appState.permissionState.isAuthorized)
        .onChange(of: appState.permissionState) { oldValue, newValue in
            // Transition to monitoring-ready state within 3 seconds after permission granted
            if !oldValue.isAuthorized && newValue.isAuthorized {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    // Permission granted, ready to start monitoring
                    hasCheckedPermission = true
                }
            }
        }
    }

    private var mainAppView: some View {
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

            Text("Accessibility permission granted. Monitoring is ready to start.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            // Monitoring controls
            Button(action: {
                if appState.isMonitoring {
                    appState.stopMonitoring()
                } else {
                    appState.startMonitoring()
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: appState.isMonitoring ? "stop.circle.fill" : "play.circle.fill")
                    Text(appState.isMonitoring ? "Stop Monitoring" : "Start Monitoring")
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 12)
                .background(appState.isMonitoring ? Color.red : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .disabled(appState.activeModelConfig == nil) // Require active model config

            if appState.activeModelConfig == nil {
                Text("Please configure a model in Settings to start monitoring")
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            Spacer()
        }
        .padding()
        .sheet(isPresented: $showingSettings) {
            ModelSettingsView()
        }
    }
}

#Preview("Onboarding - Unauthorized") {
    ContentView()
        .environmentObject({
            let env = AppEnvironment.production()
            let state = AppState(environment: env)
            state.permissionState = .denied
            return state
        }())
}

#Preview("Main App - Authorized") {
    ContentView()
        .environmentObject({
            let env = AppEnvironment.production()
            let state = AppState(environment: env)
            state.permissionState = .authorized
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
