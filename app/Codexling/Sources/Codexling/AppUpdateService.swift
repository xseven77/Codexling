import AppKit
import Foundation
import Observation

enum AppUpdatePhase: Equatable {
    case idle
    case checking
    case upToDate
    case available
    case downloading
    case installing
    case failed(String)

    var isBusy: Bool {
        switch self {
        case .checking, .downloading, .installing:
            true
        default:
            false
        }
    }
}

struct AppReleaseInfo: Equatable {
    let tagName: String
    let version: String
    let name: String
    let releaseNotes: String
    let htmlURL: URL
    let downloadURL: URL
    let assetName: String
    let assetSize: Int64
}

@MainActor
@Observable
final class AppUpdateController {
    private enum Constants {
        static let repo = "xseven77/Codexling"
        static let latestReleaseURL = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
        static let releasesPageURL = URL(string: "https://github.com/\(repo)/releases")!
    }

    private(set) var phase: AppUpdatePhase = .idle
    private(set) var latestRelease: AppReleaseInfo?
    private(set) var downloadProgress: Double = 0
    private(set) var lastCheckedAt: Date?

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    var currentBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    var statusText: String {
        switch phase {
        case .idle:
            if let lastCheckedAt {
                return "上次检查：\(UsageDateFormat.display(lastCheckedAt))"
            }
            return "当前版本 \(currentVersion)（\(currentBuild)）"
        case .checking:
            return "正在检查更新…"
        case .upToDate:
            return "已是最新版本 \(currentVersion)"
        case .available:
            if let latestRelease {
                return "发现新版本 \(latestRelease.version)"
            }
            return "发现新版本"
        case .downloading:
            return "正在下载… \(Int((downloadProgress * 100).rounded()))%"
        case .installing:
            return "正在安装并准备重启…"
        case .failed(let message):
            return message
        }
    }

    func openReleasesPage() {
        NSWorkspace.shared.open(Constants.releasesPageURL)
    }

    func checkForUpdates() {
        guard !phase.isBusy else { return }

        phase = .checking
        latestRelease = nil
        downloadProgress = 0

        Task { [weak self] in
            guard let self else { return }
            do {
                let release = try await self.fetchLatestRelease()
                self.lastCheckedAt = Date()
                self.latestRelease = release

                if Self.compareVersions(release.version, self.currentVersion) > 0 {
                    self.phase = .available
                } else {
                    self.phase = .upToDate
                }
            } catch {
                self.phase = .failed(error.localizedDescription)
            }
        }
    }

    func downloadAndInstall() {
        guard case .available = phase, let release = latestRelease else { return }
        guard !phase.isBusy else { return }

        phase = .downloading
        downloadProgress = 0

        Task { [weak self] in
            guard let self else { return }
            do {
                let dmgURL = try await self.downloadDMG(from: release)
                self.phase = .installing
                try await self.installFromDMG(at: dmgURL, expectedAppName: "Codexling.app")
                self.relaunchAfterInstall()
            } catch {
                self.phase = .failed(error.localizedDescription)
            }
        }
    }

    private func fetchLatestRelease() async throws -> AppReleaseInfo {
        var request = URLRequest(url: Constants.latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AppUpdateError.network
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AppUpdateError.httpStatus(http.statusCode)
        }

        let decoded = try JSONDecoder().decode(GitHubLatestReleaseDTO.self, from: data)
        let version = Self.normalizeVersion(decoded.tagName)
        guard let htmlURL = URL(string: decoded.htmlURL) else {
            throw AppUpdateError.invalidRelease
        }

        let dmgAsset = decoded.assets.first { asset in
            let name = asset.name.lowercased()
            return name.hasSuffix(".dmg") && name.contains("codex")
        } ?? decoded.assets.first { $0.name.lowercased().hasSuffix(".dmg") }

        guard let dmgAsset, let downloadURL = URL(string: dmgAsset.browserDownloadURL) else {
            throw AppUpdateError.missingDMG
        }

        return AppReleaseInfo(
            tagName: decoded.tagName,
            version: version,
            name: decoded.name ?? decoded.tagName,
            releaseNotes: decoded.body ?? "",
            htmlURL: htmlURL,
            downloadURL: downloadURL,
            assetName: dmgAsset.name,
            assetSize: dmgAsset.size
        )
    }

    private func downloadDMG(from release: AppReleaseInfo) async throws -> URL {
        let downloads = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexlingUpdates", isDirectory: true)
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)

