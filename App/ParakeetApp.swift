import SwiftUI
import Core
import FluidAudio
import HotKey
import AVFoundation

@main
struct AirakeetApp: App {
    @StateObject private var appController = AppController()
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

private final class MonitorWrapper: @unchecked Sendable {
    var monitor: Any?
}

@MainActor
class AppController: NSObject, ObservableObject, HotkeyManagerDelegate, ASREngineDelegate, AudioRecorderDelegate {
    private var statusBarManager: StatusBarManager?
    private let asrEngine = ASREngine()
    private let recorder = AudioRecorder()
    private let injector = TextInjector()
    private let hotkeyManager = HotkeyManager()
    private let permissions = PermissionsManager()
    
    @Published var lastResult: TranscriptionResult?
    @Published var status: ASREngineStatus = .idle
    @Published var isRecording = false
    @Published var currentPower: Float = 0
    @Published var mode: RecordingMode = .holdToTalk
    @Published var availableDevices: [AVCaptureDevice] = []
    @Published var selectedDeviceID: String?
    
    private var idleTimer: Timer?
    private let idleTimeout: TimeInterval = 300 // 5 minutes
    
    private var transcriptionTask: Task<Void, Never>?
    private let escapeMonitorWrapper = MonitorWrapper()
    
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
        
        // Initialize ASR engine (starts model download/load)
        Task {
            await asrEngine.setDelegate(self)
            do {
                try await asrEngine.ensureInitialized()
                resetIdleTimer()
            } catch {
                print("Failed to initialize ASR: \(error)")
            }
        }
        
        statusBarManager = StatusBarManager(controller: self)
        setupEscapeMonitor()
    }
    
    private func setupEscapeMonitor() {
        // Monitor for Escape key (virtual key code 53)
        escapeMonitorWrapper.monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return }
            if event.keyCode == 53 { // Escape
                Task { @MainActor in
                    if self.isRecording || self.status == .transcribing {
                        print("Escape pressed: Cancelling...")
                        await self.cancel()
                    }
                }
            }
        }
    }
    
    func cancel() async {
        if isRecording {
            _ = try? await recorder.stopRecording()
        }
        
        transcriptionTask?.cancel()
        transcriptionTask = nil
        
        OverlayWindow.hide()
        resetIdleTimer()
        print("Operation cancelled by user.")
    }
    
    func refreshDevices() {
        self.availableDevices = AudioRecorder.availableDevices()
    }
    
    func changeDevice(_ deviceID: String) {
        self.selectedDeviceID = deviceID
        recorder.selectedDeviceID = deviceID
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
            } else if status != .transcribing {
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
        idleTimer?.invalidate()
        
        Task {
            do {
                // Ensure models are loaded before starting
                try await asrEngine.ensureInitialized()
                try recorder.startRecording()
            } catch {
                print("Failed to start recording: \(error)")
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
                
                // Check for cancellation before ASR
                if Task.isCancelled { return }
                
                let result = try await asrEngine.transcribe(samples: samples, audioDuration: duration)
                
                // Check for cancellation after ASR
                if Task.isCancelled { return }
                
                self.lastResult = result
                injector.inject(result.text)
            } catch {
                if !Task.isCancelled {
                    print("Transcription error: \(error)")
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
        Task {
            // Re-transcription logic if needed
        }
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
    
    deinit {
        if let monitor = escapeMonitorWrapper.monitor {
            NSEvent.removeMonitor(monitor)
        }
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
        
        menu.addItem(NSMenuItem(title: "Airakeet", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        
        let modeMenu = NSMenu()
        RecordingMode.allCases.forEach { mode in
            let item = NSMenuItem(title: mode.rawValue, action: #selector(changeMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode
            if mode == controller.mode {
                item.state = .on
            }
            modeMenu.addItem(item)
        }
        
        let modeItem = NSMenuItem(title: "Mode", action: nil, keyEquivalent: "")
        modeItem.submenu = modeMenu
        menu.addItem(modeItem)
        
        // Microphone Selector
        let micMenu = NSMenu()
        controller.refreshDevices()
        controller.availableDevices.forEach { device in
            let item = NSMenuItem(title: device.localizedName, action: #selector(changeDevice(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = device.uniqueID
            if device.uniqueID == controller.selectedDeviceID {
                item.state = .on
            }
            micMenu.addItem(item)
        }
        
        if controller.availableDevices.isEmpty {
            micMenu.addItem(NSMenuItem(title: "No devices found", action: nil, keyEquivalent: ""))
        }
        
        let micItem = NSMenuItem(title: "Microphone", action: nil, keyEquivalent: "")
        micItem.submenu = micMenu
        menu.addItem(micItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let debugItem = NSMenuItem(title: "Open Test/Debug...", action: #selector(openDebug), keyEquivalent: "d")
        debugItem.target = self
        menu.addItem(debugItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusBarItem.menu = menu
    }
    
    @objc func changeMode(_ sender: NSMenuItem) {
        if let mode = sender.representedObject as? RecordingMode {
            controller.changeMode(mode)
            setupMenu() // Refresh checkmarks
        }
    }
    
    @objc func changeDevice(_ sender: NSMenuItem) {
        if let deviceID = sender.representedObject as? String {
            controller.changeDevice(deviceID)
            setupMenu() // Refresh checkmarks
        }
    }
    
    @objc func openDebug() {
        controller.openDebugWindow()
    }
    
    @objc func quit() {
        controller.quit()
    }
}
