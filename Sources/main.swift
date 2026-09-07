import AppKit
import ApplicationServices
import GameController
import CoreHaptics

let completionNotification = Notification.Name("local.dualsense.codexbridge.turnEnded")

// No audio capture: Codex owns the recording UI and uses its selected microphone.
struct Binding {
    let label: String
    let key: CGKeyCode
    let flags: CGEventFlags
}

struct HeldDictationTarget {
    let application: NSRunningApplication
    let keyUp: CGEvent
}

final class ControllerBridge: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let diagnostic = CommandLine.arguments.contains("--diagnose")
    let targetBundle = "com.openai.codex"
    var enabled = true
    var statusItem: NSStatusItem!
    var deviceItem: NSMenuItem!
    var permissionItem: NSMenuItem!
    var lastItem: NSMenuItem!
    var toggleItem: NSMenuItem!
    var hapticsItem: NSMenuItem!
    var reminderItem: NSMenuItem!
    var reminderStatus: NSMenuItem!
    var remindersEnabled = UserDefaults.standard.object(forKey: "remindersEnabled") as? Bool ?? true
    var activeEngines: [CHHapticEngine] = []
    var activePlayers: [CHHapticPatternPlayer] = []
    var recentEvents: [String] = []
    var lastPulseTime = Date.distantPast
    var attached = Set<ObjectIdentifier>()
    var timer: Timer?
    var dictationHold = HoldState<ObjectIdentifier, HeldDictationTarget>()
    var triggers: [ObjectIdentifier: TriggerGesture] = [:]
    var sticks: [ObjectIdentifier: (Float, Float)] = [:]
    var stickTimer: Timer?
    var menuNavigation = false
    var nextStickKeyTime = Date.distantPast
    let conversationLocator = ConversationLocator()

    func log(_ text: String) {
        print(text)
        fflush(stdout)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !diagnostic { makeMenu() }
        if !diagnostic {
            DistributedNotificationCenter.default().addObserver(self, selector: #selector(turnEnded(_:)), name: completionNotification, object: nil, suspensionBehavior: .deliverImmediately)
        }
        GCController.shouldMonitorBackgroundEvents = true
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: .GCControllerDidConnect, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: .GCControllerDidDisconnect, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(frontmostChanged), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        refresh()
        let refreshTimer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(refreshTimer, forMode: .common)
        timer = refreshTimer
        let motionTimer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in self?.moveStick() }
        RunLoop.main.add(motionTimer, forMode: .common)
        stickTimer = motionTimer
        if diagnostic {
            log("Diagnostic mode: no keyboard events will be sent. Listening for 15 seconds.")
            DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
                self.log("Diagnostic complete. Controllers: \(self.attached.count); accessibility: \(AXIsProcessTrusted())")
                NSApp.terminate(nil)
            }
        }
    }

    func makeMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🎮"
        statusItem.button?.toolTip = "DualSense → ChatGPT"
        let menu = NSMenu()
        menu.delegate = self
        deviceItem = menu.addItem(withTitle: "等待手柄…", action: nil, keyEquivalent: "")
        permissionItem = menu.addItem(withTitle: "", action: nil, keyEquivalent: "")
        lastItem = menu.addItem(withTitle: "最近按键：无", action: nil, keyEquivalent: "")
        hapticsItem = menu.addItem(withTitle: "震动：等待手柄", action: nil, keyEquivalent: "")
        reminderStatus = menu.addItem(withTitle: "最近提醒：无", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        toggleItem = menu.addItem(withTitle: "启用按键映射", action: #selector(toggle), keyEquivalent: "")
        toggleItem.target = self
        toggleItem.state = .on
        let permission = menu.addItem(withTitle: "打开辅助功能授权设置…", action: #selector(requestAccessibility), keyEquivalent: "")
        permission.target = self
        menu.addItem(.separator())
        reminderItem = menu.addItem(withTitle: "回合结束时震动提醒", action: #selector(toggleReminders), keyEquivalent: "")
        reminderItem.target = self
        reminderItem.state = remindersEnabled ? .on : .off
        let test = menu.addItem(withTitle: "测试：两次短震动", action: #selector(testRumble), keyEquivalent: "")
        test.target = self
        menu.addItem(.separator())
        for title in ["仅在 ChatGPT 位于前台时生效", "□  按住听写，松开结束（⌃⇧D）", "△  启动语音对话（⌃⇧V）", "×  确认会话选择；平时为回车", "○  取消会话选择；平时为 Esc", "L1 / R1  上一个 / 下一个标签", "R2  轻按松开排队，深按立即发送", "左摇杆  滚动内容；菜单中选择", "方向键  ↑ ↓ ← →", "Options  打开最近会话菜单（⌘⇧P）", "↑ / ↓  选择，× 进入，○ 返回", "暂停映射请使用本菜单的启用开关", "松开 □ 后等待转写，再按 × 发送", "收音由 ChatGPT 选择的麦克风负责"] {
            menu.addItem(withTitle: title, action: nil, keyEquivalent: "")
        }
        menu.addItem(.separator())
        let quit = menu.addItem(withTitle: "退出 DualSense Codex", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        statusItem.menu = menu
    }

    @objc func refresh() {
        let controllers = GCController.controllers().filter { $0.extendedGamepad is GCDualSenseGamepad }
        let ids = Set(controllers.map { ObjectIdentifier($0) })
        for controller in controllers where !attached.contains(ObjectIdentifier(controller)) {
            bind(controller)
            log("Connected: \(controller.vendorName ?? "DualSense")")
        }
        if !attached.subtracting(ids).isEmpty {
            log("Controller disconnected")
        }
        triggers = triggers.filter { ids.contains($0.key) }
        sticks = sticks.filter { ids.contains($0.key) }
        if let hold = dictationHold.active, !ids.contains(hold.owner) { endDictation() }
        attached = ids
        if !diagnostic {
            deviceItem.title = controllers.isEmpty ? "未连接 DualSense" : "已连接：\(controllers.first?.vendorName ?? "DualSense")"
            permissionItem.title = AXIsProcessTrusted() ? "辅助功能：已授权" : "辅助功能：未授权，暂不能控制 ChatGPT"
            hapticsItem.title = controllers.contains { !($0.haptics?.supportedLocalities.isEmpty ?? true) } ? "震动：手柄支持" : "震动：未连接支持的手柄"
            statusItem.button?.title = enabled ? "🎮" : "🎮 ⏸"
        }
    }

    func bind(_ controller: GCController) {
        guard let pad = controller.extendedGamepad else { return }
        controller.handlerQueue = .main
        let owner = ObjectIdentifier(controller)
        var trigger = TriggerGesture()
        _ = trigger.update(pad.rightTrigger.value, allowed: true)
        triggers[owner] = trigger
        pad.rightTrigger.valueChangedHandler = { [weak self] _, value, _ in
            self?.handleTrigger(owner: owner, value: value)
        }
        sticks[owner] = (0, 0)
        pad.leftThumbstick.valueChangedHandler = { [weak self] _, x, y in
            self?.sticks[owner] = (x, y)
        }
        pad.buttonX.pressedChangedHandler = { [weak self] _, _, pressed in
            guard let self else { return }
            if self.diagnostic { self.log(pressed ? "Button: □ down" : "Button: □ up"); return }
            if pressed { self.beginDictation(owner: owner) } else { self.endDictation(owner: owner) }
        }
        connect(pad.buttonY, Binding(label: "△ 语音对话", key: 9, flags: [.maskControl, .maskShift]))
        connect(pad.buttonA, Binding(label: "× 回车", key: 36, flags: []))
        connect(pad.buttonB, Binding(label: "○ Esc", key: 53, flags: []))
        connect(pad.leftShoulder, Binding(label: "L1 上一个标签", key: 33, flags: [.maskCommand, .maskShift]))
        connect(pad.rightShoulder, Binding(label: "R1 下一个标签", key: 30, flags: [.maskCommand, .maskShift]))
        connect(pad.dpad.up, Binding(label: "↑", key: 126, flags: []))
        connect(pad.dpad.down, Binding(label: "↓", key: 125, flags: []))
        connect(pad.dpad.left, Binding(label: "←", key: 123, flags: []))
        connect(pad.dpad.right, Binding(label: "→", key: 124, flags: []))
        // Open ChatGPT's command menu, whose default content includes recent chats.
        // Unlike Control+Tab, this command does not depend on the active tab panel.
        connect(pad.buttonMenu, Binding(label: "Options 最近会话菜单", key: 35, flags: [.maskCommand, .maskShift]))
    }

    func connect(_ button: GCControllerButtonInput, _ binding: Binding) {
        button.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed, let self else { return }
            self.perform(binding)
        }
    }

    func perform(_ binding: Binding) {
        if diagnostic { log("Button: \(binding.label)"); return }
        lastItem.title = "最近按键：\(binding.label)"
        guard enabled else { lastItem.title += "（已暂停）"; return }
        guard let target = NSWorkspace.shared.frontmostApplication,
              target.bundleIdentifier == targetBundle else {
            lastItem.title += "（ChatGPT 不在前台）"
            return
        }
        guard AXIsProcessTrusted() else { lastItem.title += "（需要辅助功能授权）"; return }
        if binding.key == 35 && binding.flags.contains(.maskCommand) {
            menuNavigation = true
            cancelTriggers()
        } else if binding.key == 36 || binding.key == 53 {
            menuNavigation = false
        }
        guard let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: binding.key, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: binding.key, keyDown: false) else {
            lastItem.title += "（创建键盘事件失败）"
            return
        }
        down.flags = binding.flags
        up.flags = binding.flags
        // Deliver a balanced key pair directly to the verified app PID.
        down.postToPid(target.processIdentifier)
        up.postToPid(target.processIdentifier)
    }

    func cancelTriggers() {
        for owner in Array(triggers.keys) { triggers[owner]?.cancel() }
    }

    func focusedElement(_ target: NSRunningApplication) -> AXUIElement? {
        var value: CFTypeRef?
        let app = AXUIElementCreateApplication(target.processIdentifier)
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    func focusedRoles(_ target: NSRunningApplication) -> [String] {
        var element = focusedElement(target)
        var roles: [String] = []
        for _ in 0..<12 {
            guard let current = element else { break }
            var role: CFTypeRef?
            if AXUIElementCopyAttributeValue(current, kAXRoleAttribute as CFString, &role) == .success,
               let name = role as? String { roles.append(name) }
            var parent: CFTypeRef?
            guard AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parent) == .success,
                  let parent, CFGetTypeID(parent) == AXUIElementGetTypeID() else { break }
            element = (parent as! AXUIElement)
        }
        return roles
    }

    func handleTrigger(owner: ObjectIdentifier, value: Float) {
        let target = NSWorkspace.shared.frontmostApplication
        let isTarget = target?.bundleIdentifier == targetBundle
        let roles = isTarget && AXIsProcessTrusted() ? target.map { focusedRoles($0) } ?? [] : []
        let inMenu = menuNavigation || roles.contains { ["AXMenu", "AXMenuItem", "AXSheet", "AXDialog", "AXComboBox"].contains($0) }
        let editable = roles.first.map { ["AXTextArea", "AXTextField"].contains($0) } ?? false
        let allowed = diagnostic || (enabled && target?.bundleIdentifier == targetBundle && AXIsProcessTrusted()
            && !inMenu && editable && dictationHold.active == nil)
        guard let action = triggers[owner]?.update(value, allowed: allowed) else {
            if !diagnostic && value >= 0.18 && !allowed {
                lastItem.title = "R2：请先聚焦 ChatGPT 输入框，并关闭菜单、结束听写"
            }
            return
        }
        // This user's composer uses Enter to queue; Command+Enter steers a running turn.
        // With no active turn, ChatGPT handles either as a normal submission.
        perform(Binding(label: action == .queue ? "R2 轻按：排队发送" : "R2 深按：立即发送",
                        key: 36, flags: action == .queue ? [] : .maskCommand))
    }

    func moveStick() {
        guard enabled, !diagnostic, let target = NSWorkspace.shared.frontmostApplication,
              target.bundleIdentifier == targetBundle, AXIsProcessTrusted(),
              let stick = sticks.values.max(by: { max(abs($0.0), abs($0.1)) < max(abs($1.0), abs($1.1)) }) else { return }
        let (x, y) = stick
        let amount = max(abs(x), abs(y))
        guard amount > 0.22 else { nextStickKeyTime = .distantPast; return }
        let roles = focusedRoles(target)
        let inMenu = StickNavigation.mode(roles: roles, openedWithOptions: menuNavigation) == .menu
        if !inMenu { menuNavigation = false }
        if inMenu {
            guard Date() >= nextStickKeyTime else { return }
            let first = nextStickKeyTime == .distantPast
            nextStickKeyTime = Date().addingTimeInterval(first ? 0.32 : 0.16)
            let key: CGKeyCode = abs(y) >= abs(x) ? (y > 0 ? 126 : 125) : (x > 0 ? 124 : 123)
            perform(Binding(label: String(format: "左摇杆 %.2f / %.2f：菜单选择", x, y), key: key, flags: []))
            return
        }
        func pixels(_ value: Float) -> Int32 {
            guard abs(value) > 0.22 else { return 0 }
            let speed = pow((Double(abs(value)) - 0.22) / 0.78, 1.5) * 42
            return Int32(max(1, speed)) * (value > 0 ? 1 : -1)
        }
        guard let source = CGEventSource(stateID: .privateState),
              let scroll = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2,
                                   wheel1: pixels(y), wheel2: -pixels(x), wheel3: 0) else { return }
        guard let point = conversationLocator.point(in: target) else {
            lastItem.title = "左摇杆：请先点击对话输入框，以定位聊天内容区"
            return
        }
        scroll.location = point
        // Scroll wheels need WindowServer hit testing to reach the view under
        // the event location. PID-only posting can leave the NSEvent without
        // a destination window. This does not move the physical mouse cursor.
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier else { return }
        lastItem.title = String(format: "左摇杆 %.2f / %.2f：滚动聊天内容", x, y)
        scroll.post(tap: .cghidEventTap)
    }

    @objc func toggle() {
        endDictation()
        cancelTriggers()
        menuNavigation = false
        enabled.toggle()
        toggleItem?.state = enabled ? .on : .off
        refresh()
    }

    func menuWillOpen(_ menu: NSMenu) { refresh() }

    @objc func frontmostChanged() {
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier != targetBundle {
            endDictation()
            cancelTriggers()
            menuNavigation = false
            sticks = sticks.mapValues { _ in (0, 0) }
            conversationLocator.reset()
        }
    }

    func beginDictation(owner: ObjectIdentifier) {
        guard dictationHold.active == nil else { return }
        lastItem.title = "最近按键：□ 按下"
        guard enabled else { lastItem.title += "（已暂停）"; return }
        guard let target = NSWorkspace.shared.frontmostApplication,
              target.bundleIdentifier == targetBundle else {
            lastItem.title += "（ChatGPT 不在前台）"; return
        }
        guard AXIsProcessTrusted() else { lastItem.title += "（需要辅助功能授权）"; return }
        guard let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 2, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 2, keyDown: false) else {
            lastItem.title += "（创建键盘事件失败）"; return
        }
        down.flags = [.maskControl, .maskShift]
        up.flags = [.maskControl, .maskShift]
        guard dictationHold.begin(owner: owner, destination: HeldDictationTarget(application: target, keyUp: up)) else { return }
        // ChatGPT handles this accelerator as push-to-talk. Do not emit keyUp here.
        down.postToPid(target.processIdentifier)
        lastItem.title = "最近按键：□ 已发送按下，松开结束听写"
    }

    func endDictation(owner: ObjectIdentifier? = nil) {
        guard let destination = dictationHold.end(owner: owner) else { return }
        // Release the original app even when focus has changed. Never send it
        // to an unrelated frontmost app or a reused PID from a terminated app.
        if !destination.application.isTerminated {
            destination.keyUp.postToPid(destination.application.processIdentifier)
        }
        lastItem?.title = "最近按键：□ 已松开，等待 ChatGPT 转写"
    }

    @objc func toggleReminders() {
        remindersEnabled.toggle()
        UserDefaults.standard.set(remindersEnabled, forKey: "remindersEnabled")
        reminderItem.state = remindersEnabled ? .on : .off
    }

    @objc func turnEnded(_ notification: Notification) {
        // Do not interpret or retain prompt text. Only use an opaque event ID.
        guard remindersEnabled, let event = notification.object as? String,
              event.count <= 512, !recentEvents.contains(event) else { return }
        recentEvents.append(event)
        if recentEvents.count > 100 { recentEvents.removeFirst() }
        pulse()
    }

    @objc func testRumble() { pulse() }

    func pulse() {
        // Coalesce bursts from concurrent tasks; never queue stale reminders.
        guard Date().timeIntervalSince(lastPulseTime) >= 2 else { return }
        lastPulseTime = Date()
        let controllers = GCController.controllers().filter { $0.extendedGamepad is GCDualSenseGamepad }
        var played = false
        for controller in controllers {
            guard let haptics = controller.haptics, !haptics.supportedLocalities.isEmpty else { continue }
            let locality: GCHapticsLocality = haptics.supportedLocalities.contains(.handles) ? .handles : .default
            guard haptics.supportedLocalities.contains(locality), let engine = haptics.createEngine(withLocality: locality) else { continue }
            do {
                try engine.start()
                let events = [0.0, 0.35].map { time in
                    CHHapticEvent(eventType: .hapticContinuous,
                                  parameters: [CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.65)],
                                  relativeTime: time, duration: 0.18)
                }
                let player = try engine.makePlayer(with: CHHapticPattern(events: events, parameters: []))
                try player.start(atTime: CHHapticTimeImmediate)
                activeEngines.append(engine)
                activePlayers.append(player)
                played = true
            } catch {
                engine.stop(completionHandler: nil)
                log("Rumble failed: \(error)")
            }
        }
        reminderStatus.title = played ? "最近提醒：已发送两次短震动" : "最近提醒：未能发送，检查手柄连接"
        log(played ? "Rumble: two-pulse command accepted" : "Rumble: unavailable")
        // Keep the players alive until the pattern ends, then release hardware.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self else { return }
            for engine in self.activeEngines { engine.stop(completionHandler: nil) }
            self.activePlayers.removeAll()
            self.activeEngines.removeAll()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        endDictation()
        for engine in activeEngines { engine.stop(completionHandler: nil) }
        DistributedNotificationCenter.default().removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func quitApp() { NSApp.terminate(nil) }
}

let application = NSApplication.shared
application.setActivationPolicy(.accessory)
let delegate = ControllerBridge()
application.delegate = delegate
application.run()
