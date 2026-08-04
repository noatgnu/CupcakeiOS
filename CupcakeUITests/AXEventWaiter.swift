#if os(macOS)
import ApplicationServices
import Foundation

final class AXEventWaiter {
    private let pid: pid_t

    init(pid: pid_t) {
        self.pid = pid
    }

    func waitForDestruction(ofIdentifier identifier: String, timeout: TimeInterval) -> Bool {
        let appElement = AXUIElementCreateApplication(pid)
        guard let target = Self.findElement(identifier: identifier, root: appElement) else {
            return true
        }
        return Self.waitForNotification(kAXUIElementDestroyedNotification, pid: pid, element: target, timeout: timeout)
    }

    private static func findElement(identifier: String, root: AXUIElement, depth: Int = 0) -> AXUIElement? {
        guard depth < 40 else { return nil }

        var idValue: AnyObject?
        if AXUIElementCopyAttributeValue(root, kAXIdentifierAttribute as CFString, &idValue) == .success,
           let idString = idValue as? String, idString == identifier {
            return root
        }

        var childrenValue: AnyObject?
        guard AXUIElementCopyAttributeValue(root, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let children = childrenValue as? [AXUIElement] else {
            return nil
        }
        for child in children {
            if let found = findElement(identifier: identifier, root: child, depth: depth + 1) {
                return found
            }
        }
        return nil
    }

    private final class FireBox {
        var fired = false
    }

    private static func waitForNotification(_ name: String, pid: pid_t, element: AXUIElement, timeout: TimeInterval) -> Bool {
        var observer: AXObserver?
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            let box = Unmanaged<FireBox>.fromOpaque(refcon).takeUnretainedValue()
            box.fired = true
            CFRunLoopStop(CFRunLoopGetCurrent())
        }

        guard AXObserverCreate(pid, callback, &observer) == .success, let observer else {
            return false
        }

        let box = FireBox()
        let refcon = Unmanaged.passUnretained(box).toOpaque()
        guard AXObserverAddNotification(observer, element, name as CFString, refcon) == .success else {
            return false
        }

        let source = AXObserverGetRunLoopSource(observer)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .defaultMode)
        defer {
            AXObserverRemoveNotification(observer, element, name as CFString)
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .defaultMode)
        }

        let deadline = Date().addingTimeInterval(timeout)
        while !box.fired {
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 { break }
            CFRunLoopRunInMode(.defaultMode, remaining, true)
        }
        return box.fired
    }
}
#endif
