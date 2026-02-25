import SwiftUI
import Core
import UniformTypeIdentifiers
import AVFoundation
import AppKit

struct FileTranscriptionView: View {
    @ObservedObject var controller: AppController
    @StateObject private var viewModel = FileTranscriptionViewModel()
    
    var body: some View {
        VStack(spacing: 20) {
            headerSection
            controlSection
            transcriptSection
            footerSection
        }
        .padding(30)
        .frame(width: 500, height: 600)
        .onDisappear {
            viewModel.clear(deleteStore: true)
        }
    }
    
    private var headerSection: some View {
        HStack {
            Image(systemName: "doc.text.fill")
                .font(.largeTitle)
                .foregroundColor(controller.waveformColor)
            VStack(alignment: .leading) {
                Text("File Transcription")
                    .font(.headline)
                if !viewModel.fileName.isEmpty {
                    Text(viewModel.fileName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
        }
    }
    
    private var controlSection: some View {
        VStack(spacing: 12) {
            if viewModel.isProcessing {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: viewModel.processedDuration, total: max(viewModel.totalDuration, 0.0001))
                        .progressViewStyle(.linear)
                    Text(progressLabel)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.gray.opacity(0.05))
                .cornerRadius(12)
            } else {
                Button(action: selectAndTranscribe) {
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
            
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    
    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("TRANSCRIPT")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                Spacer()
                HStack(spacing: 12) {
                    Button(action: viewModel.copyFullTranscript) {
                        Label("Copy", systemImage: "doc.on.doc")
                            .font(.caption2)
                    }
                    .buttonStyle(.link)
                    .disabled(!viewModel.canCopy)
                    
                    Button(action: viewModel.revealTranscriptFile) {
                        Label("Reveal", systemImage: "folder")
                            .font(.caption2)
                    }
                    .buttonStyle(.link)
                    .disabled(!viewModel.canReveal)
                }
            }
            
            TranscriptTextView(controller: viewModel.textController)
                .background(Color.black.opacity(0.03))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.1), lineWidth: 1)
                )
        }
    }
    
    private var footerSection: some View {
        HStack {
            Button("Clear") {
                viewModel.clear(deleteStore: true)
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            
            Spacer()
            
            Button("Done") {
                viewModel.clear(deleteStore: true)
                NSApplication.shared.keyWindow?.close()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(controller.waveformColor)
        }
    }
    
    private var progressLabel: String {
        let processed = format(duration: viewModel.processedDuration)
        let total = viewModel.totalDuration > 0 ? format(duration: viewModel.totalDuration) : "?"
        return "Processed \(processed) of \(total) • Chunks: \(max(viewModel.chunkCount, 0))"
    }
    
    private func selectAndTranscribe() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.audio, .mp3, .wav, .mpeg4Audio]
        
        if panel.runModal() == .OK, let url = panel.url {
            viewModel.startTranscription(url: url, engine: controller.asrEngineForFile())
        }
    }
    
    private func format(duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: duration) ?? String(format: "%.1fs", duration)
    }
}

final class FileTranscriptionViewModel: ObservableObject, @unchecked Sendable {
    @Published var isProcessing = false
    @Published var processedDuration: TimeInterval = 0
    @Published var totalDuration: TimeInterval = 0
    @Published var chunkCount: Int = 0
    @Published var fileName: String = ""
    @Published var errorMessage: String?
    @Published var canCopy = false
    @Published var canReveal = false
    
    let textController = TranscriptTextController()
    
    private var transcriptStore: TranscriptStore?
    private var transcriptionTask: Task<Void, Never>?
    
