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
        return granted
    }
    
    public func checkAccessibility() {
        // Use AXIsProcessTrusted() directly as the source of truth
        let trusted = AXIsProcessTrusted()
        
        if self.hasAccessibilityPermission != trusted {
            self.hasAccessibilityPermission = trusted
            logger.info("Accessibility permission updated: \(trusted)")
        }
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
