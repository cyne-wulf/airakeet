import Cocoa
import OSLog

public final class TextInjector {
    private let logger = Logger(subsystem: "com.airakeet.app", category: "TextInjector")
    
    public init() {}
    
    public func inject(_ text: String) {
        logger.info("Injecting text: \"\(text)\"")
        
        let pasteboard = NSPasteboard.general
        let previousContent = pasteboard.string(forType: .string)
        
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString(text, forType: .string)
        
        // Synthesize Cmd+V
        let src = CGEventSource(stateID: .combinedSessionState)
        let vDown = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true) // 0x09 is 'V'
        let vUp = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
        
        vDown?.flags = .maskCommand
        vUp?.flags = .maskCommand
        
        vDown?.post(tap: .cghidEventTap)
        vUp?.post(tap: .cghidEventTap)
        
        // Restore pasteboard after a delay (optional, but nice)
        if let prev = previousContent {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let pb = NSPasteboard.general
                pb.declareTypes([.string], owner: nil)
                pb.setString(prev, forType: .string)
            }
        }
    }
}
