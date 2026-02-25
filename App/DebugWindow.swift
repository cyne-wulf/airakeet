import SwiftUI
import Core

struct DebugWindowView: View {
    @ObservedObject var controller: AppController
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerSection
                statusSection
                controlsSection
                resultsSection
                modelManagementSection
                permissionsSection
            }
            .padding()
        }
        .frame(minWidth: 400, maxWidth: 400, minHeight: 400, maxHeight: 800)
    }
    
    var headerSection: some View {
        HStack {
            Image(systemName: "waveform.circle.fill")
                .font(.largeTitle)
                .foregroundColor(controller.waveformColor)
            Text("Airakeet Debug")
                .font(.headline)
            Spacer()
        }
    }
    
    var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Status:")
                    .fontWeight(.bold)
                Text(controller.status.rawValue)
                    .foregroundColor(controller.status == .error ? .red : .primary)
            }
            
            if controller.status == .loading {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: controller.loadProgress, total: 1.0)
                        .progressViewStyle(.linear)
                    Text("\(Int(controller.loadProgress * 100))%")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
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
            if controller.isRecording {
                Button(action: { controller.stopRecording() }) {
                    HStack {
                        Image(systemName: "stop.fill")
                        Text("Stop Recording")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            } else {
                Button(action: { controller.startManualRecording() }) {
                    HStack {
                        Image(systemName: "record.circle")
                        Text("Start Test Recording")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(controller.isRecording || controller.status == .loading)
            }
            
            HStack {
                Button(action: { controller.reTranscribeLast() }) {
                    Text("Re-transcribe Last")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(controller.lastResult == nil || controller.isRecording || controller.status == .loading)
                
                Button(action: { controller.injectLastResult() }) {
                    HStack {
                        Image(systemName: "square.and.arrow.down")
                        Text("Inject Last Result")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(controller.lastResult == nil || controller.isRecording || controller.status == .loading)
            }
        }
    }
    
    var resultsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Last Transcript:")
                    .fontWeight(.bold)
                Spacer()
                if controller.lastResult != nil {
                    Button(action: { controller.copyLastTranscript() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.doc")
                            Text("Copy")
                        }
                        .font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.blue)
                }
            }
            
            TextEditor(text: .constant(controller.lastResult?.text ?? ""))
                .font(.system(.body, design: .monospaced))
                .frame(height: 80)
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
            
            if controller.hasLastRecording {
                VStack(alignment: .leading, spacing: 8) {
                    Text("LAST RECORDING (DISK CACHE)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Button(action: { controller.playLastRecording() }) {
                            HStack {
                                Image(systemName: "play.circle.fill")
                                Text("Play Audio")
                            }
                        }
                        .buttonStyle(.bordered)
                        
                        Button(action: { controller.saveLastRecording() }) {
                            HStack {
                                Image(systemName: "arrow.down.doc.fill")
                                Text("Save...")
                            }
                        }
                        .buttonStyle(.bordered)
                        
                        Button(action: { controller.deleteLastRecording() }) {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 8)
                    }
                }
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    var modelManagementSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MODEL MANAGEMENT")
                .font(.caption)
                .fontWeight(.black)
                .foregroundColor(.secondary)
            
            HStack {
                Button(action: { controller.loadModel() }) {
                    HStack {
                        Image(systemName: "arrow.down.circle")
                        Text("Reload Model")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(controller.status == .loading)
                
                Button(action: { controller.deleteModelCache() }) {
                    HStack {
                        Image(systemName: "trash")
                        Text("Delete Cache")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .disabled(controller.status == .loading)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
    
    var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("REQUIRED PERMISSIONS")
                    .font(.caption)
                    .fontWeight(.black)
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: { controller.permissions.checkAll() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                        Text("Refresh")
                    }
                    .font(.caption2)
                }
                .buttonStyle(.link)
            }
            
            permissionRow(label: "Microphone", granted: controller.permissions.hasMicrophonePermission)
            permissionRow(label: "Accessibility", granted: controller.permissions.hasAccessibilityPermission)
            
            if !controller.permissions.hasMicrophonePermission || !controller.permissions.hasAccessibilityPermission {
                Text("Airakeet cannot function without these permissions.")
                    .font(.caption2)
                    .foregroundColor(.red)
                    .padding(.top, 4)
            }
            
            Button("Open System Settings") {
                controller.permissions.openSystemSettings()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding()
        .background(Color.red.opacity(controller.permissions.hasMicrophonePermission && controller.permissions.hasAccessibilityPermission ? 0 : 0.1))
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
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
            Image(systemName: granted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(granted ? .green : .red)
                .font(.title3)
            
            VStack(alignment: .leading) {
                Text(label)
                    .fontWeight(.bold)
                Text(granted ? "Permission Granted" : "Permission Missing")
                    .font(.caption2)
                    .foregroundColor(granted ? .secondary : .red)
            }
            
            Spacer()
            
            if !granted {
                Button("Grant") {
                    if label == "Microphone" {
                        Task { await controller.permissions.requestMicrophone() }
                    } else {
                        controller.permissions.requestAccessibility()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
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
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "Airakeet Debug"
        window.contentView = NSHostingView(rootView: DebugWindowView(controller: controller))
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        shared = window
    }
}
