import Foundation

// MARK: - Plugin Manifest Data Model

public struct WebPluginManifest: Codable, Equatable, Sendable {
    public let name: String
    public let version: String
    public let build: Int?
    public let minCodexlingVersion: String?
    public let description: String?
    public let author: String?
    public let entry: String?

    public init(
        name: String = "codexling-mobile-web",
        version: String = "1.0.0",
        build: Int? = 1,
        minCodexlingVersion: String? = "0.7.3",
        description: String? = nil,
        author: String? = nil,
        entry: String? = "index.html"
    ) {
        self.name = name
        self.version = version
        self.build = build
        self.minCodexlingVersion = minCodexlingVersion
        self.description = description
        self.author = author
        self.entry = entry
    }
}

public struct WebPluginStatus: Equatable, Sendable {
    public let isInstalled: Bool
    public let manifest: WebPluginManifest?
    public let pluginDirectory: URL
    public let totalSizeBytes: Int64

    public var displayVersion: String {
        manifest?.version ?? "未知"
    }

    public var displaySizeString: String {
        ByteCountFormatter.string(fromByteCount: totalSizeBytes, countStyle: .file)
    }

    public init(
        isInstalled: Bool,
        manifest: WebPluginManifest?,
        pluginDirectory: URL,
        totalSizeBytes: Int64
    ) {
        self.isInstalled = isInstalled
        self.manifest = manifest
        self.pluginDirectory = pluginDirectory
        self.totalSizeBytes = totalSizeBytes
    }
}

// MARK: - Web Plugin Installer

public final class WebPluginInstaller: @unchecked Sendable {
    public static let shared = WebPluginInstaller()

    public static let defaultReleaseURL = URL(
        string: "https://github.com/xseven77/CodexlingMobileWebPlugin-release/releases/latest/download/mobile-web-plugin.zip"
    )!

    public let pluginDirectory: URL
    private let fileManager = FileManager.default

    public init(pluginDirectory: URL = MobileSyncServer.defaultPluginDirectoryURL) {
        self.pluginDirectory = pluginDirectory
    }

    // MARK: - Status Checking

    public func currentStatus() -> WebPluginStatus {
        let indexFile = pluginDirectory.appendingPathComponent("index.html")
        guard fileManager.fileExists(atPath: indexFile.path) else {
            return WebPluginStatus(
                isInstalled: false,
                manifest: nil,
                pluginDirectory: pluginDirectory,
                totalSizeBytes: 0
            )
        }

        let manifestFile = pluginDirectory.appendingPathComponent("plugin-manifest.json")
        var manifest: WebPluginManifest?
        if let data = try? Data(contentsOf: manifestFile),
           let decoded = try? JSONDecoder().decode(WebPluginManifest.self, from: data) {
            manifest = decoded
        }

        let size = calculateDirectorySize(at: pluginDirectory)
        return WebPluginStatus(
            isInstalled: true,
            manifest: manifest,
            pluginDirectory: pluginDirectory,
            totalSizeBytes: size
        )
    }

    // MARK: - Installation

    public func install(fromLocalZip zipURL: URL) throws {
        let tempExtractDir = fileManager.temporaryDirectory.appendingPathComponent("codexling-plugin-\(UUID().uuidString)")
        try fileManager.createDirectory(at: tempExtractDir, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: tempExtractDir)
        }

        // 1. 使用 /usr/bin/ditto 解压 zip
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-xk", zipURL.path, tempExtractDir.path]

        let pipe = Pipe()
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorMsg = String(data: errorData, encoding: .utf8) ?? "ditto failed"
            throw NSError(domain: "WebPluginInstaller", code: 1, userInfo: [NSLocalizedDescriptionKey: "解压失败: \(errorMsg)"])
        }

        // 2. 探查有效资源根目录（若压缩包外层有单一文件夹包裹，则深入该层）
        let sourceDir = resolveSourceDirectory(in: tempExtractDir)
        let indexFile = sourceDir.appendingPathComponent("index.html")
        guard fileManager.fileExists(atPath: indexFile.path) else {
            throw NSError(domain: "WebPluginInstaller", code: 2, userInfo: [NSLocalizedDescriptionKey: "插件包中缺少 index.html，不是合法的 Web 插件"])
        }

        // 3. 准备目标插件目录
        try fileManager.createDirectory(at: pluginDirectory.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: pluginDirectory.path) {
            try fileManager.removeItem(at: pluginDirectory)
        }

        // 4. 原子移动至正式插件目录
        try fileManager.moveItem(at: sourceDir, to: pluginDirectory)
    }

    public func downloadAndInstall(
        from remoteURL: URL = defaultReleaseURL,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        let session = URLSession(configuration: .default)
        let (tempDownloadedURL, response) = try await session.download(from: remoteURL)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw NSError(
                domain: "WebPluginInstaller",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "下载插件失败: HTTP 状态码 \(code)"]
            )
        }

        onProgress?(1.0)
        try install(fromLocalZip: tempDownloadedURL)
        try? fileManager.removeItem(at: tempDownloadedURL)
    }

    public func uninstall() throws {
        if fileManager.fileExists(atPath: pluginDirectory.path) {
            try fileManager.removeItem(at: pluginDirectory)
        }
    }

    // MARK: - Helpers

    private func resolveSourceDirectory(in directory: URL) -> URL {
        if fileManager.fileExists(atPath: directory.appendingPathComponent("index.html").path) {
            return directory
        }

        if let contents = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles),
           contents.count == 1,
           let first = contents.first,
           (try? first.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
           fileManager.fileExists(atPath: first.appendingPathComponent("index.html").path) {
            return first
        }

        return directory
    }

    private func calculateDirectorySize(at url: URL) -> Int64 {
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else {
            return 0
        }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey]), let size = values.fileSize {
                total += Int64(size)
            }
        }
        return total
    }
}
