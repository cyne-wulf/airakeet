import AVFoundation
import Cocoa
import OSLog

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
        self.hasMicrophonePermission = (status == .authorized)
        logger.info("Microphone permission: \(status == .authorized)")
    }
    
    public func requestMicrophone() async -> Bool {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        self.hasMicrophonePermission = granted
        return granted
    }
    
    public func checkAccessibility() {
        // AXIsProcessTrustedWithOptions returns true if the app is already trusted
        let promptKey = "AXTrustedCheckOptionPrompt" as CFString
        let options = [promptKey: false] as CFDictionary
        self.hasAccessibilityPermission = AXIsProcessTrustedWithOptions(options)
        logger.info("Accessibility permission: \(self.hasAccessibilityPermission)")
    }
    
    public func requestAccessibility() {
        let promptKey = "AXTrustedCheckOptionPrompt" as CFString
        let options = [promptKey: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
    
    public func openSystemSettings() {
        if !hasMicrophonePermission {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
            NSWorkspace.shared.open(url)
        } else if !hasAccessibilityPermission {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            NSWorkspace.shared.open(url)
        }
    }
}
