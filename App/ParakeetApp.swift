import SwiftUI
import Core
import FluidAudio
import AVFoundation
import KeyboardShortcuts
import Combine
import ServiceManagement

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
    let hotkeyManager = HotkeyManager()
    @Published var permissions = PermissionsManager()
    @Published var waveformColor: Color = .blue
    
    var useShiftFnShortcut: Bool {
        hotkeyManager.useShiftFnShortcut
    }
    
    func toggleShiftFnShortcut() {
        hotkeyManager.useShiftFnShortcut.toggle()
        self.objectWillChange.send()
    }
    
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
    private var audioPlayer: AVAudioPlayer?
    @Published var hasLastRecording: Bool = false
    
    override init() {
        super.init()
        loadSettings()
        setup()
    }
    
    private func loadSettings() {
        if let hex = UserDefaults.standard.string(forKey: "waveformColor") {
            waveformColor = Color(hex: hex) ?? .blue
        }
    }
    
    func updateWaveformColor(_ color: Color) {
        self.waveformColor = color
        UserDefaults.standard.set(color.toHex(), forKey: "waveformColor")
    }
    
    private func setup() {
        hotkeyManager.delegate = self
        recorder.delegate = self
        
        // Check if last recording exists on disk
        updateHasLastRecording()
        
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
    
    // MARK: - Launch at Login
    var isStartAtLogin: Bool {
        return SMAppService.mainApp.status == .enabled
    }
    
    func toggleStartAtLogin() {
        do {
            if isStartAtLogin {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            print("Airakeet: Launch at login toggle failed: \(error)")
        }
        // Notify UI to refresh checkmark
        self.objectWillChange.send()
        statusBarManager?.setupMenu()
    }
    
    func updateHasLastRecording() {
        if let url = recorder.getLastRecordingURL() {
            hasLastRecording = FileManager.default.fileExists(atPath: url.path)
        } else {
            hasLastRecording = false
        }
    }
    
    func playLastRecording() {
        guard let url = recorder.getLastRecordingURL() else { return }
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.play()
            print("Airakeet: Playing last recording...")
        } catch {
            print("Airakeet: Playback error: \(error)")
        }
    }
    
    func deleteLastRecording() {
        guard let url = recorder.getLastRecordingURL() else { return }
        try? FileManager.default.removeItem(at: url)
        updateHasLastRecording()
        print("Airakeet: Last recording deleted.")
    }
    
    func saveLastRecording() {
        guard let sourceURL = recorder.getLastRecordingURL() else { return }
        
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.wav]
        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false
        savePanel.title = "Save Recording"
        savePanel.message = "Choose a location to save the audio file."
        savePanel.nameFieldStringValue = "recording_\(Int(Date().timeIntervalSince1970)).wav"
        
        let response = savePanel.runModal()
        if response == .OK, let targetURL = savePanel.url {
            do {
                if FileManager.default.fileExists(atPath: targetURL.path) {
                    try FileManager.default.removeItem(at: targetURL)
                }
                try FileManager.default.copyItem(at: sourceURL, to: targetURL)
                print("Airakeet: Recording saved to \(targetURL.path)")
            } catch {
                print("Airakeet: Save error: \(error)")
            }
        }
    }
    
    func reTranscribeLast() {
        guard let _ = recorder.getLastRecordingURL() else { return }
        transcriptionTask = Task {
            do {
                print("Airakeet: Re-transcribing last recording...")
                status = .transcribing
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                status = .ready
            }
        }
    }
    
    func injectLastResult() {
        if let text = lastResult?.text {
            injector.inject(text)
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
        HotkeySettingsWindow.show(controller: self)
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
                updateHasLastRecording()
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
    
    func openDebugWindow() {
        NSApp.activate(ignoringOtherApps: true)
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
        let hotkeyItem = NSMenuItem(title: "Hotkey & Appearance...", action: #selector(openHotkey), keyEquivalent: "k")
        hotkeyItem.target = self
        menu.addItem(hotkeyItem)
        
        // Start at Login
        let launchItem = NSMenuItem(title: "Start at Login", action: #selector(toggleLaunch), keyEquivalent: "")
        launchItem.target = self
        launchItem.state = controller.isStartAtLogin ? .on : .off
        menu.addItem(launchItem)
        
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
    
    @objc func toggleLaunch() { controller.toggleStartAtLogin() }
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

// MARK: - Color Extensions for Persistence
extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt64 = 0
        
        var r: CGFloat = 0.0
        var g: CGFloat = 0.0
        var b: CGFloat = 0.0
        var a: CGFloat = 1.0
        
        let length = hexSanitized.count
        
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }
        
        if length == 6 {
            r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
            g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
            b = CGFloat(rgb & 0x0000FF) / 255.0
        } else if length == 8 {
            r = CGFloat((rgb & 0xFF000000) >> 24) / 255.0
            g = CGFloat((rgb & 0x00FF0000) >> 16) / 255.0
            b = CGFloat((rgb & 0x0000FF00) >> 8) / 255.0
            a = CGFloat(rgb & 0x000000FF) / 255.0
        } else {
            return nil
        }
        
        self.init(.sRGB, red: Double(r), green: Double(g), blue: Double(b), opacity: Double(a))
    }
    
    func toHex() -> String {
        let nsColor = NSColor(self)
        guard let rgbColor = nsColor.usingColorSpace(.deviceRGB) else {
            return "0000FF"
        }
        let r = Int(rgbColor.redComponent * 255)
        let g = Int(rgbColor.greenComponent * 255)
        let b = Int(rgbColor.blueComponent * 255)
        return String(format: "%02X%02X%02X", r, g, b)
    }
}
