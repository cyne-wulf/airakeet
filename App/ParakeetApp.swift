import SwiftUI
import Core
import FluidAudio
import HotKey
import AVFoundation
import KeyboardShortcuts
import Combine

@main
struct AirakeetApp: App {
    @StateObject private var appController = AppController()
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
class AppController: NSObject, ObservableObject, HotkeyManagerDelegate, ASREngineDelegate, AudioRecorderDelegate {
    var statusBarManager: StatusBarManager?
    private let asrEngine = ASREngine()
    private let recorder = AudioRecorder()
    private let injector = TextInjector()
    private let hotkeyManager = HotkeyManager()
    @Published var permissions = PermissionsManager()
    
    @Published var lastResult: TranscriptionResult?
    @Published var status: ASREngineStatus = .idle
    @Published var isRecording = false
    @Published var currentPower: Float = 0
    @Published var mode: RecordingMode = .toggle
    @Published var availableDevices: [AVCaptureDevice] = []
    @Published var selectedDeviceID: String?
    
    private var idleTimer: Timer?
    private let idleTimeout: TimeInterval = 300 // 5 minutes
    
    private var transcriptionTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    
    override init() {
        super.init()
        setup()
    }
    
    private func setup() {
        hotkeyManager.delegate = self
        recorder.delegate = self
        
        // Load initial devices
        self.availableDevices = AudioRecorder.availableDevices()
        self.selectedDeviceID = AVCaptureDevice.default(for: .audio)?.uniqueID
        
        // Set default hotkey
        if KeyboardShortcuts.getShortcut(for: .toggleAirakeet) == nil {
            KeyboardShortcuts.setShortcut(KeyboardShortcuts.Shortcut(.backtick, modifiers: [.function]), for: .toggleAirakeet)
        }
        
        // Initialize ASR engine
        Task {
            await asrEngine.setDelegate(self)
            do {
                try await asrEngine.ensureInitialized()
                resetIdleTimer()
            } catch {
                print("Airakeet: ASR Init error: \(error)")
            }
        }
        
        statusBarManager = StatusBarManager(controller: self)
        
        // Reactive Menu Refresh
        permissions.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.statusBarManager?.setupMenu()
            }
            .store(in: &cancellables)
            
        // Frequent polling for permissions (1s)
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.permissions.checkAll()
            }
        }
    }
    
    func refreshDevices() {
        self.availableDevices = AudioRecorder.availableDevices()
    }
    
    func changeDevice(_ deviceID: String) {
        self.selectedDeviceID = deviceID
        recorder.selectedDeviceID = deviceID
    }
    
    func openHotkeySettings() {
        HotkeySettingsWindow.show()
    }
    
    private func resetIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: idleTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor in
                await self?.asrEngine.unload()
            }
        }
    }
    
    // MARK: - AudioRecorderDelegate
    nonisolated func audioRecorderDidUpdateRecordingState(_ isRecording: Bool) {
        Task { @MainActor in
            self.isRecording = isRecording
            if isRecording {
                OverlayWindow.show(view: AnyView(RecordingOverlayView(controller: self)))
            } else if self.status != .transcribing {
                OverlayWindow.hide()
            }
        }
    }
    
    nonisolated func audioRecorderDidUpdatePower(_ power: Float) {
        Task { @MainActor in
            self.currentPower = power
        }
    }
    
    // MARK: - HotkeyManagerDelegate
    func hotkeyDidStart() {
        startRecording()
    }
    
    func hotkeyDidStop() {
        stopRecording()
    }
    
    func isCurrentlyRecording() -> Bool {
        return self.isRecording
    }
    
    // MARK: - ASREngineDelegate
    func asrEngineDidUpdateStatus(_ status: ASREngineStatus) {
        self.status = status
        if status == .ready && !isRecording {
            OverlayWindow.hide()
        } else if status == .transcribing {
            OverlayWindow.show(view: AnyView(RecordingOverlayView(controller: self)))
        }
    }
    
    // MARK: - Actions
    func startRecording() {
        guard !isRecording else { return }
        
        if !permissions.hasMicrophonePermission || !permissions.hasAccessibilityPermission {
            openDebugWindow()
            return
        }
        
        idleTimer?.invalidate()
        
        Task {
            do {
                try await asrEngine.ensureInitialized()
                try recorder.startRecording()
            } catch {
                print("Airakeet: Start error: \(error)")
                resetIdleTimer()
                OverlayWindow.hide()
            }
        }
    }
    
    func startManualRecording() {
        startRecording()
    }
    
    func stopRecording() {
        transcriptionTask = Task {
            defer { 
                resetIdleTimer() 
                transcriptionTask = nil
            }
            
            do {
                let (samples, duration) = try await recorder.stopRecording()
                if Task.isCancelled { return }
                
                let result = try await asrEngine.transcribe(samples: samples, audioDuration: duration)
                if Task.isCancelled { return }
                
                self.lastResult = result
                injector.inject(result.text)
            } catch {
                if !Task.isCancelled {
                    print("Airakeet: Transcription error: \(error)")
                }
                OverlayWindow.hide()
            }
        }
    }
    
    func changeMode(_ newMode: RecordingMode) {
        self.mode = newMode
        hotkeyManager.mode = newMode
    }
    
    func reTranscribeLast() {
        guard let _ = recorder.getLastRecordingURL() else { return }
    }
    
    func injectLastResult() {
        if let text = lastResult?.text {
            injector.inject(text)
        }
    }
    
    func openDebugWindow() {
        DebugWindow.show(controller: self)
    }
    
    func quit() {
        NSApplication.shared.terminate(nil)
    }
}