    func startTranscription(url: URL, engine: ASREngine) {
        clear(deleteStore: true)
        fileName = url.lastPathComponent
        do {
            let store = try TranscriptStore()
            transcriptStore = store
            canReveal = true
            Task { @MainActor in
                self.textController.clear()
            }
            processedDuration = 0
            totalDuration = 0
            chunkCount = 0
            canCopy = false
            errorMessage = nil
            isProcessing = true
            
            let service = FileTranscriptionService(engine: engine)
            transcriptionTask = Task { [weak self] in
                guard let self else { return }
                do {
                    try await service.transcribe(url: url) { [weak self] update in
                        guard let self else { return }
                        if Task.isCancelled { return }
                        try? store.append(update.appendedText)
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            self.chunkCount = update.chunkIndex
                            self.processedDuration = update.processedDuration
                            self.totalDuration = update.totalDuration
                            self.canCopy = true
                            self.isProcessing = update.processedDuration < update.totalDuration
                            self.textController.append(update.appendedText)
                        }
                    }
                    await MainActor.run {
                        self.isProcessing = false
                    }
                } catch is CancellationError {
                    await MainActor.run {
                        self.isProcessing = false
                    }
                } catch {
                    await MainActor.run {
                        self.errorMessage = error.localizedDescription
                        self.isProcessing = false
                    }
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    func copyFullTranscript() {
        guard canCopy, let text = transcriptStore?.readAll(), !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
    
    func revealTranscriptFile() {
        guard canReveal, let url = transcriptStore?.url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    
    func clear(deleteStore: Bool) {
        transcriptionTask?.cancel()
        transcriptionTask = nil
        if deleteStore {
            transcriptStore?.delete()
            transcriptStore = nil
            canReveal = false
        }
        Task { @MainActor in
            self.textController.clear()
        }
        processedDuration = 0
        totalDuration = 0
        chunkCount = 0
        isProcessing = false
        canCopy = false
        errorMessage = nil
        if deleteStore {
            fileName = ""
        }
    }
}

@MainActor
final class TranscriptTextController: ObservableObject {
    private weak var textView: NSTextView?
    private var pendingText = ""
    
    func bind(_ textView: NSTextView) {
        self.textView = textView
        textView.isEditable = false
        textView.isRichText = false
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = .labelColor
        if !pendingText.isEmpty {
            textView.textStorage?.append(NSAttributedString(string: pendingText))
            pendingText.removeAll()
        }
    }
    
    func append(_ text: String) {
        guard !text.isEmpty else { return }
        if let textView = textView {
            textView.textStorage?.append(NSAttributedString(string: text))
            textView.scrollToEndOfDocument(nil)
        } else {
            pendingText.append(text)
        }
    }
    
    func clear() {
        textView?.string = ""
        pendingText.removeAll()
    }
}

struct TranscriptTextView: NSViewRepresentable {
    @ObservedObject var controller: TranscriptTextController
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        let textView = NSTextView()
        textView.isEditable = false
        textView.isRichText = false
        textView.textContainerInset = NSSize(width: 8, height: 8)
        scrollView.documentView = textView
        controller.bind(textView)
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        if let textView = nsView.documentView as? NSTextView {
            controller.bind(textView)
        }
    }
}

final class TranscriptStore: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.airakeet.transcriptstore")
    private let directory: URL
    let url: URL
    private var handle: FileHandle?
    
    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("airakeet-transcripts", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("txt")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try FileHandle(forWritingTo: url)
    }
    
    func append(_ text: String) throws {
        guard let data = text.data(using: .utf8), let handle = handle else { return }
        try queue.sync {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        }
    }
    
    func readAll() -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }
    
    func delete() {
        queue.sync {
            try? handle?.close()
            handle = nil
        }
        try? FileManager.default.removeItem(at: url)
    }
}

struct FileTranscriptionChunkUpdate: Sendable {
    let appendedText: String
    let processedDuration: TimeInterval
    let totalDuration: TimeInterval
    let chunkIndex: Int
}

final class FileTranscriptionService {
    private let asrEngine: ASREngine
    private let targetSampleRate: Double = 16_000
    private let chunkDuration: TimeInterval = 30
    private let overlapDuration: TimeInterval = 1
    private let singleChunkThreshold: TimeInterval = 45
    
    init(engine: ASREngine) {
        self.asrEngine = engine
    }
    
    func transcribe(url: URL, onChunk: @escaping (FileTranscriptionChunkUpdate) -> Void) async throws {
        try await asrEngine.ensureInitialized()
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard !tracks.isEmpty else {
            throw NSError(domain: "FileTranscriptionService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No audio track found"])
        }
        let duration = try await asset.load(.duration)
        let totalDuration = CMTimeGetSeconds(duration)
        let singleChunkMode = totalDuration > 0 && totalDuration <= singleChunkThreshold
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: targetSampleRate,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVNumberOfChannelsKey: 1
        ])
        output.alwaysCopiesSampleData = false
        reader.add(output)
        guard reader.startReading() else {
            throw reader.error ?? NSError(domain: "FileTranscriptionService", code: -2, userInfo: [NSLocalizedDescriptionKey: "Unable to read audio file"])
        }
        
