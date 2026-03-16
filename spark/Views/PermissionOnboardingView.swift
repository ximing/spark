//
//  PermissionOnboardingView.swift
//  spark
//
//  Created by Claude on 2026/3/16.
//

import SwiftUI

/// First-launch permission onboarding view
struct PermissionOnboardingView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 24) {
            // Icon
            Image(systemName: "lock.shield")
                .font(.system(size: 64))
                .foregroundColor(.blue)

            // Title
            Text("Accessibility Permission Required")
                .font(.title)
                .fontWeight(.bold)

            // Description
            Text("Spark needs accessibility permission to monitor your input across applications and provide real-time English translations.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 32)

            // Permission status indicator
            permissionStatusView

            // Actions
            VStack(spacing: 12) {
                Button(action: {
                    appState.openAccessibilitySettings()
                    appState.observePermissionChanges()
                }) {
                    Text("Open System Settings")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)

                Button(action: {
                    appState.checkPermissions()
                }) {
                    Text("Recheck Permission")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray.opacity(0.2))
                        .foregroundColor(.primary)
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 32)

            // Instructions
            if !appState.permissionState.isAuthorized {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Steps to enable:")
                        .font(.headline)

                    InstructionStep(number: 1, text: "Click \"Open System Settings\" above")
                    InstructionStep(number: 2, text: "Find \"spark\" in the Accessibility list")
                    InstructionStep(number: 3, text: "Toggle the switch to enable permission")
                    InstructionStep(number: 4, text: "Return to Spark - it will detect the change automatically")
                }
                .padding(.horizontal, 32)
                .padding(.top, 8)
            }
        }
        .padding(.vertical, 32)
        .frame(maxWidth: 600)
    }

    @ViewBuilder
    private var permissionStatusView: some View {
        HStack(spacing: 12) {
            Image(systemName: appState.permissionState.isAuthorized ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundColor(appState.permissionState.isAuthorized ? .green : .orange)
                .font(.title2)

            Text(permissionStatusText)
                .font(.body)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }

    private var permissionStatusText: String {
        switch appState.permissionState {
        case .notDetermined:
            return "Permission not yet requested"
        case .denied:
            return "Permission denied - please enable in System Settings"
        case .authorized:
            return "Permission granted! Starting monitoring..."
        case .unknown:
            return "Unable to determine permission status"
        }
    }
}

/// Helper view for instruction steps
private struct InstructionStep: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(Color.blue)
                .clipShape(Circle())

            Text(text)
                .font(.body)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Previews

#Preview("Unauthorized State") {
    PermissionOnboardingView()
        .environmentObject({
            let env = AppEnvironment.production()
            let state = AppState(environment: env)
            // Simulate unauthorized state
            state.permissionState = .denied
            return state
        }())
}

#Preview("Authorized State") {
    PermissionOnboardingView()
        .environmentObject({
            let env = AppEnvironment.production()
            let state = AppState(environment: env)
            // Simulate authorized state
            state.permissionState = .authorized
            return state
        }())
}

#Preview("Not Determined State") {
    PermissionOnboardingView()
        .environmentObject({
            let env = AppEnvironment.production()
            let state = AppState(environment: env)
            // Simulate not determined state
            state.permissionState = .notDetermined
            return state
        }())
}
