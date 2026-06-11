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

        if self.hasAccessibilityPermission != trusted {
            self.hasAccessibilityPermission = trusted
            logger.info("Accessibility permission updated: \(trusted)")
        }
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
