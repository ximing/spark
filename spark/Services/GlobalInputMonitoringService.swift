//
//  GlobalInputMonitoringService.swift
//  spark
//
//  Created by Claude on 2026/3/16.
//
//  架构：双路监听方案
//  路径 A（AXObserver）：适用于 Safari、Chrome、VSCode、Terminal 等支持 Accessibility 的应用
//    - 注册 kAXValueChangedNotification + kAXFocusedUIElementChangedNotification
//    - 事件驱动，零轮询开销
//  路径 B（TSM Event Handler）：适用于微信等 AX 黑盒应用
//    - 挂载 kEventTextInputUnicodeForKeyEvent，在输入法上屏前捕获真实 Unicode 文字
//    - 能捕获所有经过系统 TSM 的上屏事件（包括中文汉字）
//  轮询兜底：极低频（5s）轮询，仅用于恢复意外断开的 AXObserver
//

import Foundation
import Combine
import AppKit
import ApplicationServices
import Carbon

// MARK: - TSM C 回调桥接

/// TSM 事件回调（C 函数，必须在 class 外部定义）
private func tsmEventHandler(
    _ callRef: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData = userData, let event = event else { return OSStatus(eventNotHandledErr) }
    let service = Unmanaged<GlobalInputMonitoringService>.fromOpaque(userData).takeUnretainedValue()
    service.handleTSMEvent(event)
    // 返回 eventNotHandledErr 让事件继续传播，不拦截
    return OSStatus(eventNotHandledErr)
}

// MARK: - AXObserver C 回调桥接

/// AXObserver 回调（C 函数）
private func axObserverCallback(
    _ observer: AXObserver,
    _ element: AXUIElement,
    _ notificationName: CFString,
    _ userData: UnsafeMutableRawPointer?
) {
    guard let userData = userData else { return }
    let service = Unmanaged<GlobalInputMonitoringService>.fromOpaque(userData).takeUnretainedValue()
    service.handleAXNotification(element: element, notification: notificationName as String)
}

// MARK: - GlobalInputMonitoringService

/// 全局输入监听服务，采用 AXObserver + TSM 双路方案
class GlobalInputMonitoringService: InputMonitoringService {

    // MARK: - Public Interface

    private let inputEventsSubject = PassthroughSubject<String, Never>()

    var inputEvents: AnyPublisher<String, Never> {
        inputEventsSubject.eraseToAnyPublisher()
    }

    private(set) var isMonitoring: Bool = false

    // MARK: - Route A: AXObserver（标准应用）

    /// 当前挂载 AXObserver 的应用
    private var axObservedApp: NSRunningApplication?
    /// AXObserver 实例（绑定到 axObservedApp 的 pid）
    private var axObserver: AXObserver?
    /// 当前正在观察的元素列表（用于取消注册）
    private var axObservedElements: [AXUIElement] = []
    /// 是否已成功注册过至少一个 AX 通知（用于决策是否需要降级到 TSM）
    private var axObserverActive: Bool = false

    // MARK: - Route B: TSM Event Handler（微信等 AX 黑盒应用）

    /// TSM 事件处理器引用
    private var tsmEventHandlerRef: EventHandlerRef?
    /// TSM 上屏缓冲区：暂存本次输入的文字，随 debounce 一起发出
    private var tsmBuffer: String = ""
    /// TSM 缓冲区上次更新时间（用于 debounce）
    private var tsmLastUpdateTime: Date?

    // MARK: - App Switch Monitoring

    private var appSwitchObserver: NSObjectProtocol?
    private var lastActiveApp: NSRunningApplication?

    // MARK: - Polling（极低频兜底，仅用于检测 AXObserver 是否需要重附）

    private var pollingTimer: Timer?
    /// 轮询间隔：AXObserver 健康时仅用于周期性健康检查，不做文本读取
    private let pollingInterval: TimeInterval = 5.0

    // MARK: - Debounce

    private var debounceTimeout: TimeInterval
    private var debounceTimer: Timer?
    private var pendingText: String?
    /// 上次发出给 debounce 的文本，避免重复触发
    private var lastObservedText: String?

    // MARK: - AX Query Config