@MainActor
class StatusBarManager {
    private var statusBarItem: NSStatusItem
    private let controller: AppController
    
    init(controller: AppController) {
        self.controller = controller
        self.statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusBarItem.button {
            button.image = NSImage(systemSymbolName: "waveform.circle", accessibilityDescription: "Airakeet")
        }
        
        setupMenu()
    }
    
    func setupMenu() {
        let menu = NSMenu()
        
        // Title
        let titleItem = NSMenuItem(title: "Airakeet", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // --- Permissions Section ---
        let micOk = controller.permissions.hasMicrophonePermission
        let accOk = controller.permissions.hasAccessibilityPermission
        
        let micStatusItem = NSMenuItem(title: micOk ? "● Microphone: Granted" : "○ Microphone: Missing", action: nil, keyEquivalent: "")
        micStatusItem.isEnabled = false
        menu.addItem(micStatusItem)
        
        let accStatusItem = NSMenuItem(title: accOk ? "● Accessibility: Granted" : "○ Accessibility: Missing", action: nil, keyEquivalent: "")
        accStatusItem.isEnabled = false
        menu.addItem(accStatusItem)
        
        if !micOk || !accOk {
            let grantItem = NSMenuItem(title: "Grant Permissions...", action: #selector(openDebug), keyEquivalent: "")
            grantItem.target = self
            menu.addItem(grantItem)
        }
        
        menu.addItem(NSMenuItem.separator())
        
        // --- Configuration Section ---
        let hotkeyItem = NSMenuItem(title: "Set Hotkey...", action: #selector(openHotkey), keyEquivalent: "k")
        hotkeyItem.target = self
        menu.addItem(hotkeyItem)
        
        let modeMenu = NSMenu()
        RecordingMode.allCases.forEach { mode in
            let item = NSMenuItem(title: mode.rawValue, action: #selector(changeMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode
            if mode == controller.mode { item.state = .on }
            modeMenu.addItem(item)
        }
        
        let modeItem = NSMenuItem(title: "Mode", action: nil, keyEquivalent: "")
        modeItem.submenu = modeMenu
        menu.addItem(modeItem)
        
        // Microphone Selector
        let micSelectorMenu = NSMenu()
        controller.refreshDevices()
        controller.availableDevices.forEach { device in
            let item = NSMenuItem(title: device.localizedName, action: #selector(changeDevice(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = device.uniqueID
            if device.uniqueID == controller.selectedDeviceID { item.state = .on }
            micSelectorMenu.addItem(item)
        }
        
        if controller.availableDevices.isEmpty {
            micSelectorMenu.addItem(NSMenuItem(title: "No devices found", action: nil, keyEquivalent: ""))
        }
        
        let micSelectorItem = NSMenuItem(title: "Input Source", action: nil, keyEquivalent: "")
        micSelectorItem.submenu = micSelectorMenu
        menu.addItem(micSelectorItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // --- Debug & App Section ---
        let debugItem = NSMenuItem(title: "Open Test/Debug...", action: #selector(openDebug), keyEquivalent: "d")
        debugItem.target = self
        menu.addItem(debugItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusBarItem.menu = menu
    }
    
    @objc func openHotkey() { controller.openHotkeySettings() }
    @objc func changeMode(_ sender: NSMenuItem) {
        if let mode = sender.representedObject as? RecordingMode {
            controller.changeMode(mode)
            setupMenu()
        }
    }
    @objc func changeDevice(_ sender: NSMenuItem) {
        if let deviceID = sender.representedObject as? String {
            controller.changeDevice(deviceID)
            setupMenu()
        }
    }
    @objc func openDebug() { controller.openDebugWindow() }
    @objc func quit() { controller.quit() }
}
