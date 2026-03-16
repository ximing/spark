//
//  KeyboardShortcutRecorder.swift
//  spark
//
//  Created by Claude on 2026/3/16.
//

import SwiftUI
import AppKit
import Carbon

/// Recording mode for keyboard shortcuts
enum RecordingMode {
    case keyCombo    // Regular key combination like ⌘⇧T
    case doubleTap   // Double-tap like double-tap Control
}

/// A view component that allows users to record keyboard shortcuts by pressing keys
struct KeyboardShortcutRecorder: View {
    /// The currently selected shortcut type
    @Binding var selectedShortcut: KeyboardShortcut
    
    /// Callback when shortcut changes
    var onShortcutChanged: (() -> Void)?
    
    @State private var isRecording: Bool = false
    @State private var recordingMode: RecordingMode = .keyCombo
    @State private var recordedShortcut: CustomKeyboardShortcut?
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerView
            
            presetOption
            
            doubleTapSection
            
            Divider()
                .padding(.vertical, 4)
            
            customKeySection
            
            if let error = errorMessage {
                errorView(message: error)
            }
            
            if !isRecording {
                hintView
            }
            
            if isRecording {
                cancelView
            }
        }
        .padding(12)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
        .onAppear { loadCurrentShortcut() }
        .onDisappear { stopRecording() }
    }
    
    // MARK: - Subviews
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Translation trigger")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("Press the keyboard shortcut you want to use")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if selectedShortcut == .custom && recordedShortcut != nil {
                clearButton
            }
        }
    }
    
    private var clearButton: some View {
        Button(action: clearShortcut) {
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle.fill")
                Text("Clear")
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
    }
    
    private var presetOption: some View {
        Button(action: { selectPreset(.doubleControl) }) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Double Control (⌃⌃)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    Text("Press Control key twice quickly")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                shortcutIndicator(isSelected: selectedShortcut == .doubleControl)
            }
            .padding(10)
            .background(selectedShortcut == .doubleControl ? Color.blue.opacity(0.1) : Color.gray.opacity(0.05))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
    
    private var doubleTapSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Double-tap modifier keys")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
            doubleTapOption(title: "Double-tap Option (⌥⌥)", keyCode: 58)
            doubleTapOption(title: "Double-tap Shift (⇧⇧)", keyCode: 56)
            doubleTapOption(title: "Double-tap Command (⌘⌘)", keyCode: 55)
        }
    }
    
    private func doubleTapOption(title: String, keyCode: UInt16) -> some View {
        let isSelected = isSelectedDoubleTap(keyCode: keyCode)
        return Button(action: { selectDoubleTapShortcut(DoubleTapShortcut(keyCode: keyCode)) }) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                Spacer()
                shortcutIndicator(isSelected: isSelected)
            }
            .padding(8)
            .background(isSelected ? Color.blue.opacity(0.1) : Color.gray.opacity(0.05))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
    
    private var customKeySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Custom key combination")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
            customKeyButton
        }
    }
    
    private var customKeyButton: some View {
        let isRecordingKeyCombo = isRecording && recordingMode == .keyCombo
        let isCustomSelected = selectedShortcut == .custom && !(recordedShortcut?.isDoubleTapShortcut ?? true)
        
        return Button(action: {
            if !isRecording {
                recordingMode = .keyCombo
                startRecording()
            }
        }) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Key Combination")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    if isRecordingKeyCombo {
                        Text("Press your desired key combination...")
                            .font(.caption)
                            .foregroundColor(.red)
                    } else if let shortcut = recordedShortcut, !shortcut.isDoubleTapShortcut {
                        Text(shortcut.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Click to record (e.g., ⌘⇧T)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                shortcutIndicator(isSelected: isCustomSelected, isRecording: isRecordingKeyCombo)
            }
            .padding(10)
            .background(backgroundColor(isRecording: isRecordingKeyCombo, isCustom: isCustomSelected))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isRecordingKeyCombo ? Color.red : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
    
    private func backgroundColor(isRecording: Bool, isCustom: Bool) -> Color {
        if isRecording { return Color.red.opacity(0.1) }
        if isCustom { return Color.blue.opacity(0.1) }
        return Color.gray.opacity(0.05)
    }
    
    private func shortcutIndicator(isSelected: Bool, isRecording: Bool = false) -> some View {
        Group {
            if isRecording {
                Image(systemName: "record.circle")
                    .foregroundColor(.red)
            } else if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.blue)
            } else {
                Image(systemName: "circle")
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func errorView(message: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text(message)
                .font(.caption)
                .foregroundColor(.orange)
        }
    }
    
    private var hintView: some View {
        Text("💡 Tip: You can use double-tap shortcuts or record a custom key combination")
            .font(.caption)
            .foregroundColor(.secondary)
    }
    
    private var cancelView: some View {
        HStack {
            Button(action: { stopRecording() }) {
                HStack(spacing: 4) {
                    Image(systemName: "xmark.circle")
                    Text("Cancel")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            Text("or press ESC")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Logic
    
    private func isSelectedDoubleTap(keyCode: UInt16) -> Bool {
        guard selectedShortcut == .custom,
              let shortcut = recordedShortcut,
              shortcut.isDoubleTapShortcut,
              shortcut.doubleTapKey?.keyCode == keyCode else {
            return false
        }
        return true
    }
    
    private func loadCurrentShortcut() {
        if let rawValue = UserDefaults.standard.string(forKey: "keyboardShortcut"),
           let shortcut = KeyboardShortcut(rawValue: rawValue) {
            selectedShortcut = shortcut
            
            if shortcut == .custom {
                if let data = UserDefaults.standard.data(forKey: "customKeyboardShortcut"),
                   let custom = try? JSONDecoder().decode(CustomKeyboardShortcut.self, from: data) {
                    recordedShortcut = custom
                }
            }
        }
    }
    
    private func selectPreset(_ shortcut: KeyboardShortcut) {
        stopRecording()
        selectedShortcut = shortcut
        UserDefaults.standard.set(shortcut.rawValue, forKey: "keyboardShortcut")
        KeyboardShortcut.clearCustomShortcut()
        recordedShortcut = nil
        onShortcutChanged?()
    }
    
    private func selectDoubleTapShortcut(_ doubleTap: DoubleTapShortcut) {
        stopRecording()
        
        let shortcut = CustomKeyboardShortcut(doubleTap: doubleTap)
        recordedShortcut = shortcut
        selectedShortcut = .custom
        KeyboardShortcut.setCustomShortcut(shortcut)
        onShortcutChanged?()
    }
    
    private func startRecording() {
        errorMessage = nil
        isRecording = true
        recordedShortcut = nil
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            ShortcutRecorderShared.shared.start(
                isRecording: { [self] in self.isRecording },
                recordingMode: { [self] in self.recordingMode },
                onRecorded: { [self] shortcut in self.handleRecordedShortcut(shortcut) },
                onCancel: { [self] in self.stopRecording() }
            )
        }
    }
    
    private func handleRecordedShortcut(_ shortcut: CustomKeyboardShortcut) {
        let hasModifier = shortcut.modifiers & UInt(NSEvent.ModifierFlags.command.rawValue) != 0 ||
                          shortcut.modifiers & UInt(NSEvent.ModifierFlags.option.rawValue) != 0 ||
                          shortcut.modifiers & UInt(NSEvent.ModifierFlags.control.rawValue) != 0
        
        if !hasModifier {
            errorMessage = "Please use a shortcut with at least one modifier (⌘, ⌥, or ⌃)"
            return
        }
        
        stopRecording()
        
        recordedShortcut = shortcut
        selectedShortcut = .custom
        KeyboardShortcut.setCustomShortcut(shortcut)
        onShortcutChanged?()
    }
    
    private func stopRecording() {
        ShortcutRecorderShared.shared.stop()
        isRecording = false
    }
    
    private func clearShortcut() {
        recordedShortcut = nil
        KeyboardShortcut.clearCustomShortcut()
        selectPreset(.doubleControl)
    }
}

// MARK: - Global Shortcut Recorder

private class ShortcutRecorderShared {
    static let shared = ShortcutRecorderShared()
    
    private var onShortcutRecorded: ((CustomKeyboardShortcut) -> Void)?
    private var onCancel: (() -> Void)?
    
    private var eventMonitor: Any?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    
    private var isRecordingCheck: (() -> Bool)?
    private var recordingModeCheck: (() -> RecordingMode)?
    
    func start(isRecording: @escaping () -> Bool, 
               recordingMode: @escaping () -> RecordingMode,
               onRecorded: @escaping (CustomKeyboardShortcut) -> Void, 
               onCancel: @escaping () -> Void) {
        self.isRecordingCheck = isRecording
        self.recordingModeCheck = recordingMode
        self.onShortcutRecorded = onRecorded
        self.onCancel = onCancel
        
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.isRecordingCheck?() == true else { return event }
            return self.handleEvent(event)
        }
        
        setupCGEventTap()
    }
    
    func stop() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        
        onShortcutRecorded = nil
        onCancel = nil
    }
    
    private func handleEvent(_ event: NSEvent) -> NSEvent? {
        if event.keyCode == 53 {
            DispatchQueue.main.async { self.onCancel?() }
            return nil
        }
        
        let mode = recordingModeCheck?() ?? .keyCombo
        guard mode == .keyCombo else { return event }
        
        if let shortcut = CustomKeyboardShortcut(from: event) {
            DispatchQueue.main.async { self.onShortcutRecorded?(shortcut) }
            return nil
        }
        
        return nil
    }
    
    private func setupCGEventTap() {
        let eventMask = (1 << CGEventType.keyDown.rawValue)
        
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { proxy, type, event, refcon in
                guard let refcon = refcon else { return Unmanaged.passRetained(event) }
                let recorder = Unmanaged<ShortcutRecorderShared>.fromOpaque(refcon).takeUnretainedValue()
                
                guard recorder.isRecordingCheck?() == true else { return Unmanaged.passRetained(event) }
                
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                
                if keyCode == 53 {
                    DispatchQueue.main.async { recorder.onCancel?() }
                    return nil
                }
                
                let mode = recorder.recordingModeCheck?() ?? .keyCombo
                guard mode == .keyCombo else { return Unmanaged.passRetained(event) }
                
                let flags = event.flags
                if let shortcut = CustomKeyboardShortcut.fromCGEvent(flags: flags, keyCode: UInt16(keyCode)) {
                    DispatchQueue.main.async { recorder.onShortcutRecorded?(shortcut) }
                    return nil
                }
                
                return Unmanaged.passRetained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }
        
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }
    
    deinit { stop() }
}

// MARK: - CustomKeyboardShortcut Extension

extension CustomKeyboardShortcut {
    static func fromCGEvent(flags: CGEventFlags, keyCode: UInt16) -> CustomKeyboardShortcut? {
        var modifierBits: UInt = 0
        
        if flags.contains(.maskCommand) {
            modifierBits |= UInt(NSEvent.ModifierFlags.command.rawValue)
        }
        if flags.contains(.maskAlternate) {
            modifierBits |= UInt(NSEvent.ModifierFlags.option.rawValue)
        }
        if flags.contains(.maskShift) {
            modifierBits |= UInt(NSEvent.ModifierFlags.shift.rawValue)
        }
        if flags.contains(.maskControl) {
            modifierBits |= UInt(NSEvent.ModifierFlags.control.rawValue)
        }
        
        guard modifierBits != 0 else { return nil }
        
        return CustomKeyboardShortcut(keyCode: keyCode, modifiers: modifierBits)
    }
}

// MARK: - Preview

#Preview {
    KeyboardShortcutRecorder(selectedShortcut: .constant(.doubleControl))
        .frame(width: 500)
        .padding()
}
