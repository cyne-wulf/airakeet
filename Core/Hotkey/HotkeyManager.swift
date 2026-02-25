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
    
    private var globalModifierMonitor: MonitorWrapper?
    private var localModifierMonitor: MonitorWrapper?
    private var shiftFnEngaged = false
    
    public var useShiftFnShortcut: Bool {
        get { UserDefaults.standard.bool(forKey: "useShiftFnShortcut") }
        set {
            UserDefaults.standard.set(newValue, forKey: "useShiftFnShortcut")
            logger.info("Shift+Fn shortcut enabled: \(newValue)")
            if newValue {
                startShiftFnMonitoring()
            } else {
                shiftFnEngaged = false
                stopShiftFnMonitoring()
            }
        }
    }

    public init() {
        setupHandlers()
        if useShiftFnShortcut {
            startShiftFnMonitoring()
        }
    }
    
    private func setupHandlers() {
        KeyboardShortcuts.onKeyDown(for: .toggleAirakeet) { [weak self] in
            self?.handleTrigger()
        }
        
        KeyboardShortcuts.onKeyUp(for: .toggleAirakeet) { [weak self] in
            guard let self = self, self.mode == .holdToTalk else { return }
            self.stopIfRecording()
        }
    }
    
    private func startShiftFnMonitoring() {
        if globalModifierMonitor?.monitor == nil {
            let wrapper = globalModifierMonitor ?? MonitorWrapper()
            wrapper.monitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                guard let self = self else { return }
                Task { @MainActor in
                    self.handleShiftFnFlags(event.modifierFlags)
                }
            }
            globalModifierMonitor = wrapper
        }

        if localModifierMonitor?.monitor == nil {
            let wrapper = localModifierMonitor ?? MonitorWrapper()
            wrapper.monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                guard let self = self else { return event }
                Task { @MainActor in
                    self.handleShiftFnFlags(event.modifierFlags)
                }
                return event
            }
            localModifierMonitor = wrapper
        }
    }

    private func stopShiftFnMonitoring() {
        if let monitor = globalModifierMonitor?.monitor {
            NSEvent.removeMonitor(monitor)
        }
        globalModifierMonitor?.monitor = nil

        if let monitor = localModifierMonitor?.monitor {
            NSEvent.removeMonitor(monitor)
        }
        localModifierMonitor?.monitor = nil
    }
    
    private func handleTrigger() {
        let currentlyRecording = delegate?.isCurrentlyRecording() ?? false
        switch mode {
        case .holdToTalk:
            if !currentlyRecording {
                delegate?.hotkeyDidStart()
            }
        case .toggle:
            if currentlyRecording {
                stopIfRecording()
            } else {
                delegate?.hotkeyDidStart()
            }
        }
    }
    
    private func handleShiftFnFlags(_ flags: NSEvent.ModifierFlags) {
        guard useShiftFnShortcut else { return }

        let maskedFlags = flags.intersection(.deviceIndependentFlagsMask)
        let sanitizedFlags = maskedFlags.subtracting([.capsLock, .numericPad])
        let engaged = sanitizedFlags == [.function, .shift]

        if engaged && !shiftFnEngaged {
            shiftFnEngaged = true
            handleTrigger()
        } else if !engaged && shiftFnEngaged {
            shiftFnEngaged = false
            stopShiftFnIfNeeded()
        }
    }

    private func stopShiftFnIfNeeded() {
        guard mode == .holdToTalk else { return }
        stopIfRecording()
    }
    
    private func stopIfRecording() {
        guard delegate?.isCurrentlyRecording() ?? false else { return }
        delegate?.hotkeyDidStop()
    }

    deinit {
        let global = globalModifierMonitor?.monitor
        let local = localModifierMonitor?.monitor
        if global != nil || local != nil {
            DispatchQueue.main.async {
                if let m = global { NSEvent.removeMonitor(m) }
                if let m = local { NSEvent.removeMonitor(m) }
            }
        }
    }
}
