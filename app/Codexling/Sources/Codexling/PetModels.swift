import AppKit
import Foundation
import ImageIO

enum CodexPetSource: String, Sendable {
    case codexBuiltIn
    case custom

    var title: String {
        switch self {
        case .codexBuiltIn:
            "Codex 内置"
        case .custom:
            "自定义"
        }
    }
}

struct CodexPet: Identifiable, Hashable, Sendable {
    let id: String
    let assetID: String
    let displayName: String
    let description: String
    let source: CodexPetSource
    let spriteVersionNumber: Int
    let spritesheetURL: URL
    let rowCount: Int
}

private struct CustomPetManifest: Decodable {
    let id: String
    let displayName: String
    let description: String?
    let spriteVersionNumber: Int?
    let spritesheetPath: String
}

enum CodexlingPetInstaller {
    static let petID = "codexling"

    static func isInstalled(in petsRoot: URL = defaultPetsRoot) -> Bool {
        let directory = petsRoot.appendingPathComponent(petID, isDirectory: true)
        let manifestURL = directory.appendingPathComponent("pet.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(CustomPetManifest.self, from: data),
              manifest.id == petID else {
            return false
        }
        return FileManager.default.fileExists(
            atPath: directory.appendingPathComponent(manifest.spritesheetPath).path
        )
    }

    static func install(into petsRoot: URL = defaultPetsRoot) throws {
        let fileManager = FileManager.default
        let destination = petsRoot.appendingPathComponent(petID, isDirectory: true)
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw CocoaError(.fileWriteFileExists)
        }
        guard let source = bundledPetDirectory() else {
            throw CocoaError(.fileNoSuchFile)
        }

        try fileManager.createDirectory(at: petsRoot, withIntermediateDirectories: true)
        try fileManager.copyItem(at: source, to: destination)
    }

    static func bundledPetDirectory() -> URL? {
        Bundle.main.url(
            forResource: "pet",
            withExtension: "json",
            subdirectory: "Pets/Codexling"
        )?.deletingLastPathComponent()
    }

    private static var defaultPetsRoot: URL {
        CodexPetCatalog.defaultCustomPetsRoot
    }
}

