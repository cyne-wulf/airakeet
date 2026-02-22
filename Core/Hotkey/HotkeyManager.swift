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
    
    private var isRecording = false
    
    public init() {
        setupHandlers()
    }
    
    private func setupHandlers() {
        KeyboardShortcuts.onKeyDown(for: .toggleAirakeet) { [weak self] in
            guard let self = self else { return }
            
            if self.mode == .holdToTalk {
                if !self.isRecording {
                    self.isRecording = true
                    self.delegate?.hotkeyDidStart()
                }
            } else { // Toggle mode
                if self.isRecording {
                    self.isRecording = false
                    self.delegate?.hotkeyDidStop()
                } else {
                    self.isRecording = true
                    self.delegate?.hotkeyDidStart()
                }
            }
        }
        
        KeyboardShortcuts.onKeyUp(for: .toggleAirakeet) { [weak self] in
            guard let self = self else { return }
            
            if self.mode == .holdToTalk {
                if self.isRecording {
                    self.isRecording = false
                    self.delegate?.hotkeyDidStop()
                }
            }
        }
    }
}
