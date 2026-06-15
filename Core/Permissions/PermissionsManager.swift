import AVFoundation
import Cocoa
import OSLog
import ApplicationServices

@MainActor
public final class PermissionsManager: ObservableObject {
    private let logger = Logger(subsystem: "com.airakeet.app", category: "PermissionsManager")
    
    @Published public var hasMicrophonePermission = false
    @Published public var hasAccessibilityPermission = false
    
    public init() {
        checkAll()
    }
    
    public func checkAll() {
        checkMicrophone()
        checkAccessibility()
    }
    
    public func checkMicrophone() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        let authorized = (status == .authorized)
        if self.hasMicrophonePermission != authorized {
            self.hasMicrophonePermission = authorized
            logger.info("Microphone permission updated: \(authorized)")
        }
    }
    
    public func requestMicrophone() async -> Bool {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        self.hasMicrophonePermission = granted
        if granted {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                NSApp?.activate(ignoringOtherApps: true)
            }
        }
        return granted
    }
    
    public func checkAccessibility() {
        // AXIsProcessTrusted() reads a per-process cache populated at first
        // call, so a grant made while the app is running never flips it until
        // relaunch. An active CGEvent tap is gated by the same Accessibility
        // TCC service but is answered from the live database, so probe it as
        // a fallback when the cached check says no.
        let trusted = AXIsProcessTrusted() || Self.probeAccessibilityViaEventTap()

        if trusted {
            // Remember that this user has granted Accessibility at least once. If a
            // later launch finds it revoked (the silent break an update used to
            // cause), `migrationLikely` uses this to show recovery guidance instead
            // of generic first-run copy. The TCC database itself is SIP-protected
            // and unreadable, so this flag is our only signal.
            UserDefaults.standard.set(true, forKey: Self.accessibilityWasGrantedKey)
        }

        if self.hasAccessibilityPermission != trusted {
            self.hasAccessibilityPermission = trusted
            logger.info("Accessibility permission updated: \(trusted)")
        }
    }

    private static let accessibilityWasGrantedKey = "accessibilityWasGranted"

    /// True when Accessibility is currently missing but was granted before — i.e.
    /// the grant most likely broke because the app's code signature changed across
    /// an update, leaving a stale, ineffective entry in System Settings.
    public var migrationLikely: Bool {
        !hasAccessibilityPermission
            && UserDefaults.standard.bool(forKey: Self.accessibilityWasGrantedKey)
    }

    /// Clears this app's stale Accessibility entry via `tccutil`, then re-prompts.
    /// Saves the user from hunting down and deleting the old entry by hand: after
    /// the reset, granting again adds the current binary cleanly. Only call this
    /// when Accessibility is already non-functional (e.g. `migrationLikely`) —
    /// `tccutil reset` drops any existing grant.
    public func resetAccessibilityEntry() {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.cyne-wulf.airakeet"
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        task.arguments = ["reset", "Accessibility", bundleID]
        do {
            try task.run()
            task.waitUntilExit()
            logger.info("tccutil reset Accessibility for \(bundleID) exited \(task.terminationStatus)")
        } catch {
            logger.error("Failed to run tccutil reset: \(error.localizedDescription)")
        }
        // Re-prompt so the user can add this binary right away. requestAccessibility()
        // also rechecks state shortly after.
        requestAccessibility()
    }

    /// Returns true when the live TCC database grants this process
    /// Accessibility. Creating an active (.defaultTap) tap requires that
    /// service; .listenOnly would test Input Monitoring instead. The tap is
    /// never added to a run loop, so it receives no events, and it is torn
    /// down immediately. Creation does not trigger a permission prompt.
    private static func probeAccessibilityViaEventTap() -> Bool {
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: { _, _, event, _ in Unmanaged.passUnretained(event) },
            userInfo: nil
        ) else {
            return false
        }
        CGEvent.tapEnable(tap: tap, enable: false)
        CFMachPortInvalidate(tap)
        return true
    }
    
    public func requestAccessibility() {
        let promptKey = "AXTrustedCheckOptionPrompt" as CFString
        let options = [promptKey: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        
        // Re-check after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.checkAccessibility()
        }
    }
    
    public func openSystemSettings() {
        if !hasMicrophonePermission {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
            NSWorkspace.shared.open(url)
        } else {
            // Go to Accessibility
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            NSWorkspace.shared.open(url)
        }
        
        // Re-check after returning
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.checkAll()
        }
    }
}