        let destination = downloads.appendingPathComponent(release.assetName)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }

        downloadProgress = 0.02
        let tempURL = try await DownloadProgressSession.download(
            from: release.downloadURL,
            expectedSize: release.assetSize
        ) { [weak self] fraction in
            Task { @MainActor in
                self?.downloadProgress = min(max(fraction, 0.02), 0.99)
            }
        }

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: tempURL, to: destination)
        downloadProgress = 1
        return destination
    }

    private func installFromDMG(at dmgURL: URL, expectedAppName: String) async throws {
        let mountPoint = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexlingMount-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)

        defer {
            _ = try? runProcess("/usr/bin/hdiutil", ["detach", mountPoint.path, "-quiet", "-force"])
            try? FileManager.default.removeItem(at: mountPoint)
        }

        try runProcess("/usr/bin/hdiutil", [
            "attach", dmgURL.path,
            "-nobrowse",
            "-readonly",
            "-mountpoint", mountPoint.path
        ])

        let mountedApp = mountPoint.appendingPathComponent(expectedAppName)
        guard FileManager.default.fileExists(atPath: mountedApp.path) else {
            throw AppUpdateError.missingAppInDMG
        }

        let currentAppURL = Bundle.main.bundleURL
        let installTarget: URL
        if currentAppURL.pathExtension == "app" {
            installTarget = currentAppURL
        } else {
            installTarget = URL(fileURLWithPath: "/Applications/Codexling.app")
        }

        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("Codexling-update.app", isDirectory: true)
        if FileManager.default.fileExists(atPath: staging.path) {
            try FileManager.default.removeItem(at: staging)
        }

        try FileManager.default.copyItem(at: mountedApp, to: staging)

        // Replace the running app after quit via a short shell helper.
        let script = """
        #!/bin/bash
        set -euo pipefail
        sleep 1
        /usr/bin/ditto "$1" "$2"
        /usr/bin/xattr -dr com.apple.quarantine "$2" || true
        /usr/bin/open "$2"
        /bin/rm -rf "$1"
        """

        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexling-install-\(UUID().uuidString).sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptURL.path, staging.path, installTarget.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    private func relaunchAfterInstall() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            NSApp.terminate(nil)
        }
    }

    private func runProcess(_ launchPath: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let stderr = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = stderr.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw AppUpdateError.shellFailed(message?.isEmpty == false ? message! : launchPath)
        }
    }

    static func normalizeVersion(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.lowercased().hasPrefix("v") {
            value.removeFirst()
        }
        return value
    }

    /// Returns 1 if lhs > rhs, -1 if lhs < rhs, 0 if equal.
    static func compareVersions(_ lhs: String, _ rhs: String) -> Int {
        let left = normalizeVersion(lhs).split(separator: ".").compactMap { Int($0) }
        let right = normalizeVersion(rhs).split(separator: ".").compactMap { Int($0) }
        let count = max(left.count, right.count)
        for index in 0..<count {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l > r { return 1 }
            if l < r { return -1 }
        }
        return 0
    }
}

enum AppUpdateError: LocalizedError {
    case network
    case httpStatus(Int)
    case invalidRelease
    case missingDMG
    case missingAppInDMG
    case shellFailed(String)

    var errorDescription: String? {
        switch self {
        case .network:
            "网络请求失败，请稍后重试"
        case .httpStatus(let code):
            "检查更新失败（HTTP \(code)）"
        case .invalidRelease:
            "无法解析 GitHub Release 信息"
        case .missingDMG:
            "最新 Release 中未找到 DMG 安装包"
        case .missingAppInDMG:
            "DMG 中未找到 Codexling.app"
        case .shellFailed(let detail):
            "安装失败：\(detail)"
        }
    }
}

private struct GitHubLatestReleaseDTO: Decodable {
    let tagName: String
    let name: String?
    let body: String?
    let htmlURL: String
    let assets: [GitHubAssetDTO]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlURL = "html_url"
        case assets
    }
}

private struct GitHubAssetDTO: Decodable {
    let name: String
    let size: Int64
    let browserDownloadURL: String

    enum CodingKeys: String, CodingKey {
        case name
        case size
        case browserDownloadURL = "browser_download_url"
    }
}

private final class DownloadProgressSession: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private var continuation: CheckedContinuation<URL, Error>?
    private let onProgress: @Sendable (Double) -> Void
    private let expectedSize: Int64
    private var session: URLSession?

    private init(expectedSize: Int64, onProgress: @escaping @Sendable (Double) -> Void) {
        self.expectedSize = expectedSize
        self.onProgress = onProgress
    }

    static func download(
        from url: URL,
        expectedSize: Int64,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let bridge = DownloadProgressSession(expectedSize: expectedSize, onProgress: onProgress)
            bridge.continuation = continuation
            let session = URLSession(configuration: .ephemeral, delegate: bridge, delegateQueue: nil)
            bridge.session = session
            session.downloadTask(with: url).resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : max(expectedSize, 1)
        onProgress(Double(totalBytesWritten) / Double(total))
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        do {
            let temp = FileManager.default.temporaryDirectory
                .appendingPathComponent("codexling-dl-\(UUID().uuidString).dmg")
            if FileManager.default.fileExists(atPath: temp.path) {
                try FileManager.default.removeItem(at: temp)
            }
            try FileManager.default.copyItem(at: location, to: temp)
            finish(.success(temp))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            finish(.failure(error))
        }
    }

    private func finish(_ result: Result<URL, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
        session?.finishTasksAndInvalidate()
        session = nil
    }
}
