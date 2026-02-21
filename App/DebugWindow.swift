import SwiftUI
import Core

struct DebugWindowView: View {
    @ObservedObject var controller: AppController
    @StateObject private var permissions = PermissionsManager()
    
    var body: some View {
        VStack(spacing: 20) {
            headerSection
            statusSection
            controlsSection
            resultsSection
            permissionsSection
        }
        .padding()
        .frame(width: 400, height: 600)
    }
    
    var headerSection: some View {
        HStack {
            Image(systemName: "waveform.circle.fill")
                .font(.largeTitle)
                .foregroundColor(.blue)
            Text("Parakeet Debug")
                .font(.headline)
            Spacer()
        }
    }
    
    var statusSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("Status:")
                    .fontWeight(.bold)
                Text(controller.status.rawValue)
                    .foregroundColor(controller.status == .error ? .red : .primary)
            }
            if controller.isRecording {
                HStack {
                    Text("Recording...")
                        .foregroundColor(.red)
                    ProgressView()
                        .scaleEffect(0.5)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
    
    var controlsSection: some View {
        VStack(spacing: 10) {
            Button(action: { controller.startRecording() }) {
                Text("Record 5s Test")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(controller.isRecording)
            
            HStack {
                Button(action: { controller.reTranscribeLast() }) {
                    Text("Re-transcribe Last")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(controller.lastResult == nil)
                
                Button(action: { controller.injectLastResult() }) {
                    Text("Inject Last Result")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(controller.lastResult == nil)
            }
        }
    }
    
    var resultsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Last Transcript:")
                .fontWeight(.bold)
            
            TextEditor(text: .constant(controller.lastResult?.text ?? ""))
                .font(.system(.body, design: .monospaced))
                .frame(height: 100)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.2)))
            
            if let metrics = controller.lastResult?.metrics {
                VStack(alignment: .leading, spacing: 5) {
                    metricRow(label: "Audio Duration:", value: String(format: "%.2fs", metrics.audioDuration))
                    metricRow(label: "Transcription Time:", value: String(format: "%.2fs", metrics.transcriptionTime))
                    metricRow(label: "Total Time:", value: String(format: "%.2fs", metrics.totalTime))
                    metricRow(label: "Real-time Factor:", value: String(format: "%.2fx", metrics.realTimeFactor))
                }
                .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Permissions:")
                .fontWeight(.bold)
            
            permissionRow(label: "Microphone", granted: permissions.hasMicrophonePermission)
            permissionRow(label: "Accessibility", granted: permissions.hasAccessibilityPermission)
            
            Button("Open System Settings") {
                permissions.openSystemSettings()
            }
            .font(.caption)
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
    }
    
    func metricRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
    
    func permissionRow(label: String, granted: Bool) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(granted ? .green : .red)
            Text(label)
            Spacer()
            if !granted {
                Button("Request") {
                    if label == "Microphone" {
                        Task { await permissions.requestMicrophone() }
                    } else {
                        permissions.requestAccessibility()
                    }
                }
                .buttonStyle(.link)
                .font(.caption)
            }
        }
    }
}

class DebugWindow: NSWindow {
    static var shared: DebugWindow?
    
    static func show(controller: AppController) {
        if let shared = shared {
            shared.makeKeyAndOrderFront(nil)
            return
        }
        
        let window = DebugWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 600),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "Parakeet Debug"
        window.contentView = NSHostingView(rootView: DebugWindowView(controller: controller))
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        shared = window
    }
}
