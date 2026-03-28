import SwiftUI
import AppKit
import Core
import FluidAudio
import AVFoundation
import KeyboardShortcuts
import Combine
import ServiceManagement
import UniformTypeIdentifiers
import Carbon.HIToolbox

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
    struct AudioDeviceInfo: Identifiable, Equatable, Sendable {
        let uniqueID: String
        let localizedName: String
        var id: String { uniqueID }
    }
    
    var statusBarManager: StatusBarManager?
    private let asrEngine = ASREngine()
    private let recorder = AudioRecorder()
    private let injector = TextInjector()
    private let updateManager = UpdateManager(owner: "cyne-wulf", repo: "airakeet")
    let hotkeyManager = HotkeyManager()
    @Published var permissions = PermissionsManager()
    @Published var waveformColor: Color = .blue
    @Published var updateStatus: UpdateStatus = .idle
    @Published var latestRelease: ReleaseInfo?
    
    var useShiftFnShortcut: Bool {
        hotkeyManager.useShiftFnShortcut
    }
    
    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }
    
    var updateMenuTitle: String {
        updateStatus.menuTitle(currentVersion: currentVersion)
    }
    
    func toggleShiftFnShortcut() {
        hotkeyManager.useShiftFnShortcut.toggle()
        self.objectWillChange.send()
    }
    
    @Published var lastResult: TranscriptionResult?
    @Published var status: ASREngineStatus = .idle
    @Published var loadProgress: Double = 0
    @Published var loadLog: String = ""
    @Published var isRecording = false
    @Published var currentPower: Float = 0
    @Published var mode: RecordingMode = .toggle
    @Published var availableDevices: [AudioDeviceInfo] = []
    @Published var selectedDeviceID: String?
    
    private var idleTimer: Timer?
    private var permissionTimer: Timer?
    private let idleTimeout: TimeInterval = 300 // 5 minutes
    private let shortClipThreshold: TimeInterval = 1.0
    private var lastClipDuration: TimeInterval?
    private var overlayMessageTask: Task<Void, Never>?
    private var isPresentingSpecificErrorOverlay = false
    
    private var escapeCancelMonitor: Any?
    private var escapeCancelLocalMonitor: Any?
    
    private var isEscapeCancellationInFlight = false
    
    private var startTask: Task<Void, Never>?
    private var transcriptionTask: Task<Void, Never>?
    private var updateTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var audioPlayer: AVAudioPlayer?
    @Published var hasLastRecording: Bool = false
    private var pendingRelaunchURL: URL?
    private var deferredInitializationTask: Task<Void, Never>?
    private var hasPerformedInitialWarmup = false
    private var deviceRefreshTask: Task<Void, Never>?
    private var deviceNotificationObservers: [NSObjectProtocol] = []
    
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
        observePermissionChanges()
        
        // Check if last recording exists on disk
        updateHasLastRecording()
        
        // Load initial devices
        self.availableDevices = []
        self.selectedDeviceID = AVCaptureDevice.default(for: .audio)?.uniqueID
        recorder.selectedDeviceID = self.selectedDeviceID
        scheduleDeviceEnumeration()
        registerDeviceNotifications()
        
        // Set default hotkey
        if KeyboardShortcuts.getShortcut(for: .toggleAirakeet) == nil {
            KeyboardShortcuts.setShortcut(KeyboardShortcuts.Shortcut(.backtick, modifiers: [.function]), for: .toggleAirakeet)
        }
        
        // Initialize ASR engine
        Task {
            await asrEngine.setDelegate(self)
        }
        deferASRWarmupIfNeeded()

        statusBarManager = StatusBarManager(controller: self)
        
        setupMenuRefreshPipeline()

        startPermissionPolling()
    }
    
    private func observePermissionChanges() {
        permissions.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
    
    private func setupMenuRefreshPipeline() {
        objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.requestMenuRefresh()
            }
            .store(in: &cancellables)

        permissions.$hasMicrophonePermission
            .combineLatest(permissions.$hasAccessibilityPermission)
            .removeDuplicates { lhs, rhs in lhs.0 == rhs.0 && lhs.1 == rhs.1 }
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in
                guard let self = self else { return }
                self.startPermissionPolling()
                self.deferASRWarmupIfNeeded()
            }
            .store(in: &cancellables)
    }
    
    private func requestMenuRefresh() {
        statusBarManager?.setNeedsMenuRefresh()
    }
    
    private func startPermissionPolling() {
        permissions.checkAll()
        let hasAllPermissions = permissions.hasMicrophonePermission && permissions.hasAccessibilityPermission
        let interval: TimeInterval = hasAllPermissions ? 5.0 : 1.0
        if let timer = permissionTimer, abs(timer.timeInterval - interval) < 0.001 {
            return
        }
        permissionTimer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.permissions.checkAll()
            }
        }
        timer.tolerance = interval * 0.2
        RunLoop.main.add(timer, forMode: .common)
        permissionTimer = timer
    }
    
    private func deferASRWarmupIfNeeded() {
        guard !hasPerformedInitialWarmup else { return }
        guard deferredInitializationTask == nil else { return }
        
        deferredInitializationTask = Task { [weak self] in
            defer { self?.deferredInitializationTask = nil }
            do {
                try await Task.sleep(nanoseconds: 2_000_000_000)
            } catch {
                return
            }
            guard let self else {
                return
            }
            
            let engine = self.asrEngine
            do {
                try await Task.detached(priority: .utility) {
                    try await engine.ensureInitialized()
                }.value
                self.hasPerformedInitialWarmup = true
                self.resetIdleTimer()
            } catch {
                print("Airakeet: Deferred ASR init failed: \(error)")
            }
        }
    }
    
    private func scheduleDeviceEnumeration() {
        deviceRefreshTask?.cancel()
        deviceRefreshTask = Task { [weak self] in
            guard let self else { return }
            let devices = await Task.detached(priority: .utility) { () -> [AudioDeviceInfo] in
                let discoverySession = AVCaptureDevice.DiscoverySession(
                    deviceTypes: [.microphone],
                    mediaType: .audio,
                    position: .unspecified
                )
                return discoverySession.devices.map { device in
                    AudioDeviceInfo(uniqueID: device.uniqueID, localizedName: device.localizedName)
                }
            }.value
            self.applyEnumeratedDevices(devices)
        }
    }
    
    private func applyEnumeratedDevices(_ devices: [AudioDeviceInfo]) {
        availableDevices = devices
        if let selected = selectedDeviceID,
           !devices.contains(where: { $0.uniqueID == selected }) {
            selectedDeviceID = nil
        }
        
        if selectedDeviceID == nil {
            selectedDeviceID = devices.first?.uniqueID
        }
        
        recorder.selectedDeviceID = selectedDeviceID
    }
    
    private func registerDeviceNotifications() {
        let center = NotificationCenter.default
        let queue = OperationQueue.main
        let notifications: [NSNotification.Name] = [
            .AVCaptureDeviceWasConnected,
            .AVCaptureDeviceWasDisconnected
        ]
        
        notifications.forEach { name in
            let token = center.addObserver(forName: name, object: nil, queue: queue) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.scheduleDeviceEnumeration()
                }
            }
            deviceNotificationObservers.append(token)
        }
    }
    
    // MARK: - Overlay Helpers
    private func showRecordingOverlay() {
        showOverlay(AnyView(RecordingOverlayView(controller: self)))
        armEscapeCancelMonitor()
    }
    
    private func showOverlay(_ view: AnyView) {
        cancelOverlayHideTask()
        isPresentingSpecificErrorOverlay = false
        OverlayWindow.show(view: view)
    }
    
    private func presentTransientOverlay(for message: OverlayMessage, duration: TimeInterval = 1.0) {
        cancelOverlayHideTask()
        isPresentingSpecificErrorOverlay = message.isSpecificError
        let view = AnyView(
            StatusMessageOverlayView(
                iconName: message.iconName,
                iconColor: message.iconColor,
                title: message.title,
                subtitle: message.subtitle
            )
        )
        OverlayWindow.show(view: view)
        overlayMessageTask = Task { @MainActor [weak self] in
            let nanoseconds = UInt64(duration * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard let self else { return }
            if Task.isCancelled { return }
            OverlayWindow.hide()
            self.isPresentingSpecificErrorOverlay = false
            self.overlayMessageTask = nil
        }
    }
    
    private func hideOverlay() {
        cancelOverlayHideTask()
        isPresentingSpecificErrorOverlay = false
        OverlayWindow.hide()
        disarmEscapeCancelMonitor()
    }
    
    private func cancelOverlayHideTask() {
        overlayMessageTask?.cancel()
        overlayMessageTask = nil
    }
    
    private func armEscapeCancelMonitor() {
        if escapeCancelMonitor == nil {
            escapeCancelMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard event.keyCode == UInt16(kVK_Escape) else { return }
                Task { @MainActor [weak self] in
                    self?.handleEscapeCancel()
                }
            }
        }

        if escapeCancelLocalMonitor == nil {
            escapeCancelLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard event.keyCode == UInt16(kVK_Escape) else { return event }
                Task { @MainActor [weak self] in
                    self?.handleEscapeCancel()
                }
                return nil
            }
        }
    }

    private func disarmEscapeCancelMonitor() {
        if let m = escapeCancelMonitor { NSEvent.removeMonitor(m) }
        if let m = escapeCancelLocalMonitor { NSEvent.removeMonitor(m) }
        escapeCancelMonitor = nil
        escapeCancelLocalMonitor = nil
    }
    
    private func handleEscapeCancel() {
        guard !isEscapeCancellationInFlight else { return }
        guard isRecording else { return }
        
        isEscapeCancellationInFlight = true
        print("Airakeet: Escape cancellation triggered during recording.")
        
        cancelPendingStart()
        cancelActiveTranscriptionTask()
        
        hideOverlay()
        resetIdleTimer()
        presentTransientOverlay(for: .cancelled, duration: 1.25)
        
        Task { [weak self] in
            guard let self else { return }
            defer { self.isEscapeCancellationInFlight = false }
            do {
                let (_, duration) = try await self.recorder.stopRecording()
                self.lastClipDuration = duration
                self.updateHasLastRecording()
            } catch {
                print("Airakeet: Escape cancel stop error: \(error)")
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
        requestMenuRefresh()
    }
    
    // MARK: - Model Management
    func loadModel() {
        Task {
            do {
                try await asrEngine.loadModel(forceReload: true)
            } catch {
                print("Airakeet: Manual load failed: \(error)")
            }
        }
    }
    
    func deleteModelCache() {
        Task {
            do {
                try await asrEngine.deleteModelCache()
            } catch {
                print("Airakeet: Delete cache failed: \(error)")
            }
        }
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
        recorder.clearLastRecording()
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
        guard let url = recorder.getLastRecordingURL() else { return }
        cancelActiveTranscriptionTask()
        transcriptionTask = Task {
            defer {
                resetIdleTimer()
                transcriptionTask = nil
                if !isRecording {
                    status = .ready
                }
            }
            
            do {
                try await asrEngine.ensureInitialized()
                status = .transcribing
                let result = try await asrEngine.transcribe(url: url)
                if Task.isCancelled { return }
                self.lastResult = result
            } catch {
                if Task.isCancelled { return }
                print("Airakeet: Re-transcribe error: \(error)")
                presentTransientOverlay(for: .generalError)
            }
        }
    }
    
    func injectLastResult() {
        if let text = lastResult?.text {
            injector.inject(text)
        }
    }
    
    func transcribeAudioFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.audio, .mp3, .wav, .mpeg4Audio]
        panel.title = "Select Audio File"
        
        NSApp.activate(ignoringOtherApps: true)
        let response = panel.runModal()
        
        if response == .OK, let url = panel.url {
            Task {
                do {
                    try await asrEngine.ensureInitialized()
                    // Show overlay for feedback
                    self.showRecordingOverlay()
                    
                    let result = try await asrEngine.transcribe(url: url)
                    self.lastResult = result
                    injector.inject(result.text)
                } catch {
                    print("Airakeet: File transcription error: \(error)")
                    self.presentTransientOverlay(for: .generalError)
                }
            }
        }
    }
    
    func copyLastTranscript() {
        guard let text = lastResult?.text else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        print("Airakeet: Last transcript copied to clipboard.")
    }
    
    func asrEngineForFile() -> ASREngine {
        return asrEngine
    }
    
    func openFileTranscriptionWindow() {
        FileTranscriptionWindow.show(controller: self)
    }
    
    func changeDevice(_ deviceID: String) {
        self.selectedDeviceID = deviceID
        recorder.selectedDeviceID = deviceID
    }
    
    func openHotkeySettings() {
        HotkeySettingsWindow.show(controller: self)
    }
    
    func openUpdateWindow() {
        NSApp.activate(ignoringOtherApps: true)
        UpdateStatusWindow.show(controller: self)
    }
    
    func beginUpdateFlow() {
        openUpdateWindow()
        guard updateTask == nil else { return }
        updateTask = Task { @MainActor [weak self] in
            guard let self else { return }
            self.updateStatus = .checking
            self.requestMenuRefresh()
            do {
                let outcome = try await self.updateManager.checkAndInstall(currentVersion: self.currentVersion) { event in
                    Task { @MainActor [weak self] in
                        self?.handleUpdateEvent(event)
                    }
                }
                self.latestRelease = outcome.release
                switch outcome.result {
                case .upToDate(let remote):
                    self.updateStatus = .upToDate(remoteVersion: remote)
                case .installed(let version, let location):
                    self.pendingRelaunchURL = location
                    self.updateStatus = .needsRestart(version: version)
                }
            } catch let error as UpdateError {
                self.updateStatus = .failed(message: error.errorDescription ?? "Unknown update error.")
            } catch {
                self.updateStatus = .failed(message: error.localizedDescription)
            }
            self.updateTask = nil
            self.requestMenuRefresh()
        }
    }
    
    func restartAfterUpdate() {
        let targetURL = pendingRelaunchURL ?? Bundle.main.bundleURL
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: targetURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }
    
    @MainActor
    private func handleUpdateEvent(_ event: UpdateStateEvent) {
        switch event {
        case .checking:
            updateStatus = .checking
        case .foundRelease(let release):
            latestRelease = release
        case .downloadProgress(let progress):
            updateStatus = .downloading(progress: progress)
        case .installing:
            updateStatus = .installing
        }
    }
    
    private func resetIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: idleTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor in
                await self?.asrEngine.unload()
            }
        }
    }
    
    private func cancelPendingStart() {
        guard let task = startTask else { return }
        task.cancel()
        startTask = nil
    }
    
    private func cancelActiveTranscriptionTask() {
        guard let task = transcriptionTask else { return }
        transcriptionTask = nil
        task.cancel()
        Task.detached(priority: .userInitiated) {
            _ = await task.result
        }
    }
    
    // MARK: - AudioRecorderDelegate
    func audioRecorderDidUpdateRecordingState(_ isRecording: Bool) {
        self.isRecording = isRecording
        if isRecording {
            self.showRecordingOverlay()
        } else if self.status != .transcribing {
            self.hideOverlay()
        }
    }

    func audioRecorderDidUpdatePower(_ power: Float) {
        self.currentPower = power
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
        switch status {
        case .ready:
            if !isRecording {
                hideOverlay()
            }
        case .transcribing:
            showRecordingOverlay()
        case .error:
            if !isPresentingSpecificErrorOverlay {
                presentTransientOverlay(for: .generalError)
            }
        default:
            break
        }
    }
    
    func asrEngineDidUpdateProgress(_ progress: Double) {
        self.loadProgress = progress
    }
    
    func asrEngineDidUpdateLoadLog(_ log: String) {
        self.loadLog = log
    }
    
    // MARK: - Actions
    func startRecording() {
        guard startTask == nil else { return }
        permissions.checkAll()
        guard permissions.hasMicrophonePermission && permissions.hasAccessibilityPermission else {
            openDebugWindow()
            return
        }
        guard !isRecording else { return }
        
        cancelActiveTranscriptionTask()
        
        idleTimer?.invalidate()
        lastClipDuration = nil
        
        let task = Task { [weak self] in
            guard let self = self else { return }
            defer {
                Task { @MainActor in
                    self.startTask = nil
                }
            }
            do {
                try await self.asrEngine.ensureInitialized()
                try Task.checkCancellation()
                try await MainActor.run {
                    self.recorder.clearLastRecording()
                    self.updateHasLastRecording()
                    try self.recorder.startRecording()
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.resetIdleTimer()
                    self.hideOverlay()
                }
            } catch {
                print("Airakeet: Start error: \(error)")
                await MainActor.run {
                    self.resetIdleTimer()
                    self.presentTransientOverlay(for: .generalError)
                }
            }
        }
        
        startTask = task
    }
    
    func startManualRecording() {
        startRecording()
    }
    
    func stopRecording() {
        cancelPendingStart()
        guard isRecording else { return }
        
        cancelActiveTranscriptionTask()
        transcriptionTask = Task {
            defer { 
                resetIdleTimer() 
                transcriptionTask = nil
            }
            
            do {
                let (samples, duration) = try await recorder.stopRecording()
                self.lastClipDuration = duration
                updateHasLastRecording()
                if Task.isCancelled { return }
                
                let result = try await asrEngine.transcribe(samples: samples, audioDuration: duration)
                if Task.isCancelled { return }
                
                self.lastResult = result
                injector.inject(result.text)
            } catch {
                if !Task.isCancelled {
                    print("Airakeet: Transcription error: \(error)")
                    if let duration = self.lastClipDuration, duration < self.shortClipThreshold {
                        self.presentTransientOverlay(for: .shortInput)
                    } else {
                        self.presentTransientOverlay(for: .generalError)
                    }
                }
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
        recorder.clearLastRecording()
        NSApplication.shared.terminate(nil)
    }
    
    private enum OverlayMessage {
        case shortInput
        case generalError
        case cancelled
        
        var iconName: String {
            switch self {
            case .shortInput: return "mic.slash.fill"
            case .generalError: return "xmark.octagon.fill"
            case .cancelled: return "escape"
            }
        }
        
        var iconColor: Color {
            switch self {
            case .shortInput: return .red
            case .generalError: return .red
            case .cancelled: return .yellow
            }
        }
        
        var title: String {
            switch self {
            case .shortInput: return "Error: input too short"
            case .generalError: return "Error: try again"
            case .cancelled: return "Canceled"
            }
        }
        
        var subtitle: String? {
            switch self {
            case .shortInput: return nil
            case .generalError: return "See Debug window for details."
            case .cancelled: return nil
            }
        }
        
        var isSpecificError: Bool {
            switch self {
            case .shortInput: return true
            case .generalError: return false
            case .cancelled: return false
            }
        }
    }
}

@MainActor
class StatusBarManager: NSObject, NSMenuDelegate {
    private let statusBarItem: NSStatusItem
    private let controller: AppController
    private let menu: NSMenu
    private var needsMenuRefresh = true
    
    init(controller: AppController) {
        self.controller = controller
        self.statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.menu = NSMenu()
        super.init()
        
        if let button = statusBarItem.button {
            button.image = NSImage(systemSymbolName: "waveform.circle", accessibilityDescription: "Airakeet")
        }
        
        menu.delegate = self
        statusBarItem.menu = menu
        setNeedsMenuRefresh()
    }
    
    func setNeedsMenuRefresh() {
        needsMenuRefresh = true
    }
    
    @objc func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === self.menu else { return }
        guard needsMenuRefresh || menu.items.isEmpty else { return }
        rebuildMenu()
        needsMenuRefresh = false
    }
    
    private func rebuildMenu() {
        menu.removeAllItems()
        
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
        
        let fileItem = NSMenuItem(title: "Transcribe Audio File...", action: #selector(openFile), keyEquivalent: "o")
        fileItem.target = self
        menu.addItem(fileItem)
        
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
        controller.availableDevices.forEach { device in
            let item = NSMenuItem(title: device.localizedName, action: #selector(changeDevice(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = device.uniqueID
            if device.uniqueID == controller.selectedDeviceID { item.state = .on }
            micSelectorMenu.addItem(item)
        }
        
        if controller.availableDevices.isEmpty {
            let emptyItem = NSMenuItem(title: "No devices found", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            micSelectorMenu.addItem(emptyItem)
        }
        
        let micSelectorItem = NSMenuItem(title: "Input Source", action: nil, keyEquivalent: "")
        micSelectorItem.submenu = micSelectorMenu
        menu.addItem(micSelectorItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // --- Debug & App Section ---
        let updateItem = NSMenuItem(title: controller.updateMenuTitle, action: #selector(checkForUpdates), keyEquivalent: "")
        updateItem.target = self
        updateItem.isEnabled = controller.updateStatus.isClickable
        menu.addItem(updateItem)
        
        let debugItem = NSMenuItem(title: "Open Test/Debug...", action: #selector(openDebug), keyEquivalent: "d")
        debugItem.target = self
        menu.addItem(debugItem)
        
        let copyItem = NSMenuItem(title: "Copy Last Transcript", action: #selector(copyLast), keyEquivalent: "c")
        copyItem.target = self
        copyItem.isEnabled = controller.lastResult != nil
        menu.addItem(copyItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }
    
    @objc func copyLast() { controller.copyLastTranscript() }
    @objc func toggleLaunch() { controller.toggleStartAtLogin() }
    @objc func openHotkey() { controller.openHotkeySettings() }
    @objc func openFile() { controller.openFileTranscriptionWindow() }
    @objc func changeMode(_ sender: NSMenuItem) {
        if let mode = sender.representedObject as? RecordingMode {
            controller.changeMode(mode)
            setNeedsMenuRefresh()
        }
    }
    @objc func changeDevice(_ sender: NSMenuItem) {
        if let deviceID = sender.representedObject as? String {
            controller.changeDevice(deviceID)
            setNeedsMenuRefresh()
        }
    }
    @objc func checkForUpdates() { controller.beginUpdateFlow() }
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