struct CodexPetCatalog: Sendable {
    static var defaultCustomPetsRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/pets", isDirectory: true)
    }

    private struct BuiltInPetSpec: Sendable {
        let id: String
        let displayName: String
        let assetPrefix: String
    }

    private static let builtInPets = [
        BuiltInPetSpec(id: "codex", displayName: "Codex", assetPrefix: "codex-spritesheet-"),
        BuiltInPetSpec(id: "dewey", displayName: "Dewey", assetPrefix: "dewey-spritesheet-"),
        BuiltInPetSpec(id: "fireball", displayName: "Fireball", assetPrefix: "fireball-spritesheet-"),
        BuiltInPetSpec(id: "hoots", displayName: "Hoots", assetPrefix: "hoots-spritesheet-"),
        BuiltInPetSpec(id: "null-signal", displayName: "Null Signal", assetPrefix: "null-signal-spritesheet-"),
        BuiltInPetSpec(id: "rocky", displayName: "Rocky", assetPrefix: "rocky-spritesheet-"),
        BuiltInPetSpec(id: "seedy", displayName: "Seedy", assetPrefix: "seedy-spritesheet-"),
        BuiltInPetSpec(id: "stacky", displayName: "Stacky", assetPrefix: "stacky-spritesheet-"),
        BuiltInPetSpec(id: "bsod", displayName: "BSOD", assetPrefix: "bsod-spritesheet-")
    ]

    let customPetsRoot: URL
    let cacheRoot: URL
    let applicationURLs: [URL]

    init(
        customPetsRoot: URL? = nil,
        cacheRoot: URL? = nil,
        applicationURLs: [URL]? = nil
    ) {
        self.customPetsRoot = customPetsRoot
            ?? Self.defaultCustomPetsRoot

        if let cacheRoot {
            self.cacheRoot = cacheRoot
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            let nextCacheRoot = support
                .appendingPathComponent("Codexling", isDirectory: true)
                .appendingPathComponent("Pets", isDirectory: true)
            let legacyCacheRoot = support
                .appendingPathComponent("CodexLight", isDirectory: true)
                .appendingPathComponent("Pets", isDirectory: true)
            if !FileManager.default.fileExists(atPath: nextCacheRoot.path),
               FileManager.default.fileExists(atPath: legacyCacheRoot.path) {
                try? FileManager.default.createDirectory(
                    at: nextCacheRoot.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try? FileManager.default.copyItem(at: legacyCacheRoot, to: nextCacheRoot)
            }
            self.cacheRoot = nextCacheRoot
        }

        self.applicationURLs = applicationURLs ?? Self.defaultCodexApplicationURLs()
    }

    func discover() -> [CodexPet] {
        let builtIns = discoverBuiltInPets()
        let custom = discoverCustomPets()
        return (builtIns + custom).sorted {
            if $0.source != $1.source {
                return $0.source == .codexBuiltIn
            }
            return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    private func discoverCustomPets() -> [CodexPet] {
        guard let directories = try? FileManager.default.contentsOfDirectory(
            at: customPetsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return directories.compactMap { directory in
            let manifestURL = directory.appendingPathComponent("pet.json")
            guard let data = try? Data(contentsOf: manifestURL),
                  let manifest = try? JSONDecoder().decode(CustomPetManifest.self, from: data) else {
                return nil
            }

            let spritesheetURL = directory.appendingPathComponent(manifest.spritesheetPath)
            guard let dimensions = imageDimensions(at: spritesheetURL),
                  dimensions.width == PetSpriteSheet.cellWidth * 8,
                  dimensions.height % PetSpriteSheet.cellHeight == 0 else {
                return nil
            }

            let rowCount = dimensions.height / PetSpriteSheet.cellHeight
            guard rowCount >= 9 else { return nil }
            let version = manifest.spriteVersionNumber ?? (rowCount >= 11 ? 2 : 1)

            return CodexPet(
                id: "custom:\(manifest.id)",
                assetID: manifest.id,
                displayName: manifest.displayName,
                description: manifest.description ?? "Codex 自定义 Pet",
                source: .custom,
                spriteVersionNumber: version,
                spritesheetURL: spritesheetURL,
                rowCount: rowCount
            )
        }
    }

    private func discoverBuiltInPets() -> [CodexPet] {
        for applicationURL in applicationURLs {
            let asarURL = applicationURL
                .appendingPathComponent("Contents/Resources/app.asar")
            guard FileManager.default.fileExists(atPath: asarURL.path),
                  let archive = try? AsarArchive(url: asarURL) else {
                continue
            }

            let version = (Bundle(url: applicationURL)?.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String) ?? "current"
            let versionCache = cacheRoot.appendingPathComponent(version, isDirectory: true)
            try? FileManager.default.createDirectory(
                at: versionCache,
                withIntermediateDirectories: true
            )

            return Self.builtInPets.compactMap { spec in
                guard let entry = archive.firstEntry(where: { path in
                    let name = URL(fileURLWithPath: path).lastPathComponent
                    return path.contains("/webview/assets/")
                        && name.hasPrefix(spec.assetPrefix)
                        && name.hasSuffix(".webp")
                }) else {
                    return nil
                }

                let destination = versionCache.appendingPathComponent(entry.name)
                if !FileManager.default.fileExists(atPath: destination.path) {
                    guard (try? archive.extract(entry, to: destination)) != nil else {
                        return nil
                    }
                }

                guard let dimensions = imageDimensions(at: destination),
                      dimensions.width == PetSpriteSheet.cellWidth * 8,
                      dimensions.height % PetSpriteSheet.cellHeight == 0 else {
                    try? FileManager.default.removeItem(at: destination)
                    return nil
                }

                let rowCount = dimensions.height / PetSpriteSheet.cellHeight
                return CodexPet(
                    id: "builtin:\(spec.id)",
                    assetID: spec.id,
                    displayName: spec.displayName,
                    description: "随 Codex 安装的内置 Pet",
                    source: .codexBuiltIn,
                    spriteVersionNumber: rowCount >= 11 ? 2 : 1,
                    spritesheetURL: destination,
                    rowCount: rowCount
                )
            }
        }

        return []
    }

    private static func defaultCodexApplicationURLs() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var urls = [
            URL(fileURLWithPath: "/Applications/ChatGPT.app"),
            URL(fileURLWithPath: "/Applications/Codex.app"),
            home.appendingPathComponent("Applications/ChatGPT.app"),
            home.appendingPathComponent("Applications/Codex.app")
        ]
        if let installed = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.openai.codex"
        ) {
            urls.insert(installed, at: 0)
        }

        var seen = Set<String>()
        return urls.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }
}

private func imageDimensions(at url: URL) -> (width: Int, height: Int)? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? Int,
          let height = properties[kCGImagePropertyPixelHeight] as? Int else {
        return nil
    }
    return (width, height)
}

struct AsarEntry: Sendable {
    let path: String
    let name: String
    let offset: UInt64
    let size: Int
}

struct AsarArchive: Sendable {
    let url: URL
    let contentOffset: UInt64
    let entries: [AsarEntry]

