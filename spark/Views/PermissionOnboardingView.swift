//
//  PermissionOnboardingView.swift
//  spark
//
//  Created by Claude on 2026/3/16.
//
//  First-launch permission onboarding view required by FR-001.
//  This view is shown when the app lacks accessibility permissions.
//

import SwiftUI

/// First-launch permission onboarding view
struct PermissionOnboardingView: View {
    @EnvironmentObject var appState: AppState
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Icon
            Image(systemName: "hand.raised.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.blue)

            // Title
            Text("Welcome to Spark")
                .font(.largeTitle)
                .fontWeight(.bold)

            // Explanation
            VStack(alignment: .leading, spacing: 16) {
                Text("Accessibility Permission Required")
                    .font(.headline)
                    .foregroundColor(.primary)

                Text("Spark needs Accessibility permission to:")
                    .font(.body)
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    PermissionReasonRow(
                        icon: "keyboard.fill",
                        text: "Read text from any application"
                    )
                    PermissionReasonRow(
                        icon: "text.magnifyingglass",
                        text: "Detect when you want to translate"
                    )
                    PermissionReasonRow(
                        icon: "sparkles",
                        text: "Provide real-time translations"
                    )
                }
                .padding(.leading, 8)
            }
            .padding(.horizontal, 32)

            // Permission status indicator
            permissionStatusView

            // Action buttons
            VStack(spacing: 12) {
                if appState.permissionState.isAuthorized {
                    // Permission already granted - allow continue
                    Button(action: onContinue) {
                        Text("Continue")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.blue)
                            .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                } else {
                    // Request permission
                    Button(action: {
                        appState.openAccessibilitySettings()
                    }) {
                        HStack {
                            Image(systemName: "gear")
                            Text("Open System Settings")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)

                    Text("After granting permission, return to this window")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 16)

            Spacer()

            // Privacy note
            Text("Your data stays local. We never collect or store your text.")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.bottom, 24)
        }
        .frame(minWidth: 420, minHeight: 480)
        .onAppear {
            // Start observing permission changes when onboarding appears
            appState.checkPermissions()
            appState.observePermissionChanges()
        }
    }

    @ViewBuilder
    private var permissionStatusView: some View {
        HStack(spacing: 8) {
            if appState.permissionState.isAuthorized {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Permission Granted")
                    .foregroundColor(.green)
            } else {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundColor(.orange)
                Text("Permission Required")
                    .foregroundColor(.orange)
            }
        }
        .font(.subheadline)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(appState.permissionState.isAuthorized ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
        )
    }
}

/// Row showing a reason why permission is needed
private struct PermissionReasonRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 20)
            Text(text)
                .font(.body)
                .foregroundColor(.primary)
        }
    }
}

#Preview("Not Authorized") {
    PermissionOnboardingView(onContinue: {})
        .environmentObject({
            let env = AppEnvironment.production()
            let state = AppState(environment: env)
            state.permissionState = .notDetermined
            return state
        }())
}

#Preview("Authorized") {
    PermissionOnboardingView(onContinue: {})
        .environmentObject({
            let env = AppEnvironment.production()
            let state = AppState(environment: env)
            state.permissionState = .authorized
            return state
        }())
}
