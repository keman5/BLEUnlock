import Cocoa
import ApplicationServices
import Darwin

enum AuthorizationPromptPolicy {
    static func requester(in text: String) -> String? {
        let patterns = [
            #"由\s*[“"]([^”"]+)[”"]"#,
            #"(?i)\bby\s*[“"]([^”"]+)[”"]"#,
            #"^[“"]([^”"]+)[”"]"#
        ]
        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = expression.firstMatch(in: text, range: range),
                  let nameRange = Range(match.range(at: 1), in: text) else { continue }
            let name = text[nameRange].trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { return name }
        }
        return nil
    }

    static func allows(_ requester: String?, allowedNames: [String]) -> Bool {
        guard !allowedNames.isEmpty else { return true }
        guard let requester else { return false }
        return allowedNames.contains { $0.compare(requester, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
    }
}

final class AuthorizationPromptMonitor {
    private let isEligible: () -> Bool
    private let password: () -> String?
    private let preferences: UserDefaults
    private var timer: Timer?
    private var lastWindow: AXUIElement?
    private var lastAttemptAt = Date.distantPast

    init(preferences: UserDefaults, isEligible: @escaping () -> Bool, password: @escaping () -> String?) {
        self.preferences = preferences
        self.isEligible = isEligible
        self.password = password
    }

    func refresh() {
        guard preferences.bool(forKey: "autoApproveAuthorization") else {
            timer?.invalidate()
            timer = nil
            return
        }
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.check() }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func check() {
        guard preferences.bool(forKey: "autoApproveAuthorization"), isEligible(),
              AXIsProcessTrusted(), let prompt = AuthorizationPrompt.current() else { return }
        let allowed = preferences.stringArray(forKey: "authorizationAllowedApps") ?? []
        guard AuthorizationPromptPolicy.allows(prompt.requester, allowedNames: allowed) else { return }
        if let lastWindow, CFEqual(lastWindow, prompt.window), Date().timeIntervalSince(lastAttemptAt) < 60 {
            return
        }
        guard let password = password(), !password.isEmpty, isEligible() else { return }
        lastWindow = prompt.window
        lastAttemptAt = Date()

        let source = CGEventSource(stateID: .hidSystemState)
        let characters = Array(password.utf16)
        for start in stride(from: 0, to: characters.count, by: 20) {
            guard isEligible(), prompt.isStillFocused() else { return }
            let chunk = Array(characters[start..<min(start + 20, characters.count)])
            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 49, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 49, keyDown: false) else { return }
            chunk.withUnsafeBufferPointer { buffer in
                keyDown.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
            }
            keyDown.postToPid(prompt.pid)
            keyUp.postToPid(prompt.pid)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, self.preferences.bool(forKey: "autoApproveAuthorization"),
                  self.isEligible(), prompt.isStillFocused(),
                  AuthorizationPromptPolicy.allows(
                    prompt.requester,
                    allowedNames: self.preferences.stringArray(forKey: "authorizationAllowedApps") ?? []
                  ) else { return }
            if AXUIElementPerformAction(prompt.approveButton, kAXPressAction as CFString) != .success {
                CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: true)?.postToPid(prompt.pid)
                CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: false)?.postToPid(prompt.pid)
            }
        }
    }
}

private struct AuthorizationPrompt {
    let pid: pid_t
    let window: AXUIElement
    let approveButton: AXUIElement
    let requester: String?

    static func current() -> AuthorizationPrompt? {
        let system = AXUIElementCreateSystemWide()
        guard let focused = element(system, kAXFocusedUIElementAttribute as String) else { return nil }
        var pid: pid_t = 0
        guard AXUIElementGetPid(focused, &pid) == .success,
              isSystemAuthorizationService(pid),
              value(focused, kAXSubroleAttribute as String) as? String == kAXSecureTextFieldSubrole as String else {
            return nil
        }
        let application = AXUIElementCreateApplication(pid)
        guard let window = element(focused, kAXWindowAttribute as String)
            ?? element(application, kAXFocusedWindowAttribute as String) else { return nil }

        var messages: [String] = []
        var approveButton: AXUIElement?
        var pending = [window]
        var inspected = 0
        while !pending.isEmpty && inspected < 80 {
            let element = pending.removeLast()
            inspected += 1
            let role = value(element, kAXRoleAttribute as String) as? String
            let title = value(element, kAXTitleAttribute as String) as? String
            if role == kAXButtonRole as String, let title,
               ["允许访问", "允许", "Allow Access", "Allow"].contains(title) {
                approveButton = element
            } else if role == kAXStaticTextRole as String,
                      let text = value(element, kAXValueAttribute as String) as? String {
                messages.append(text)
            } else if role == kAXWindowRole as String, let title {
                messages.append(title)
            }
            if let children = value(element, kAXChildrenAttribute as String) as? [AXUIElement] {
                pending.append(contentsOf: children)
            }
        }
        guard let approveButton else { return nil }
        let requester = messages.compactMap(AuthorizationPromptPolicy.requester).first
        return AuthorizationPrompt(pid: pid, window: window, approveButton: approveButton, requester: requester)
    }

    func isStillFocused() -> Bool {
        let system = AXUIElementCreateSystemWide()
        guard let focused = Self.element(system, kAXFocusedUIElementAttribute as String),
              Self.value(focused, kAXSubroleAttribute as String) as? String == kAXSecureTextFieldSubrole as String else { return false }
        var focusedPID: pid_t = 0
        guard AXUIElementGetPid(focused, &focusedPID) == .success, focusedPID == pid else { return false }
        let application = AXUIElementCreateApplication(pid)
        guard let activeWindow = Self.element(focused, kAXWindowAttribute as String)
            ?? Self.element(application, kAXFocusedWindowAttribute as String) else { return false }
        return CFEqual(activeWindow, window)
    }

    private static func value(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var result: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, key as CFString, &result) == .success ? result : nil
    }

    private static func element(_ owner: AXUIElement, _ key: String) -> AXUIElement? {
        guard let result = value(owner, key), CFGetTypeID(result) == AXUIElementGetTypeID() else { return nil }
        return (result as! AXUIElement)
    }

    private static func isSystemAuthorizationService(_ pid: pid_t) -> Bool {
        var path = [CChar](repeating: 0, count: 4096)
        let length = path.withUnsafeMutableBufferPointer {
            proc_pidpath(pid, $0.baseAddress, UInt32($0.count))
        }
        return length > 0 && String(cString: path)
            == "/System/Library/CoreServices/AuthorizationPromptService.app/Contents/MacOS/AuthorizationPromptService"
    }
}