    init(url: URL) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        guard let prefix = try handle.read(upToCount: 16), prefix.count == 16 else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let headerPickleSize = prefix.littleEndianUInt32(at: 4)
        let headerJSONSize = prefix.littleEndianUInt32(at: 12)
        guard headerJSONSize > 0 else { throw CocoaError(.fileReadCorruptFile) }

        let headerData = try handle.read(upToCount: Int(headerJSONSize)) ?? Data()
        guard headerData.count == Int(headerJSONSize),
              let root = try JSONSerialization.jsonObject(with: headerData) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }

        self.url = url
        contentOffset = UInt64(8 + headerPickleSize)
        entries = Self.collectEntries(root: root)
    }

    func firstEntry(where predicate: (String) -> Bool) -> AsarEntry? {
        entries.first { predicate($0.path) }
    }

    func extract(_ entry: AsarEntry, to destination: URL) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: contentOffset + entry.offset)
        guard let data = try handle.read(upToCount: entry.size), data.count == entry.size else {
            throw CocoaError(.fileReadCorruptFile)
        }

        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: destination, options: .atomic)
    }

    private static func collectEntries(root: [String: Any]) -> [AsarEntry] {
        var result: [AsarEntry] = []

        func visit(_ node: [String: Any], path: String) {
            guard let files = node["files"] as? [String: Any] else { return }
            for (name, rawChild) in files {
                guard let child = rawChild as? [String: Any] else { continue }
                let childPath = "\(path)/\(name)"
                if let size = child["size"] as? Int,
                   let offsetText = child["offset"] as? String,
                   let offset = UInt64(offsetText) {
                    result.append(AsarEntry(
                        path: childPath,
                        name: name,
                        offset: offset,
                        size: size
                    ))
                }
                visit(child, path: childPath)
            }
        }

        visit(root, path: "")
        return result
    }
}

private extension Data {
    func littleEndianUInt32(at offset: Int) -> UInt32 {
        withUnsafeBytes { rawBuffer in
            let bytes = rawBuffer.bindMemory(to: UInt8.self)
            return UInt32(bytes[offset])
                | UInt32(bytes[offset + 1]) << 8
                | UInt32(bytes[offset + 2]) << 16
                | UInt32(bytes[offset + 3]) << 24
        }
    }
}

enum PetAnimationState: String, Sendable, CaseIterable {
    case idle
    case running
    case review
    case waiting
    case failed
    case waving
    case jumping

    static var idleInteractionCandidates: [PetAnimationState] {
        allCases.filter { $0 != .idle }
    }
}

struct PetAnimationFrame: Equatable, Sendable {
    let row: Int
    let column: Int
    let duration: TimeInterval
}

struct PetAnimationSequence: Equatable, Sendable {
    let frames: [PetAnimationFrame]
    let loopStartIndex: Int?
}

enum PetAnimationContract {
    private static let idle = frames(
        row: 0,
        durations: [280, 110, 110, 140, 140, 320]
    )

    static func sequence(
        for state: PetAnimationState,
        reducedMotion: Bool
    ) -> PetAnimationSequence {
        let stateFrames: [PetAnimationFrame] = switch state {
        case .idle:
            idle
        case .running:
            frames(row: 7, count: 6, duration: 120, finalDuration: 220)
        case .review:
            frames(row: 8, count: 6, duration: 150, finalDuration: 280)
        case .waiting:
            frames(row: 6, count: 6, duration: 150, finalDuration: 260)
        case .failed:
            frames(row: 5, count: 8, duration: 140, finalDuration: 240)
        case .waving:
            frames(row: 3, count: 4, duration: 140, finalDuration: 280)
        case .jumping:
            frames(row: 4, count: 5, duration: 140, finalDuration: 280)
        }

        if reducedMotion {
            return PetAnimationSequence(frames: [stateFrames[0]], loopStartIndex: nil)
        }

        let slowIdle = idle.map {
            PetAnimationFrame(row: $0.row, column: $0.column, duration: $0.duration * 6)
        }
        if state == .idle {
            return PetAnimationSequence(frames: slowIdle, loopStartIndex: 0)
        }

        let reaction = stateFrames + stateFrames + stateFrames
        return PetAnimationSequence(
            frames: reaction + slowIdle,
            loopStartIndex: reaction.count
        )
    }

