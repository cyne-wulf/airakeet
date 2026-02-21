import HotKey
import Foundation
import Cocoa
import OSLog

public enum RecordingMode: String, CaseIterable, Sendable {
    case holdToTalk = "Hold-to-talk"
    case toggle = "Toggle dictation"
}

@MainActor
public final class HotkeyManager {
    private let logger = Logger(subsystem: "com.parakeet.app", category: "HotkeyManager")
    private var hotKey: HotKey?
    public weak var delegate: (any HotkeyManagerDelegate)?
    
    public var mode: RecordingMode = .holdToTalk {
        didSet { 
            logger.info("Recording mode changed to \(self.mode.rawValue)")
            setupHotKey() 
        }
    }
    
    private var isRecording = false
    
    public init() {
        setupHotKey()
    }
    
    public func setupHotKey() {
        // Default: Option + Cmd + R
        // In a real app, this would be customizable
        hotKey = HotKey(key: .r, modifiers: [.command, .option])
        
        hotKey?.keyDownHandler = { [weak self] in
            guard let self = self else { return }
            Task { @MainActor in
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
        }
        
        hotKey?.keyUpHandler = { [weak self] in
            guard let self = self else { return }
            Task { @MainActor in
                if self.mode == .holdToTalk {
                    if self.isRecording {
                        self.isRecording = false
                        self.delegate?.hotkeyDidStop()
                    }
                }
            }
        }
        
        logger.info("Global hotkey registered: Option + Cmd + R")
    }
}

@MainActor
public protocol HotkeyManagerDelegate: AnyObject {
    func hotkeyDidStart()
    func hotkeyDidStop()
}