    private let axMessagingTimeout: Float = 0.3
    /// 对于 AX 查询，只重试 1 次（原来 3 次太慢，会阻塞主线程）
    private let axMaxRetryAttempts: Int = 1

    // MARK: - Failure Tracking（决策是否降级到 TSM）

    /// 连续 AX 失败次数（切换应用时归零）
    private var consecutiveAXFailures: Int = 0
    /// 超过此阈值则认为当前应用不支持 AX，不再尝试 AXObserver
    private let axFailureThreshold: Int = 3
    /// 当前应用是否已确认不支持 AX
    private var currentAppIsAXHostile: Bool = false

    // MARK: - Log Suppression（避免日志刷屏）

    /// 连续失败时的日志抑制计数器
    private var suppressedLogCount: Int = 0
    /// 每 N 次抑制才打印一条（避免刷屏）
    private let suppressLogEvery: Int = 10

    // MARK: - Auto-Recovery

    private var healthCheckTimer: Timer?
    private let healthCheckInterval: TimeInterval = 10.0
    private var lastHealthyTimestamp: Date?
    private var recoveryAttempts: Int = 0
    private let maxRecoveryAttempts: Int = 3

    // MARK: - Init

    init(debounceTimeout: TimeInterval = 1.0) {
        self.debounceTimeout = min(max(debounceTimeout, 0.8), 1.5)
    }

    // MARK: - Public Methods

    func setDebounceTimeout(_ timeout: TimeInterval) {
        debounceTimeout = min(max(timeout, 0.8), 1.5)
        print("⏱️ Debounce timeout updated to: \(debounceTimeout)s")
    }

    func startMonitoring() {
        guard !isMonitoring else { return }
        guard AXIsProcessTrusted() else {
            print("⚠️ Cannot start: Accessibility permission not granted")
            return
        }

        isMonitoring = true
        resetState()

        // 1. 监听应用切换
        observeAppSwitches()

        // 2. 启动 TSM 事件监听（全局，对所有应用生效）
        startTSMMonitoring()

        // 3. 针对当前激活的应用附加 AXObserver
        if let currentApp = NSWorkspace.shared.frontmostApplication {
            lastActiveApp = currentApp
            attachAXObserver(to: currentApp)
        }

        // 4. 低频兜底轮询（仅用于健康检查 + 恢复）
        startPolling()
        startHealthCheck()

        print("✅ Input monitoring started (AXObserver + TSM dual-path)")
    }

    func stopMonitoring() {
        guard isMonitoring else { return }

        isMonitoring = false

        stopPolling()
        stopHealthCheck()
        stopObservingAppSwitches()
        detachAXObserver()
        stopTSMMonitoring()
        cancelDebounce()

        resetState()
        print("🛑 Input monitoring stopped")
    }

    // MARK: - State Reset

    private func resetState() {
        lastActiveApp = nil
        lastObservedText = nil
        pendingText = nil
        consecutiveAXFailures = 0
        currentAppIsAXHostile = false
        tsmBuffer = ""
        tsmLastUpdateTime = nil
        suppressedLogCount = 0
        lastHealthyTimestamp = Date()
        recoveryAttempts = 0
    }

    // MARK: - Route A: AXObserver

    /// 将 AXObserver 附加到指定应用，注册 value changed 和 focus changed 通知
    func attachAXObserver(to app: NSRunningApplication) {
        detachAXObserver()

        let pid = app.processIdentifier
        var observer: AXObserver?
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let createResult = AXObserverCreate(pid, axObserverCallback, &observer)
        guard createResult == .success, let obs = observer else {
            logAX("⚠️ AXObserverCreate failed for \(app.localizedName ?? "?") pid=\(pid): \(axErrorDescription(createResult))")
            markCurrentAppAsAXHostile()
            return
        }

        axObserver = obs
        axObservedApp = app
        axObservedElements = []

        // 注册系统级焦点切换通知（跨应用也能收到）
        let systemElement = AXUIElementCreateSystemWide()
        _ = AXUIElementSetMessagingTimeout(systemElement, axMessagingTimeout)
        let focusResult = AXObserverAddNotification(
            obs,
            systemElement,
            kAXFocusedUIElementChangedNotification as CFString,
            selfPtr
        )
        if focusResult == .success || focusResult == .notificationAlreadyRegistered {
            axObservedElements.append(systemElement)
            logAX("✅ Registered kAXFocusedUIElementChangedNotification on system-wide element")
        } else {
            logAX("⚠️ kAXFocusedUIElementChangedNotification failed: \(axErrorDescription(focusResult))")
        }

        // 注册当前应用的焦点元素的值变化通知
        let appElement = AXUIElementCreateApplication(pid)
        _ = AXUIElementSetMessagingTimeout(appElement, axMessagingTimeout)
        registerValueChangedNotification(on: appElement, observer: obs, selfPtr: selfPtr, label: "app-root")

        // 尝试注册当前焦点元素
        if let focusedElement = getFocusedElementQuick(pid: pid) {
            registerValueChangedNotification(on: focusedElement, observer: obs, selfPtr: selfPtr, label: "focused")
        }

        // 将 observer 添加到当前 RunLoop
        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(obs),
            .defaultMode
        )

