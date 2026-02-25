import Foundation

struct ReleaseAsset: Decodable {
    let name: String
    let size: Int
    let downloadURL: URL
    
    private enum CodingKeys: String, CodingKey {
        case name
        case size
        case downloadURL = "browser_download_url"
    }
}

struct ReleaseInfo: Decodable {
    let tagName: String
    let body: String
    let publishedAt: Date
    let assets: [ReleaseAsset]
    let isDraft: Bool
    let isPrerelease: Bool
    
    var normalizedVersion: String {
        tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
    }
    
    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case body
        case publishedAt = "published_at"
        case assets
        case draft
        case prerelease
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tagName = try container.decode(String.self, forKey: .tagName)
        body = try container.decode(String.self, forKey: .body)
        assets = try container.decode([ReleaseAsset].self, forKey: .assets)
        publishedAt = try container.decode(Date.self, forKey: .publishedAt)
        isDraft = try container.decodeIfPresent(Bool.self, forKey: .draft) ?? false
        isPrerelease = try container.decodeIfPresent(Bool.self, forKey: .prerelease) ?? false
    }
}

struct UpdateOutcome {
    enum Result {
        case upToDate(remoteVersion: String)
        case installed(version: String, location: URL)
    }
    
    let result: Result
    let release: ReleaseInfo
}

enum UpdateStateEvent {
    case checking
    case foundRelease(ReleaseInfo)
    case downloadProgress(Double)
    case installing
}

enum UpdateError: LocalizedError {
    case networkFailure(Error)
    case decoding
    case noAsset
    case assetDownloadFailed
    case unzipFailed
    case bundleNotFound
    case installPermissionDenied(destination: URL, savedCopy: URL)
    case installFailed
    case unsupportedReleaseType
    
    var errorDescription: String? {
        switch self {
        case .networkFailure(let error):
            return "Network error: \(error.localizedDescription)"
        case .decoding:
            return "Unable to parse latest release information."
        case .noAsset:
            return "Could not find a downloadable release asset."
        case .assetDownloadFailed:
            return "Failed to download the release asset."
        case .unzipFailed:
            return "Could not unzip the downloaded archive."
        case .bundleNotFound:
            return "The downloaded archive did not contain an app bundle."
        case .installPermissionDenied(_, let savedCopy):
            return "Airakeet downloaded the update to \(savedCopy.path). Please move it into Applications manually."
        case .installFailed:
            return "Failed to install the downloaded update."
        case .unsupportedReleaseType:
            return "Latest release is marked as draft or prerelease."
        }
    }
}

private struct SemanticVersion: Comparable {
    let components: [Int]
    
    init(_ string: String) {
        components = string
            .split(separator: ".")
            .compactMap { Int($0.filter(\.isNumber)) }
    }
    
    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = lhs.components[safe: index] ?? 0
            let right = rhs.components[safe: index] ?? 0
            if left != right { return left < right }
        }
        return false
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}

@preconcurrency
final class UpdateManager: NSObject {
    private let owner: String
    private let repo: String
    init(owner: String, repo: String) {
        self.owner = owner
        self.repo = repo
    }
    
    @MainActor
    func checkAndInstall(currentVersion: String,
                         updateHandler: @escaping (UpdateStateEvent) -> Void) async throws -> UpdateOutcome {
        updateHandler(.checking)
        let release = try await fetchRelease()
        updateHandler(.foundRelease(release))
        
        let currentSemver = SemanticVersion(currentVersion)
        let remoteSemver = SemanticVersion(release.normalizedVersion)
        
        guard remoteSemver > currentSemver else {
            return UpdateOutcome(result: .upToDate(remoteVersion: release.normalizedVersion), release: release)
        }
        
        guard let asset = release.assets.first(where: { $0.name.hasSuffix(".zip") }) else {
            throw UpdateError.noAsset
        }
        
        updateHandler(.downloadProgress(0))
        let archiveURL = try await downloadAsset(asset: asset, handler: { progress in
            updateHandler(.downloadProgress(progress))
        })
        
        updateHandler(.installing)
        let installedURL = try installArchive(archiveURL, version: release.normalizedVersion)
        return UpdateOutcome(result: .installed(version: release.normalizedVersion, location: installedURL), release: release)
    }
    
    @MainActor
    private func fetchRelease() async throws -> ReleaseInfo {
        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("Airakeet/\(Bundle.main.shortVersion)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let release = try decoder.decode(ReleaseInfo.self, from: data)
            if release.isDraft || release.isPrerelease {
                throw UpdateError.unsupportedReleaseType
            }
            return release
        } catch let error as UpdateError {
            throw error
        } catch {
            if (error as NSError).domain == NSCocoaErrorDomain {
                throw UpdateError.decoding
            }
            throw UpdateError.networkFailure(error)
        }
    }
    
