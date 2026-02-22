import KeyboardShortcuts
import Foundation
import Cocoa
import OSLog

public enum RecordingMode: String, CaseIterable, Sendable {
    case holdToTalk = "Hold-to-talk"
    case toggle = "Toggle dictation"
}

@MainActor
public protocol HotkeyManagerDelegate: AnyObject {
    func hotkeyDidStart()
    func hotkeyDidStop()
    func isCurrentlyRecording() -> Bool
}

@MainActor
public final class HotkeyManager {
    private let logger = Logger(subsystem: "com.airakeet.app", category: "HotkeyManager")
    public weak var delegate: (any HotkeyManagerDelegate)?
    
    public var mode: RecordingMode = .toggle {
        didSet { 
            logger.info("Recording mode changed to \(self.mode.rawValue)")
        }
    }
    
    // To prevent double-firing
    private var lastEventTime: Date = Date.distantPast
    private let debounceInterval: TimeInterval = 0.3
    
    public init() {
        setupHandlers()
    }
    
    private func setupHandlers() {
        KeyboardShortcuts.onKeyDown(for: .toggleAirakeet) { [weak self] in
            guard let self = self else { return }
            
            let now = Date()
            if now.timeIntervalSince(self.lastEventTime) < self.debounceInterval {
                return
            }
            self.lastEventTime = now
            
            let currentlyRecording = self.delegate?.isCurrentlyRecording() ?? false
            
            if self.mode == .holdToTalk {
                if !currentlyRecording {
                    self.delegate?.hotkeyDidStart()
                }
            } else { // Toggle mode
                if currentlyRecording {
                    self.delegate?.hotkeyDidStop()
                } else {
                    self.delegate?.hotkeyDidStart()
                }
            }
        }
        
        KeyboardShortcuts.onKeyUp(for: .toggleAirakeet) { [weak self] in
            guard let self = self else { return }
            
            if self.mode == .holdToTalk {
                if self.delegate?.isCurrentlyRecording() ?? false {
                    self.delegate?.hotkeyDidStop()
                }
            }
        }
    }
}
