import SwiftUI
import Core
import UniformTypeIdentifiers

struct FileTranscriptionView: View {
    @ObservedObject var controller: AppController
    @State private var transcriptText: String = ""
    @State private var fileName: String = ""
    @State private var isProcessing: Bool = false
    
    var body: some View {
        VStack(spacing: 20) {
            headerSection
            
            if isProcessing {
                processingView
            } else {
                uploadSection
            }
            
            transcriptSection
            
            HStack {
                Button("Clear") {
                    transcriptText = ""
                    fileName = ""
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                
                Spacer()
                
                Button("Done") {
                    NSApplication.shared.keyWindow?.close()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(controller.waveformColor)
            }
        }
        .padding(30)
        .frame(width: 500, height: 600)
    }
    
    var headerSection: some View {
        HStack {
            Image(systemName: "doc.text.fill")
                .font(.largeTitle)
                .foregroundColor(controller.waveformColor)
            VStack(alignment: .leading) {
                Text("File Transcription")
                    .font(.headline)
                if !fileName.isEmpty {
                    Text(fileName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
        }
    }
    
    var processingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Transcribing your file locally...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
    
    var uploadSection: some View {
        Button(action: { selectAndTranscribe() }) {
            VStack(spacing: 8) {
                Image(systemName: "arrow.up.doc")
                    .font(.title)
                Text("Select Audio File...")
                    .fontWeight(.medium)
                Text("Supports MP3, WAV, M4A")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 30)
            .background(controller.waveformColor.opacity(0.05))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(controller.waveformColor.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    var transcriptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("TRANSCRIPT")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                Spacer()
                if !transcriptText.isEmpty {
                    Button(action: { 
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString(transcriptText, forType: .string)
                    }) {
                        Label("Copy", systemImage: "doc.on.doc")
                            .font(.caption2)
                    }
                    .buttonStyle(.link)
                }
            }
            
            TextEditor(text: $transcriptText)
                .font(.system(.body, design: .monospaced))
                .padding(4)
                .background(Color.black.opacity(0.03))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.1), lineWidth: 1)
                )
        }
    }
    
    func selectAndTranscribe() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.audio, .mp3, .wav, .mpeg4Audio]
        
        if panel.runModal() == .OK, let url = panel.url {
            self.fileName = url.lastPathComponent
            self.isProcessing = true
            
            Task {
                do {
                    try await controller.asrEngineForFile().ensureInitialized()
                    let result = try await controller.asrEngineForFile().transcribe(url: url)
                    self.transcriptText = result.text
                    self.isProcessing = false
                } catch {
                    self.transcriptText = "Error: \(error.localizedDescription)"
                    self.isProcessing = false
                }
            }
        }
    }
}

class FileTranscriptionWindow: NSWindow {
    static var shared: FileTranscriptionWindow?
    
    static func show(controller: AppController) {
        NSApp.activate(ignoringOtherApps: true)
        
        if let shared = shared {
            shared.makeKeyAndOrderFront(nil)
            return
        }
        
        let window = FileTranscriptionWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 600),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "Airakeet - File Transcription"
        window.contentView = NSHostingView(rootView: FileTranscriptionView(controller: controller))
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        shared = window
    }
}
