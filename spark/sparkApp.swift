//
//  sparkApp.swift
//  spark
//
//  Created by ximing on 2026/3/16.
//

import SwiftUI
import AppKit

extension Notification.Name {
    static let openSettingsRequested = Notification.Name("openSettingsRequested")
}

@main
struct sparkApp: App {
    @StateObject private var appState: AppState
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var showOnboarding: Bool

    init() {
        let environment = AppEnvironment.production()
        let state = AppState(environment: environment)
        _appState = StateObject(wrappedValue: state)
        // Skip onboarding if permission is already granted on launch
        _showOnboarding = State(initialValue: !state.permissionState.isAuthorized)
    }

    var body: some Scene {
        WindowGroup("Spark") {
            Group {
                if showOnboarding {
                    PermissionOnboardingView(
                        onContinue: {
                            showOnboarding = false
                        }
                    )
                    .environmentObject(appState)
                    .frame(minWidth: 420, minHeight: 480)
                } else {
                    FloatingTranslationView(
                        onOpenSettings: {
                            appDelegate.showSettingsWindow()
                        }
                    )
                    .environmentObject(appState)
                    .frame(minWidth: 420, minHeight: 320)
                    .onAppear {
                        appDelegate.prepare(appState: appState)
                    }
                }
            }
            .onChange(of: appState.permissionState.isAuthorized) { _, isAuthorized in
                // Auto-transition from onboarding to main view when permission is granted
                if isAuthorized {
                    showOnboarding = false
                    // Reset prepare flag so monitoring can start when main view appears
                    appDelegate.resetPrepare()
                }
            }
            .onChange(of: showOnboarding) { _, newValue in
                // Sync onboarding state with permission state on launch
                if !newValue && !appState.permissionState.isAuthorized {
                    showOnboarding = true
                } else if newValue && appState.permissionState.isAuthorized {
                    showOnboarding = false
                }
            }
        }
        .defaultSize(width: 460, height: 620)
    }
}

// MARK: - App Delegate for Menu Bar

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private(set) var appState: AppState?
    private var settingsWindowController: NSWindowController?
    private var didPrepare = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBarItem()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenSettingsRequest),
            name: .openSettingsRequested,
            object: nil
        )
    }

    @objc private func handleOpenSettingsRequest() {
        showSettingsWindow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag, let mainWindow = NSApp.windows.first {
            mainWindow.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    /// Called from the app to provide state references and startup actions
    func prepare(appState: AppState) {
        guard !didPrepare else { return }
        didPrepare = true

        self.appState = appState

        // Start monitoring after permission is authorized
        appState.startMonitoring()
    }

    /// Resets the prepare flag to allow monitoring to start when transitioning from onboarding
    func resetPrepare() {
        didPrepare = false
    }

    private func setupMenuBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Spark")
            button.action = nil
        }

        let menu = NSMenu()

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(showSettingsWindow), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit Spark", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    @objc func showSettingsWindow() {
        guard let appState else { return }

        if settingsWindowController == nil {
            let settingsView = ModelSettingsView()
                .environmentObject(appState)

            let hostingController = NSHostingController(rootView: settingsView)
            let window = NSWindow(contentViewController: hostingController)
            window.title = "Settings"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.minSize = NSSize(width: 720, height: 520)
            window.setContentSize(NSSize(width: 820, height: 680))
            window.isRestorable = false
            window.center()

            settingsWindowController = NSWindowController(window: window)
        }

        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
