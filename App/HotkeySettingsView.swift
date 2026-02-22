import SwiftUI
import KeyboardShortcuts
import Core

struct HotkeySettingsView: View {
    @State private var isListeningForFnKey = false
    @State private var fnKeyHint = ""
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Image(systemName: "keyboard")
                    .font(.largeTitle)
                    .foregroundColor(.blue)
                Text("Launch Shortcut")
                    .font(.headline)
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 16) {
                // Standard Recorder
                VStack(alignment: .leading, spacing: 8) {
                    Text("Standard Shortcut")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        KeyboardShortcuts.Recorder(for: .toggleAirakeet)
                            .fixedSize()
                        Spacer()
                        Button("Reset to Default") {
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
                    Text("Custom 'Fn' Shortcut")
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
                        .tint(isListeningForFnKey ? .orange : .blue)
                    }
                    .padding()
                    .background(Color.blue.opacity(0.05))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isListeningForFnKey ? Color.orange : Color.clear, lineWidth: 2)
                    )
                }
            }
            
            Text("Note: Use the blue box above to set a shortcut using the 'Fn' key. Just click it and tap the key you want to use with Fn.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Done") {
                NSApplication.shared.keyWindow?.close()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(30)
        .frame(width: 400)
        .background(KeyEventHandler(isListening: $isListeningForFnKey))
    }
}

/// A hidden view that monitors for local key events when active
struct KeyEventHandler: NSViewRepresentable {
    @Binding var isListening: Bool
    
    class Coordinator: NSObject {
        var monitor: Any?
        var isListening: Bool = false
        var onCaptured: ((KeyboardShortcuts.Key) -> Void)?
        
        func startMonitoring() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self = self, self.isListening else { return event }
                
                let key = KeyboardShortcuts.Key(rawValue: Int(event.keyCode))
                self.onCaptured?(key)
                return nil // Swallow
            }
        }
        
        deinit {
            if let monitor = monitor {
                NSEvent.removeMonitor(monitor)
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

class HotkeySettingsWindow: NSWindow {
    static var shared: HotkeySettingsWindow?
    
    static func show() {
        NSApp.activate(ignoringOtherApps: true)
        
        if let shared = shared {
            shared.makeKeyAndOrderFront(nil)
            return
        }
        
        let window = HotkeySettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 400),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "Airakeet Hotkey"
        window.contentView = NSHostingView(rootView: HotkeySettingsView())
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        shared = window
    }
}