    @MainActor
    private func downloadAsset(asset: ReleaseAsset,
                               handler: @escaping (Double) -> Void) async throws -> URL {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("AirakeetUpdate", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let targetURL = tempRoot.appendingPathComponent(asset.name)
        if FileManager.default.fileExists(atPath: targetURL.path) {
            try FileManager.default.removeItem(at: targetURL)
        }
        
        var request = URLRequest(url: asset.downloadURL)
        request.setValue("Airakeet/\(Bundle.main.shortVersion)", forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        FileManager.default.createFile(atPath: targetURL.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: targetURL) else {
            throw UpdateError.assetDownloadFailed
        }
        defer {
            try? handle.close()
        }
        
        let expectedLength = asset.size > 0 ? Int64(asset.size) : response.expectedContentLength
        var received: Int64 = 0
        var chunk = Data()
        chunk.reserveCapacity(64 * 1024)
        
        func flushChunk() throws {
            guard !chunk.isEmpty else { return }
            try handle.write(contentsOf: chunk)
            chunk.removeAll(keepingCapacity: true)
        }
        
        func reportProgress() {
            guard expectedLength > 0 else { return }
            let ratio = min(1, Double(received) / Double(expectedLength))
            handler(ratio)
        }
        
        var iterator = bytes.makeAsyncIterator()
        while let byte = try await iterator.next() {
            chunk.append(byte)
            received += 1
            if chunk.count >= 64 * 1024 {
                try flushChunk()
                reportProgress()
            }
        }
        try flushChunk()
        reportProgress()
        
        if expectedLength > 0 && received != expectedLength {
            throw UpdateError.assetDownloadFailed
        }
        
        return targetURL
    }
    
    @MainActor
    private func installArchive(_ archiveURL: URL, version: String) throws -> URL {
        let cleanupRoot = archiveURL.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: cleanupRoot) }
        
        let extractDir = cleanupRoot.appendingPathComponent("Extracted-\(version)", isDirectory: true)
        if FileManager.default.fileExists(atPath: extractDir.path) {
            try FileManager.default.removeItem(at: extractDir)
        }
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
        try unzip(archiveURL, to: extractDir)
        
        guard let extractedApp = findAppBundle(in: extractDir) else {
            throw UpdateError.bundleNotFound
        }
        
        let destinationURL = Bundle.main.bundleURL
        let parent = destinationURL.deletingLastPathComponent()
        let tempBundleURL = parent.appendingPathComponent(destinationURL.lastPathComponent + ".tmp", isDirectory: true)
        if FileManager.default.fileExists(atPath: tempBundleURL.path) {
            try FileManager.default.removeItem(at: tempBundleURL)
        }
        try FileManager.default.moveItem(at: extractedApp, to: tempBundleURL)
        defer {
            if FileManager.default.fileExists(atPath: tempBundleURL.path) {
                try? FileManager.default.removeItem(at: tempBundleURL)
            }
        }
        
        do {
            let backupName = destinationURL.lastPathComponent + ".previous"
            let backupURL = try FileManager.default.replaceItemAt(destinationURL, withItemAt: tempBundleURL, backupItemName: backupName)
            if let backupURL {
                try? FileManager.default.removeItem(at: backupURL)
            }
            return destinationURL
        } catch {
            let downloads = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Downloads")
            let fallbackURL = downloads.appendingPathComponent("Airakeet-\(version).app")
            if copyAppBundle(tempBundleURL, to: fallbackURL) {
                throw UpdateError.installPermissionDenied(destination: destinationURL, savedCopy: fallbackURL)
            } else {
                throw UpdateError.installFailed
            }
        }
    }
    
    @MainActor
    private func unzip(_ archiveURL: URL, to destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archiveURL.path, destination.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdateError.unzipFailed
        }
    }
    
    private func findAppBundle(in directory: URL) -> URL? {
        let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isDirectoryKey])
        while let url = enumerator?.nextObject() as? URL {
            if url.pathExtension == "app" {
                return url
            }
        }
        return nil
    }
    
    @MainActor
    private func copyAppBundle(_ source: URL, to destination: URL) -> Bool {
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: source, to: destination)
            return true
        } catch {
            return false
        }
    }
}

private extension Bundle {
    var shortVersion: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }
}
