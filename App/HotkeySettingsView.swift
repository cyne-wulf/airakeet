import SwiftUI
import KeyboardShortcuts
import Core

struct HotkeySettingsView: View {
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
            
            Text("Choose a global hotkey to start/stop dictation from anywhere.")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            HStack {
                Text("Shortcut:")
                KeyboardShortcuts.Recorder(for: .toggleAirakeet)
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
            
            Text("Tip: Try using 'Fn + `' or 'Option + Space'.")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Button("Done") {
                NSApplication.shared.keyWindow?.close()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(30)
        .frame(width: 400)
    }
}

class HotkeySettingsWindow: NSWindow {
    static var shared: HotkeySettingsWindow?
    
    static func show() {
        if let shared = shared {
            shared.makeKeyAndOrderFront(nil)
            return
        }
        
        let window = HotkeySettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 250),
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