        var buffer: [Float] = []
        var chunkIndex = 0
        var processedSamples = 0
        var lastChunkEndedCleanly = true
        let chunkSamples = Int(chunkDuration * targetSampleRate)
        let overlapSamples = Int(overlapDuration * targetSampleRate)
        
        while reader.status == .reading, let sampleBuffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            buffer.append(contentsOf: Self.samples(from: sampleBuffer))
            if !singleChunkMode {
                while buffer.count >= chunkSamples {
                    let chunk = Array(buffer.prefix(chunkSamples))
                    let duration = Double(chunk.count) / targetSampleRate
                    let formatted = try await transcribeChunk(samples: chunk, duration: duration, chunkIndex: chunkIndex, lastChunkEndedCleanly: &lastChunkEndedCleanly)
                    let uniqueSamples = chunkIndex == 0 ? chunk.count : max(chunk.count - overlapSamples, 0)
                    processedSamples += uniqueSamples
                    let processedDuration = Double(processedSamples) / targetSampleRate
                    let total = totalDuration > 0 ? totalDuration : processedDuration
                    onChunk(FileTranscriptionChunkUpdate(appendedText: formatted, processedDuration: processedDuration, totalDuration: max(total, processedDuration), chunkIndex: chunkIndex + 1))
                    chunkIndex += 1
                    buffer = Array(buffer.suffix(overlapSamples))
                }
            }
        }
        
        if reader.status == .failed {
            throw reader.error ?? NSError(domain: "FileTranscriptionService", code: -3, userInfo: [NSLocalizedDescriptionKey: "Failed to read audio"])
        }
        
        let remainingThreshold = chunkIndex == 0 ? 0 : overlapSamples
        if buffer.count > remainingThreshold {
            let duration = Double(buffer.count) / targetSampleRate
            let formatted = try await transcribeChunk(samples: buffer, duration: duration, chunkIndex: chunkIndex, lastChunkEndedCleanly: &lastChunkEndedCleanly)
            let uniqueSamples = chunkIndex == 0 ? buffer.count : max(buffer.count - overlapSamples, 0)
            processedSamples += uniqueSamples
            let processedDuration = Double(processedSamples) / targetSampleRate
            let total = totalDuration > 0 ? totalDuration : processedDuration
            onChunk(FileTranscriptionChunkUpdate(appendedText: formatted, processedDuration: processedDuration, totalDuration: max(total, processedDuration), chunkIndex: chunkIndex + 1))
        }
    }
    
    private func transcribeChunk(samples: [Float], duration: TimeInterval, chunkIndex: Int, lastChunkEndedCleanly: inout Bool) async throws -> String {
        guard !samples.isEmpty else { return "" }
        let result = try await asrEngine.transcribe(samples: samples, audioDuration: duration)
        let trimmed = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        var formatted = trimmed
        if chunkIndex > 0 {
            formatted = lastChunkEndedCleanly ? "\n" + formatted : " " + formatted
        }
        if let lastCharacter = trimmed.last {
            lastChunkEndedCleanly = [".", "!", "?"] .contains(lastCharacter)
        } else {
            lastChunkEndedCleanly = false
        }
        return formatted + "\n"
    }
    
    private static func samples(from sampleBuffer: CMSampleBuffer) -> [Float] {
        var audioBufferList = AudioBufferList()
        var blockBuffer: CMBlockBuffer?
        CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: &audioBufferList,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )
        var collected: [Float] = []
        let buffers = UnsafeMutableAudioBufferListPointer(&audioBufferList)
        for buffer in buffers {
            guard let mData = buffer.mData else { continue }
            let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            guard count > 0 else { continue }
            let ptr = mData.assumingMemoryBound(to: Float.self)
            collected.append(contentsOf: UnsafeBufferPointer(start: ptr, count: count))
        }
        return collected
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