    static func oneShotSequence(
        for state: PetAnimationState,
        reducedMotion: Bool
    ) -> PetAnimationSequence {
        let stateFrames: [PetAnimationFrame] = switch state {
        case .idle:
            idle
        case .running:
            frames(row: 7, count: 6, duration: 120, finalDuration: 220)
        case .review:
            frames(row: 8, count: 6, duration: 150, finalDuration: 280)
        case .waiting:
            frames(row: 6, count: 6, duration: 150, finalDuration: 260)
        case .failed:
            frames(row: 5, count: 8, duration: 140, finalDuration: 240)
        case .waving:
            frames(row: 3, count: 4, duration: 140, finalDuration: 280)
        case .jumping:
            frames(row: 4, count: 5, duration: 140, finalDuration: 280)
        }

        if reducedMotion {
            return PetAnimationSequence(frames: [stateFrames[0]], loopStartIndex: nil)
        }

        let reaction = stateFrames + stateFrames + stateFrames
        return PetAnimationSequence(frames: reaction, loopStartIndex: nil)
    }

    private static func frames(row: Int, durations: [Int]) -> [PetAnimationFrame] {
        durations.enumerated().map { column, duration in
            PetAnimationFrame(
                row: row,
                column: column,
                duration: TimeInterval(duration) / 1_000
            )
        }
    }

    private static func frames(
        row: Int,
        count: Int,
        duration: Int,
        finalDuration: Int
    ) -> [PetAnimationFrame] {
        frames(
            row: row,
            durations: (0..<count).map { $0 == count - 1 ? finalDuration : duration }
        )
    }
}

@MainActor
final class PetSpriteSheet {
    nonisolated static let cellWidth = 192
    nonisolated static let cellHeight = 208

    private let image: CGImage
    let rowCount: Int

    init?(url: URL) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width == Self.cellWidth * 8,
              image.height % Self.cellHeight == 0 else {
            return nil
        }
        self.image = image
        rowCount = image.height / Self.cellHeight
    }

    func frame(row: Int, column: Int, displayHeight: CGFloat = 21) -> NSImage? {
        guard row >= 0, row < rowCount, column >= 0, column < 8 else { return nil }
        let cropRect = CGRect(
            x: column * Self.cellWidth,
            y: row * Self.cellHeight,
            width: Self.cellWidth,
            height: Self.cellHeight
        )
        guard let cropped = image.cropping(to: cropRect) else { return nil }
        let displayWidth = displayHeight * CGFloat(Self.cellWidth) / CGFloat(Self.cellHeight)
        return NSImage(cgImage: cropped, size: NSSize(width: displayWidth, height: displayHeight))
    }
}

@MainActor
final class PetAnimationPlayer {
    var onFrame: ((NSImage?) -> Void)?

    private var sheet: PetSpriteSheet?
    private var petID: String?
    private var state: PetAnimationState = .idle
    private var sequence = PetAnimationContract.sequence(for: .idle, reducedMotion: false)
    private var frameIndex = 0
    private var timer: Timer?
    private(set) var isPlayingOneShot = false
    private var oneShotCompletion: (() -> Void)?

    func setPet(_ pet: CodexPet?) {
        guard pet?.id != petID else { return }
        petID = pet?.id
        sheet = pet.flatMap { PetSpriteSheet(url: $0.spritesheetURL) }
        restart()
    }

    func setState(_ newState: PetAnimationState) {
        guard !isPlayingOneShot else { return }
        guard newState != state else { return }
        state = newState
        restart()
    }

    func playOneShot(_ action: PetAnimationState, onComplete: @escaping () -> Void) {
        guard action != .idle else { return }
        stop()
        isPlayingOneShot = true
        oneShotCompletion = onComplete
        state = action
        let reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        sequence = PetAnimationContract.oneShotSequence(for: action, reducedMotion: reducedMotion)
        frameIndex = 0
        showCurrentFrame()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isPlayingOneShot = false
        oneShotCompletion = nil
    }

    private func restart() {
        stop()
        isPlayingOneShot = false
        let reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        sequence = PetAnimationContract.sequence(for: state, reducedMotion: reducedMotion)
        frameIndex = 0
        showCurrentFrame()
    }

    private func finishOneShot() {
        isPlayingOneShot = false
        let completion = oneShotCompletion
        oneShotCompletion = nil
        completion?()
    }

    private func showCurrentFrame() {
        guard !sequence.frames.isEmpty else {
            onFrame?(nil)
            return
        }

        let frame = sequence.frames[frameIndex]
        onFrame?(sheet?.frame(row: frame.row, column: frame.column))
        guard sequence.frames.count > 1 else { return }

        timer = Timer.scheduledTimer(withTimeInterval: frame.duration, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.advance()
            }
        }
    }

    private func advance() {
        let next = frameIndex + 1
        if next < sequence.frames.count {
            frameIndex = next
        } else if isPlayingOneShot {
            finishOneShot()
            return
        } else if let loopStartIndex = sequence.loopStartIndex {
            frameIndex = loopStartIndex
        } else {
            return
        }
        showCurrentFrame()
    }
}