        axObserverActive = !axObservedElements.isEmpty
        if axObserverActive {
            logAX("✅ AXObserver attached to: \(app.localizedName ?? "Unknown")")
        } else {
            logAX("⚠️ AXObserver attached but no notifications registered for: \(app.localizedName ?? "Unknown")")
            markCurrentAppAsAXHostile()
        }
    }

    /// 注册 kAXValueChangedNotification 到指定元素
    private func registerValueChangedNotification(
        on element: AXUIElement,
        observer: AXObserver,
        selfPtr: UnsafeMutableRawPointer,
        label: String
    ) {
        _ = AXUIElementSetMessagingTimeout(element, axMessagingTimeout)
        let result = AXObserverAddNotification(
            observer,
            element,
            kAXValueChangedNotification as CFString,
            selfPtr
        )
        if result == .success || result == .notificationAlreadyRegistered {
            axObservedElements.append(element)
            logAX("✅ Registered kAXValueChangedNotification on \(label)")
        }
        // attributeUnsupported / notificationUnsupported 是正常的，不打日志
    }

    /// 取消当前 AXObserver 并清理资源
    func detachAXObserver() {
        guard let obs = axObserver else { return }
        CFRunLoopRemoveSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(obs),
            .defaultMode
        )
        axObserver = nil
        axObservedElements = []
        axObservedApp = nil
        axObserverActive = false
    }

    /// AXObserver 回调处理（由 C 桥接调用）
    func handleAXNotification(element: AXUIElement, notification: String) {
        guard isMonitoring else { return }

        let focusChangedNotif = kAXFocusedUIElementChangedNotification as String
        let valueChangedNotif = kAXValueChangedNotification as String

        switch notification {
        case focusChangedNotif:
            logAX("🎯 Focus changed notification received")
            consecutiveAXFailures = 0
            lastObservedText = nil

            // 焦点切换到新元素，重新注册 value changed
            if let obs = axObserver {
                let selfPtr = Unmanaged.passUnretained(self).toOpaque()
                registerValueChangedNotification(on: element, observer: obs, selfPtr: selfPtr, label: "new-focus")
            }

        case valueChangedNotif:
            consecutiveAXFailures = 0
            handleAXValueChanged(element: element)

        default:
            break
        }
    }

    /// 处理 AX 值变化通知，读取文本并触发 debounce
    private func handleAXValueChanged(element: AXUIElement) {
        // 过滤密码框
        guard !isSecureField(element) else {
            logAX("🔒 Skipping secure field value change")
            return
        }
        // 过滤 Spark 自身
        guard !isInputFromSpark() else { return }

        guard let text = getTextFromElement(element) else {
            logAX("⚠️ AX value changed but no text readable")
            return
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != lastObservedText else { return }

        logAX("📝 [AX] Text changed: \(trimmed.prefix(40))")
        lastObservedText = trimmed
        scheduleDebounce(for: trimmed)
    }

    // MARK: - Route B: TSM Event Handler

    /// 启动 TSM 事件监听，注册 kEventTextInputUnicodeForKeyEvent
    private func startTSMMonitoring() {
        stopTSMMonitoring()

        // kEventTextInputUnicodeForKeyEvent 在输入法上屏时触发，携带最终的 Unicode 文字
        // kEventTextInputOffsetToPos / kEventTextInputUpdateActiveInputArea 用于 IME 候选窗口
        var eventTypes = [
            EventTypeSpec(
                eventClass: OSType(kEventClassTextInput),
                eventKind: UInt32(kEventTextInputUnicodeForKeyEvent)
            )
        ]

        let selfPtr = Unmanaged.passRetained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            tsmEventHandler,
            1,
            &eventTypes,
            selfPtr,
            &tsmEventHandlerRef
        )

        if status == noErr {
            print("✅ TSM event handler installed (kEventTextInputUnicodeForKeyEvent)")
        } else {
            print("⚠️ TSM InstallEventHandler failed: \(status)")
        }
    }

    /// 停止 TSM 事件监听
    private func stopTSMMonitoring() {
        if let ref = tsmEventHandlerRef {
            RemoveEventHandler(ref)
            tsmEventHandlerRef = nil
            // 释放 passRetained 的引用
            Unmanaged.passUnretained(self).release()
        }
    }

    /// TSM 事件处理（由 C 桥接调用）
    /// 从 kEventTextInputUnicodeForKeyEvent 中提取上屏的 Unicode 文字
    func handleTSMEvent(_ event: EventRef) {
        guard isMonitoring else { return }

        // 密码输入模式时跳过
        guard IsSecureEventInputEnabled() == false else { return }
        // 跳过 Spark 自身
        guard !isInputFromSpark() else { return }

        // 从事件中提取上屏文字
        // typeCFStringRef 参数需要用 Unmanaged 读取，避免 ARC 错误
        var unmanagedString: Unmanaged<CFString>?
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamTextInputSendText),
            EventParamType(typeCFStringRef),
            nil,
            MemoryLayout<Unmanaged<CFString>?>.size,
            nil,
            &unmanagedString
        )

        guard status == noErr, let unmanaged = unmanagedString else {
            // 尝试 typeUnicodeText（旧格式）
            extractUnicodeTextFromEvent(event)
            return
        }

        let text = unmanaged.takeUnretainedValue() as String
        handleTSMCommittedText(text)
    }

    /// 从 typeUnicodeText 格式的事件中提取文字（兼容旧版应用）
    private func extractUnicodeTextFromEvent(_ event: EventRef) {
        // 先查询数据大小
        var actualSize: Int = 0
        let sizeStatus = GetEventParameter(
            event,
            EventParamName(kEventParamTextInputSendText),
            EventParamType(typeUnicodeText),
            nil,
            0,
            &actualSize,
            nil
        )
        guard sizeStatus == noErr || sizeStatus == errAEReplyNotArrived,
              actualSize > 0 else { return }

        let charCount = actualSize / MemoryLayout<UInt16>.size
        var buffer = [UInt16](repeating: 0, count: charCount + 1)
        var outSize: Int = 0
        let dataStatus = GetEventParameter(
            event,
            EventParamName(kEventParamTextInputSendText),
            EventParamType(typeUnicodeText),
            nil,
            actualSize,
            &outSize,
            &buffer
        )
        guard dataStatus == noErr, outSize > 0 else { return }

        let text = String(utf16CodeUnits: buffer, count: outSize / MemoryLayout<UInt16>.size)
        handleTSMCommittedText(text)
    }

    /// 处理 TSM 上屏的最终文字
    private func handleTSMCommittedText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // 过滤纯 ASCII/拼音（TSM 会同时发出拼音和汉字，只要包含中文的就处理）
        // 但也支持用户在其他语言场景输入，所以不强制要求必须是中文
        // 跳过单个功能性控制字符（如回车、退格等）
        guard trimmed.unicodeScalars.contains(where: { $0.value > 0x7E }) ||
              trimmed.count > 1 else {
            // 允许多字符英文短句通过（用户可能在英文场景）
            // 但单个 ASCII 字符（如按回车得到 \n）不触发翻译
            return
        }

        logAX("📝 [TSM] Committed text: \(trimmed.prefix(40))")

        // TSM 路径：累积文字到 tsmBuffer，用 debounce 合并连续上屏
        tsmBuffer += trimmed
        tsmLastUpdateTime = Date()

        // 如果 AX 路径已经处理了相同的文字，避免重复触发
        if tsmBuffer == lastObservedText {
            tsmBuffer = ""
            return
        }

        lastObservedText = tsmBuffer
        scheduleDebounce(for: tsmBuffer)
    }

    // MARK: - App Switch Monitoring

    private func observeAppSwitches() {
        appSwitchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else { return }
            self.handleAppSwitch(to: app)
        }
    }

    private func stopObservingAppSwitches() {
        if let obs = appSwitchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            appSwitchObserver = nil
        }
    }

    private func handleAppSwitch(to app: NSRunningApplication) {
        guard lastActiveApp?.processIdentifier != app.processIdentifier else { return }

        print("🔄 App switched to: \(app.localizedName ?? "Unknown")")
        lastActiveApp = app
        lastObservedText = nil
        consecutiveAXFailures = 0
        currentAppIsAXHostile = false
        tsmBuffer = ""

        // 重新附加 AXObserver 到新应用
        attachAXObserver(to: app)
    }

    // MARK: - Low-Frequency Polling（兜底）

    /// 低频轮询：不做文本读取，仅用于：
    ///   1. 检测 AXObserver 是否意外断开并恢复
    ///   2. 在 AX 不可用时尝试回退到直接读取（最后手段）
    private func startPolling() {
        pollingTimer = Timer.scheduledTimer(
            withTimeInterval: pollingInterval,
            repeats: true
        ) { [weak self] _ in
            self?.pollingTick()
        }
    }

    private func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }

    private func pollingTick() {
        guard isMonitoring else { return }

        // 如果 AXObserver 已激活且当前应用没有变化，无需轮询读取文本
        if axObserverActive && !currentAppIsAXHostile {
            return
        }

        // 当前应用不支持 AX（如微信），TSM 路径负责文本捕获，轮询不介入
        // 此处只做状态日志（静默，避免刷屏）
        if currentAppIsAXHostile {
            return
        }

        // 应用切换后 AXObserver 尚未建立（短暂窗口），尝试快速读取一次
        if let app = NSWorkspace.shared.frontmostApplication,
           app.processIdentifier != axObservedApp?.processIdentifier {
            attachAXObserver(to: app)
        }
    }

    /// 将当前应用标记为 AX 敌对（不支持 Accessibility API）
    private func markCurrentAppAsAXHostile() {
        if !currentAppIsAXHostile {
            currentAppIsAXHostile = true
            print("ℹ️ App \(lastActiveApp?.localizedName ?? "Unknown") does not support AX — TSM path will handle input")
        }
    }

    // MARK: - Debounce

    private func scheduleDebounce(for text: String) {
        cancelDebounce()
        pendingText = text

        debounceTimer = Timer.scheduledTimer(
            withTimeInterval: debounceTimeout,
            repeats: false
        ) { [weak self] _ in
            self?.emitDebouncedText()
        }
    }

    private func emitDebouncedText() {
        guard let text = pendingText else { return }

        inputEventsSubject.send(text)
        print("⏱️ Debounced input emitted (\(debounceTimeout)s): \(text.prefix(50))")

        pendingText = nil
        lastObservedText = nil
        // 清空 TSM 缓冲区（已发出）
        tsmBuffer = ""
    }

    private func cancelDebounce() {
        debounceTimer?.invalidate()
        debounceTimer = nil
        pendingText = nil
    }

    // MARK: - AX Helpers

    /// 快速获取指定 pid 应用的当前焦点元素（单次查询，不重试）
    private func getFocusedElementQuick(pid: pid_t) -> AXUIElement? {
        let appElement = AXUIElementCreateApplication(pid)
        _ = AXUIElementSetMessagingTimeout(appElement, axMessagingTimeout)

        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &value
        )
        guard result == .success, let value = value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return (value as! AXUIElement)
    }

    private func getTextFromElement(_ element: AXUIElement) -> String? {
        _ = AXUIElementSetMessagingTimeout(element, axMessagingTimeout)

        // 优先读 selectedText（用户选中的文字），其次是整个 value
        if let text = readStringAttribute(element, kAXSelectedTextAttribute as CFString), !text.isEmpty {
            return text
        }
        if let text = readStringAttribute(element, kAXValueAttribute as CFString), !text.isEmpty {
            return text
        }
        return nil
    }

    private func readStringAttribute(_ element: AXUIElement, _ attribute: CFString) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success, let value = value else { return nil }

        if let str = value as? String { return str }
        if let attrStr = value as? NSAttributedString { return attrStr.string }
        return nil
    }

    private func isSecureField(_ element: AXUIElement) -> Bool {
        if let role = readStringAttribute(element, kAXRoleAttribute as CFString),
           role == "AXSecureTextField" { return true }
        if let roleDesc = readStringAttribute(element, kAXRoleDescriptionAttribute as CFString) {
            let lower = roleDesc.lowercased()
            if lower.contains("secure") || lower.contains("password") { return true }
        }
        return false
    }

    private func isInputFromSpark() -> Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.aimo.spark"
    }

    private func getElementRole(_ element: AXUIElement) -> String {
        readStringAttribute(element, kAXRoleAttribute as CFString) ?? "unknown"
    }

    private func axErrorDescription(_ error: AXError) -> String {
        switch error {
        case .success: return "success"
        case .failure: return "failure"
        case .illegalArgument: return "illegalArgument"
        case .invalidUIElement: return "invalidUIElement"
        case .invalidUIElementObserver: return "invalidUIElementObserver"
        case .cannotComplete: return "cannotComplete"
        case .attributeUnsupported: return "attributeUnsupported"
        case .actionUnsupported: return "actionUnsupported"
        case .notificationUnsupported: return "notificationUnsupported"
        case .notImplemented: return "notImplemented"
        case .notificationAlreadyRegistered: return "notificationAlreadyRegistered"
        case .notificationNotRegistered: return "notificationNotRegistered"
        case .apiDisabled: return "apiDisabled"
        case .noValue: return "noValue"
        case .parameterizedAttributeUnsupported: return "parameterizedAttributeUnsupported"
        case .notEnoughPrecision: return "notEnoughPrecision"
        @unknown default: return "unknown(\(error.rawValue))"
        }
    }

    // MARK: - Logging（日志抑制）

    /// 只在 DEBUG 模式打印，且对高频路径做抑制
    private func logAX(_ message: String, suppressable: Bool = false) {
        #if DEBUG
        if suppressable {
            suppressedLogCount += 1
            guard suppressedLogCount % suppressLogEvery == 1 else { return }
            print("[AX] \(message) (×\(suppressedLogCount))")
        } else {
            suppressedLogCount = 0
            print("[AX] \(message)")
        }
        #endif
    }

    // MARK: - Health Check & Auto-Recovery

    private func startHealthCheck() {
        healthCheckTimer = Timer.scheduledTimer(
            withTimeInterval: healthCheckInterval,
            repeats: true
        ) { [weak self] _ in
            self?.performHealthCheck()
        }
    }

    private func stopHealthCheck() {
        healthCheckTimer?.invalidate()
        healthCheckTimer = nil
    }

    private func performHealthCheck() {
        guard isMonitoring else { return }

        let isTimerHealthy = pollingTimer?.isValid == true
        let hasPermission = AXIsProcessTrusted()
        let isHealthy = isTimerHealthy && hasPermission

        if isHealthy {
            lastHealthyTimestamp = Date()
            recoveryAttempts = 0
        } else if let lastHealthy = lastHealthyTimestamp {
            let elapsed = Date().timeIntervalSince(lastHealthy)
            if elapsed >= 5.0, recoveryAttempts < maxRecoveryAttempts {
                print("⚠️ Health check failed (elapsed: \(Int(elapsed))s) — attempting recovery \(recoveryAttempts + 1)/\(maxRecoveryAttempts)")
                attemptRecovery()
            } else if recoveryAttempts >= maxRecoveryAttempts {
                print("❌ Monitoring failed after \(maxRecoveryAttempts) recovery attempts — stopping")
                stopMonitoring()
            }
        }
    }

    private func attemptRecovery() {
        recoveryAttempts += 1

        // 重启轮询
        stopPolling()
        startPolling()

        // 重新附加 AXObserver
        if let app = NSWorkspace.shared.frontmostApplication {
            attachAXObserver(to: app)
        }

        lastHealthyTimestamp = Date()
        print("✅ Recovery attempt \(recoveryAttempts) completed")
    }
}
