---
ruleType: Always
---

## Project Overview

Spark is a macOS native application built with SwiftUI that provides real-time English translation assistance. It monitors user input across system applications and displays English translations in a floating window, helping users learn English in their daily workflow without disrupting their work.

**Key Product Goals:**
- Monitor global Chinese text input across macOS applications
- Provide real-time English translations via AI models
- Display translations in a non-intrusive floating window
- Allow users to configure and switch between different AI models
- Respect user privacy with local-only history (disabled by default)

## Development Commands

### Building and Running
```bash
# Open the project in Xcode
open spark.xcodeproj

# Build from command line
xcodebuild -scheme spark -configuration Debug build

# Build for release
xcodebuild -scheme spark -configuration Release build

# Clean build
xcodebuild -scheme spark clean
```

### Testing
```bash
# Run all tests
xcodebuild test -scheme spark

# Run unit tests only
xcodebuild test -scheme spark -only-testing:sparkTests

# Run UI tests only
xcodebuild test -scheme spark -only-testing:sparkUITests
```

The project uses Swift's modern Testing framework (not XCTest). Tests are located in:
- `sparkTests/` - Unit tests
- `sparkUITests/` - UI tests

## Project Architecture

### Technology Stack
- **Platform:** macOS 15.0+
- **Language:** Swift 5.0
- **UI Framework:** SwiftUI with SwiftUI Previews enabled
- **Testing:** Swift Testing framework (`import Testing`)
- **Build System:** Xcode 16.0 project

### Core Components (to be implemented)

Based on the PRD (`docs/requires/01.md`), the application architecture should include:

1. **Input Monitoring Service**
   - Requires macOS Accessibility permissions
   - Global input event monitoring across applications
   - Debounce mechanism (default 1000ms, configurable 800-1500ms)
   - Filters out password fields and sensitive inputs

2. **Translation Service**
   - Integrates with configurable AI models
   - Supports custom API endpoints (model name, API key, base URL)
   - Connection testing capability

3. **Floating Window UI**
   - Non-intrusive, always-on-top window
   - Displays latest translation result
   - One-click copy functionality
   - Does not steal input focus

4. **Settings/Configuration**
   - Model configuration management
   - API key secure storage (use macOS Keychain)
   - Local history toggle (default: OFF)
   - Debounce timing configuration

5. **Permission Management**
   - First-launch permission guidance flow
   - Accessibility permission status checking
   - Deep link to System Preferences

### Entitlements

The app uses App Sandbox with read-only access to user-selected files. For the full feature set described in the PRD, you may need to add:
- Accessibility API entitlements for global input monitoring
- Network client entitlement for AI API calls

### Security & Privacy Considerations

**Critical Requirements:**
- API keys MUST be stored in macOS Keychain, never in UserDefaults or plain files
- Password field inputs MUST be filtered and ignored
- History recording is OFF by default
- All history is local-only (no cloud sync in V1)
- Only send necessary text to AI models for translation

## Key Requirements from PRD

The product requirements are detailed in `docs/requires/01.md`. Key functional requirements:

- **FR-001 to FR-010**: Core features including permission handling, input monitoring, content filtering, debouncing, translation display, copy functionality, model configuration, and optional local history
- **Performance**: Target median latency <= 1.8s from input pause to translation display
- **Stability**: Auto-recovery within 5 seconds if monitoring service crashes
- **Privacy**: No history by default, password fields ignored, minimal data sent to AI models

## Code Style

- Use SwiftUI for all UI components
- Leverage Swift Concurrency (async/await) for asynchronous operations
- Use Swift's modern Testing framework for tests (not XCTest)
- Follow Apple's SwiftUI naming conventions
- Use `#Preview` macro for SwiftUI previews

## Product Bundle

- **Bundle Identifier:** com.aimo.spark
- **Product Name:** spark
- **Version:** 1.0 (MARKETING_VERSION)
- **Build:** 1 (CURRENT_PROJECT_VERSION)
