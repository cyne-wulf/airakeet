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

private final class MonitorWrapper: @unchecked Sendable {
    var monitor: Any?
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
    private let monitorWrapper = MonitorWrapper()
    
    public var useShiftFnShortcut: Bool {
        get { UserDefaults.standard.bool(forKey: "useShiftFnShortcut") }
        set { 
            UserDefaults.standard.set(newValue, forKey: "useShiftFnShortcut")
            logger.info("Shift+Fn shortcut enabled: \(newValue)")
        }
    }
    
    public init() {
        setupHandlers()
        setupModifierMonitor()
    }
    
    private func setupHandlers() {
        KeyboardShortcuts.onKeyDown(for: .toggleAirakeet) { [weak self] in
            self?.handleTrigger()
        }
        
        KeyboardShortcuts.onKeyUp(for: .toggleAirakeet) { [weak self] in
            if self?.mode == .holdToTalk {
                self?.stop()
            }
        }
    }
    
    private func setupModifierMonitor() {
        monitorWrapper.monitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self = self, self.useShiftFnShortcut else { return }
            
            let flags = event.modifierFlags
            let isFn = flags.contains(.function)
            let isShift = flags.contains(.shift)
            
            if isFn && isShift {
                Task { @MainActor in
                    self.handleTrigger()
                }
            }
        }
    }
    
    private func handleTrigger() {
        if mode == .holdToTalk {
            if !isRecording {
                start()
            }
        } else { // Toggle
            if isRecording {
                stop()
            } else {
                start()
            }
        }
    }
    
    private func start() {
        isRecording = true
        delegate?.hotkeyDidStart()
    }
    
    private func stop() {
        isRecording = false
        delegate?.hotkeyDidStop()
    }
    
    deinit {
        if let monitor = monitorWrapper.monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
