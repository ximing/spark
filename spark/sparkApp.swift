//
//  sparkApp.swift
//  spark
//
//  Created by ximing on 2026/3/16.
//

import SwiftUI

@main
struct sparkApp: App {
    @StateObject private var appState: AppState
    @StateObject private var floatingWindowManager: FloatingWindowManager

    init() {
        let environment = AppEnvironment.production()
        let state = AppState(environment: environment)
        _appState = StateObject(wrappedValue: state)
        _floatingWindowManager = StateObject(wrappedValue: FloatingWindowManager(appState: state))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(floatingWindowManager)
                .onAppear {
                    // Show floating window when app starts (if permission is granted)
                    if appState.permissionState.isAuthorized {
                        floatingWindowManager.showFloatingWindow()
                    }
                }
                .onChange(of: appState.permissionState) { oldValue, newValue in
                    // Show floating window when permission is granted
                    if !oldValue.isAuthorized && newValue.isAuthorized {
                        floatingWindowManager.showFloatingWindow()
                    }
                }
        }
    }
}
