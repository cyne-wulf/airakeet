import SwiftUI
import KeyboardShortcuts
import Core

struct HotkeySettingsView: View {
    var controller: AppController
    
    @State private var isListeningForFnKey = false
    @State private var fnKeyHint = ""
    @State private var useShiftFn: Bool = false
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Image(systemName: "keyboard")
                    .font(.largeTitle)
                    .foregroundColor(controller.waveformColor)
                Text("Hotkey Settings")
                    .font(.headline)
                Spacer()
            }
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Standard Recorder
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ACTIVE SHORTCUT")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 8) {
                            KeyboardShortcuts.Recorder(for: .toggleAirakeet)
                                .fixedSize()
                            
                            if useShiftFn {
                                HStack(spacing: 4) {
                                    Image(systemName: "globe")
                                    Image(systemName: "shift.fill")
                                }
                                .font(.system(size: 14, weight: .semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(4)
                                
                                Text("+ Shift + Fn enabled")
                                    .foregroundColor(.secondary)
                                    .font(.subheadline)
                            }
                            
                            Spacer()
                            
                            // Always show reset unless it's already default Fn+`
                            Button("Reset Default") {
                                KeyboardShortcuts.setShortcut(KeyboardShortcuts.Shortcut(.backtick, modifiers: [.function]), for: .toggleAirakeet)
                            }
                            .buttonStyle(.link)
                            .font(.caption)
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                    }
                    
                    // Special Fn-Key Binder
                    VStack(alignment: .leading, spacing: 8) {
                        Text("CUSTOM 'FN' SHORTCUT")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            Button(action: { 
                                isListeningForFnKey.toggle()
                                if isListeningForFnKey { fnKeyHint = "Press any key..." }
                            }) {
                                Text(isListeningForFnKey ? fnKeyHint : "Bind Fn + [Key]...")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(isListeningForFnKey ? .orange : controller.waveformColor)
                        }
                        .padding()
                        .background(controller.waveformColor.opacity(0.05))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isListeningForFnKey ? Color.orange : Color.clear, lineWidth: 2)
                        )
                    }
                    
                    // Suggested Binds (Bottom)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("SUGGESTED BINDS")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)
                        
                        Button(action: { 
                            controller.toggleShiftFnShortcut()
                            useShiftFn = controller.useShiftFnShortcut
                        }) {
                            HStack {
                                Text("Shift + Fn")
                                Spacer()
                                if useShiftFn {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                }
                            }
                            .padding(.horizontal, 12)
                            .frame(maxWidth: .infinity, minHeight: 36)
                        }
                        .buttonStyle(.bordered)
                        .tint(useShiftFn ? .green : .primary)
                    }
                }
            }
            
            Button("Done") {
                NSApplication.shared.keyWindow?.close()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(controller.waveformColor)
        }
        .padding(30)
        .frame(width: 400, height: 460)
        .background(KeyEventHandler(isListening: $isListeningForFnKey))
        .onAppear {
            self.useShiftFn = controller.useShiftFnShortcut
        }
    }
}

/// A hidden view that monitors for local key events when active
struct KeyEventHandler: NSViewRepresentable {
    @Binding var isListening: Bool
    
    private final class MonitorWrapper: @unchecked Sendable {
        var monitor: Any?
    }
    
    class Coordinator: NSObject {
        private let monitorWrapper = MonitorWrapper()
        var isListening: Bool = false
        var onCaptured: ((KeyboardShortcuts.Key) -> Void)?
        
        func startMonitoring() {
            stopMonitoring()
            monitorWrapper.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self = self, self.isListening else { return event }
                
                let key = KeyboardShortcuts.Key(rawValue: Int(event.keyCode))
                self.onCaptured?(key)
                return nil // Swallow
            }
        }
        
        func stopMonitoring() {
            if let monitor = monitorWrapper.monitor {
                NSEvent.removeMonitor(monitor)
                monitorWrapper.monitor = nil
            }
        }
        
        deinit {
            let monitor = monitorWrapper.monitor
            if let monitor = monitor {
                DispatchQueue.main.async {
                    NSEvent.removeMonitor(monitor)
                }
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.onCaptured = { key in
            KeyboardShortcuts.setShortcut(KeyboardShortcuts.Shortcut(key, modifiers: [.function]), for: .toggleAirakeet)
            DispatchQueue.main.async {
                self.isListening = false
            }
        }
        context.coordinator.startMonitoring()
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isListening = isListening
    }
}

class HotkeySettingsWindow: NSWindow, NSWindowDelegate {
    static var shared: HotkeySettingsWindow?
    
    static func show(controller: AppController) {
        NSApp.activate(ignoringOtherApps: true)
        
        if let shared = shared {
            shared.makeKeyAndOrderFront(nil)
            return
        }
        
        let window = HotkeySettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 460),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "Hotkey Settings"
        window.contentView = NSHostingView(rootView: HotkeySettingsView(controller: controller))
        window.isReleasedWhenClosed = false
        window.delegate = window
        window.makeKeyAndOrderFront(nil)
        shared = window
    }
    
    func windowWillClose(_ notification: Notification) {
        HotkeySettingsWindow.shared = nil
    }
}
