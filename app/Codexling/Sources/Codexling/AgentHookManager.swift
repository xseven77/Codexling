import Foundation

enum AgentHookInstallationState: Equatable, Sendable {
    case builtIn
    case notInstalled
    case authorizationRequired
    case installed
    case unavailable(String)
    case conflict(String)
    case failed(String)
}

struct AgentIntegrationStatus: Identifiable, Equatable, Sendable {
    let id: AgentID
    let name: String
    let priority: Int
    var cliInstalled: Bool
    var desktopInstalled: Bool
    var hookState: AgentHookInstallationState
    var detail: String
}

enum AgentHookManagerError: LocalizedError, Equatable {
    case unsupportedAgent
    case helperMissing
    case malformedConfiguration(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedAgent:
            "当前 Agent 不支持 Attached Hook"
        case .helperMissing:
            "安装包中缺少 codexling-agent-bridge"
        case .malformedConfiguration(let message):
            message
        }
    }
}

struct AgentHookManager {
    static let commandMarker = "codexling-agent-bridge"
    private static let hermesMarker = "# codexling-agent-hook"
    private static let hermesEvents = [
        "on_session_start",
        "pre_llm_call",
        "pre_tool_call",
        "pre_approval_request",
        "post_approval_response",
        "post_tool_call",
        "on_session_end",
    ]

    let fileManager: FileManager
    let homeDirectory: URL
    let applicationSupportDirectory: URL
    let helperSourceURL: URL?

    init(
        fileManager: FileManager = .default,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        applicationSupportDirectory: URL? = nil,
        helperSourceURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory
        self.applicationSupportDirectory = applicationSupportDirectory
            ?? homeDirectory.appendingPathComponent("Library/Application Support/Codexling", isDirectory: true)
        self.helperSourceURL = helperSourceURL
    }

    var installedHelperURL: URL {
        applicationSupportDirectory
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent(Self.commandMarker)
    }

    func integrationStatuses() -> [AgentIntegrationStatus] {
        BuiltInAgentCatalog.prioritized.map { descriptor in
            let cliInstalled = locateExecutable(for: descriptor.id) != nil
            let desktopInstalled = desktopApplicationExists(for: descriptor.id)
            let hookState: AgentHookInstallationState
            if descriptor.id == .codex {
                // Codex activity is observed through Codexling's built-in App
                // Server/local activity adapters. Never require or mutate a
                // user-level Codex Hook configuration.
                hookState = .builtIn
            } else if !cliInstalled && !desktopInstalled {
                hookState = .unavailable("未发现官方 CLI 或 Desktop")
            } else if descriptor.id == .hermes, isHookInstalled(for: .hermes) {
                hookState = areHermesHooksAuthorized() ? .installed : .authorizationRequired
            } else {
                hookState = isHookInstalled(for: descriptor.id) ? .installed : .notInstalled
            }
            return AgentIntegrationStatus(
                id: descriptor.id,
                name: descriptor.displayName,
                priority: descriptor.priority,
                cliInstalled: cliInstalled,
                desktopInstalled: desktopInstalled,
                hookState: hookState,
                detail: integrationDetail(
                    for: descriptor.id,
                    cliInstalled: cliInstalled,
                    desktopInstalled: desktopInstalled
                )
            )
        }
    }

    func installHook(for agentID: AgentID) throws {
        guard agentID != .codex else {
            throw AgentHookManagerError.unsupportedAgent
        }
        let helper = try installBridgeHelperIfNeeded()
        switch agentID {
        case .codex:
            throw AgentHookManagerError.unsupportedAgent
        case .claudeCode:
            try mergeNestedJSONHooks(
                at: configURL(for: agentID),
                agentID: agentID,
                surface: .claudeCodeCLI,
                events: ["SessionStart", "UserPromptSubmit", "PreToolUse", "PermissionRequest", "PostToolUse", "PostToolUseFailure", "Stop", "SessionEnd"],
                helper: helper
            )
        case .reasonix:
            try mergeDirectJSONHooks(
                at: configURL(for: agentID),
                agentID: agentID,
                surface: .reasonixCLI,
                events: ["SessionStart", "UserPromptSubmit", "PreToolUse", "PermissionRequest", "PostToolUse", "PostToolUseFailure", "Stop", "SessionEnd"],
                helper: helper
            )
        case .hermes:
            // Rebuild our managed entries so an existing install cannot retain
            // stale Bridge paths or commands that no longer match the allowlist.
            try removeHermesHooks(at: configURL(for: agentID))
            try mergeHermesHooks(at: configURL(for: agentID), helper: helper)
            try authorizeHermesHooks(helper: helper)
        default:
            throw AgentHookManagerError.unsupportedAgent
        }
    }

    func uninstallHook(for agentID: AgentID) throws {
        switch agentID {
        case .codex:
            throw AgentHookManagerError.unsupportedAgent
        case .claudeCode:
            try removeNestedJSONHooks(at: configURL(for: agentID))
        case .reasonix:
            try removeDirectJSONHooks(at: configURL(for: agentID))
        case .hermes:
            try removeHermesHooks(at: configURL(for: agentID))
            try revokeHermesHookAuthorization()
        default:
            throw AgentHookManagerError.unsupportedAgent
        }
    }

    func isHookInstalled(for agentID: AgentID) -> Bool {
        let url = configURL(for: agentID)
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return false
        }
        return text.contains(Self.commandMarker)
    }

    func areHermesHooksAuthorized() -> Bool {
        guard isHookInstalled(for: .hermes),
              let approvals = try? readHermesApprovals() else {
            return false
        }
        let approvedPairs = Set(approvals.compactMap { entry -> String? in
            guard let event = entry["event"] as? String,
                  let command = entry["command"] as? String else { return nil }
            return "\(event)\u{0}\(command)"
        })
        return hermesCommands(helper: installedHelperURL).allSatisfy { pair in
            approvedPairs.contains("\(pair.event)\u{0}\(pair.command)")
        }
    }

    func configURL(for agentID: AgentID) -> URL {
        switch agentID {
        case .codex:
            homeDirectory.appendingPathComponent(".codex/hooks.json")
        case .hermes:
            homeDirectory.appendingPathComponent(".hermes/config.yaml")
        case .claudeCode:
            homeDirectory.appendingPathComponent(".claude/settings.json")
        case .reasonix:
            homeDirectory.appendingPathComponent(".reasonix/hooks/hooks.json")
        default:
            applicationSupportDirectory.appendingPathComponent("unsupported-hooks.json")
        }
    }

    private func installBridgeHelperIfNeeded() throws -> URL {
        let destination = installedHelperURL
        let parent = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)

        let source = helperSourceURL ?? discoverBridgeHelper()
        guard let source, fileManager.isExecutableFile(atPath: source.path) else {
            throw AgentHookManagerError.helperMissing
        }

        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
        return destination
    }

    private func discoverBridgeHelper() -> URL? {
        let candidates = [
            Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/CodexlingAgentBridge"),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/codexling-agent-bridge"),
            Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("CodexlingAgentBridge"),
        ].compactMap { $0 }
        return candidates.first { fileManager.isExecutableFile(atPath: $0.path) }
    }

    private func locateExecutable(for agentID: AgentID) -> URL? {
        let executable: String
        switch agentID {
        case .codex: executable = "codex"
        case .hermes: executable = "hermes"
        case .claudeCode: executable = "claude"
        case .reasonix: executable = "reasonix"
        default: return nil
        }

        let prefixes = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            homeDirectory.appendingPathComponent(".local/bin").path,
            homeDirectory.appendingPathComponent(".nvm/current/bin").path,
        ]
        for prefix in prefixes {
            let candidate = URL(fileURLWithPath: prefix).appendingPathComponent(executable)
            if fileManager.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "command -v \(executable)"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let path = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }

    private func desktopApplicationExists(for agentID: AgentID) -> Bool {
        let paths: [String]
        switch agentID {
        case .codex:
            paths = ["/Applications/Codex.app", homeDirectory.appendingPathComponent("Applications/Codex.app").path]
        case .claudeCode:
            paths = ["/Applications/Claude.app", homeDirectory.appendingPathComponent("Applications/Claude.app").path]
        case .reasonix:
            paths = ["/Applications/Reasonix.app", homeDirectory.appendingPathComponent("Applications/Reasonix.app").path]
        case .hermes:
            paths = ["/Applications/Hermes.app", homeDirectory.appendingPathComponent("Applications/Hermes.app").path]
        default:
            paths = []
        }
        return paths.contains { fileManager.fileExists(atPath: $0) }
    }

    private func integrationDetail(for agentID: AgentID, cliInstalled: Bool, desktopInstalled: Bool) -> String {
        if agentID == .codex {
            return "App Server · 本地活动"
        }

        return switch agentID {
        case .codex: "App Server / 本地活动"
        case .hermes: "Gateway · ACP"
        case .claudeCode: "agents --json"
        case .reasonix: "ACP"
        default: ""
        }
    }

    private func bridgeCommand(
        helper: URL,
        agentID: AgentID,
        surface: AgentSurfaceID,
        event: String
    ) -> String {
        [
            shellQuote(helper.path),
            "--agent", shellQuote(agentID.rawValue),
            "--surface", shellQuote(surface.rawValue),
            "--event", shellQuote(event),
        ].joined(separator: " ")
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func mergeNestedJSONHooks(
        at url: URL,
        agentID: AgentID,
        surface: AgentSurfaceID,
        events: [String],
        helper: URL
    ) throws {
        var root = try readJSONObject(at: url)
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        guard root["hooks"] == nil || root["hooks"] is [String: Any] else {
            throw AgentHookManagerError.malformedConfiguration("\(url.lastPathComponent) 的 hooks 字段不是对象，未做修改")
        }

        for event in events {
            var groups = hooks[event] as? [[String: Any]] ?? []
            guard hooks[event] == nil || hooks[event] is [[String: Any]] else {
                throw AgentHookManagerError.malformedConfiguration("\(event) Hook 格式无法安全合并，未做修改")
            }
            let command = bridgeCommand(helper: helper, agentID: agentID, surface: surface, event: event)
            guard !groups.contains(where: { nestedGroupContainsMarker($0) }) else { continue }
            groups.append([
                "hooks": [[
                    "type": "command",
                    "command": command,
                    "timeout": 1,
                ]],
            ])
            hooks[event] = groups
        }
        root["hooks"] = hooks
        try writeJSONObject(root, to: url)
    }

    private func removeNestedJSONHooks(at url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        var root = try readJSONObject(at: url)
        guard var hooks = root["hooks"] as? [String: Any] else { return }

        for key in Array(hooks.keys) {
            guard let groups = hooks[key] as? [[String: Any]] else { continue }
            let cleaned: [[String: Any]] = groups.compactMap { group in
                guard var handlers = group["hooks"] as? [[String: Any]] else { return group }
                handlers.removeAll { handler in
                    (handler["command"] as? String)?.contains(Self.commandMarker) == true
                }
                guard !handlers.isEmpty else { return nil }
                var copy = group
                copy["hooks"] = handlers
                return copy
            }
            if cleaned.isEmpty { hooks.removeValue(forKey: key) }
            else { hooks[key] = cleaned }
        }
        if hooks.isEmpty { root.removeValue(forKey: "hooks") }
        else { root["hooks"] = hooks }
        try writeJSONObject(root, to: url)
    }

    private func mergeDirectJSONHooks(
        at url: URL,
        agentID: AgentID,
        surface: AgentSurfaceID,
        events: [String],
        helper: URL
    ) throws {
        var root = try readJSONObject(at: url)
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        guard root["hooks"] == nil || root["hooks"] is [String: Any] else {
            throw AgentHookManagerError.malformedConfiguration("Reasonix hooks.json 格式无法安全合并，未做修改")
        }
        for event in events {
            var handlers = hooks[event] as? [[String: Any]] ?? []
            guard hooks[event] == nil || hooks[event] is [[String: Any]] else {
                throw AgentHookManagerError.malformedConfiguration("Reasonix \(event) Hook 格式无法安全合并")
            }
            guard !handlers.contains(where: { ($0["command"] as? String)?.contains(Self.commandMarker) == true }) else { continue }
            handlers.append([
                "command": bridgeCommand(helper: helper, agentID: agentID, surface: surface, event: event),
                "timeout": 1,
            ])
            hooks[event] = handlers
        }
        root["hooks"] = hooks
        try writeJSONObject(root, to: url)
    }

    private func removeDirectJSONHooks(at url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        var root = try readJSONObject(at: url)
        guard var hooks = root["hooks"] as? [String: Any] else { return }
        for key in Array(hooks.keys) {
            guard var handlers = hooks[key] as? [[String: Any]] else { continue }
            handlers.removeAll { ($0["command"] as? String)?.contains(Self.commandMarker) == true }
            if handlers.isEmpty { hooks.removeValue(forKey: key) }
            else { hooks[key] = handlers }
        }
        if hooks.isEmpty { root.removeValue(forKey: "hooks") }
        else { root["hooks"] = hooks }
        try writeJSONObject(root, to: url)
    }

    private func nestedGroupContainsMarker(_ group: [String: Any]) -> Bool {
        guard let handlers = group["hooks"] as? [[String: Any]] else { return false }
        return handlers.contains { ($0["command"] as? String)?.contains(Self.commandMarker) == true }
    }

    private func mergeHermesHooks(at url: URL, helper: URL) throws {
        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""

        var lines = existing.components(separatedBy: .newlines)
        if lines.last == "" { lines.removeLast() }
        let hooksIndex = lines.firstIndex { $0.range(of: #"^hooks:\s*$"#, options: .regularExpression) != nil }

        if hooksIndex == nil {
            if !lines.isEmpty { lines.append("") }
            lines.append("hooks:")
        }
        let rootIndex = hooksIndex ?? (lines.count - 1)

        for event in Self.hermesEvents {
            let command = bridgeCommand(helper: helper, agentID: .hermes, surface: .hermesCLI, event: event)
            var blockEnd = lines.count
            if rootIndex + 1 < lines.count {
                for index in (rootIndex + 1)..<lines.count where isTopLevelYAMLLine(lines[index]) {
                    blockEnd = index
                    break
                }
            }
            let eventHeader = "  \(event):"
            if let eventIndex = lines[rootIndex..<blockEnd].firstIndex(of: eventHeader) {
                var insertion = blockEnd
                if eventIndex + 1 < blockEnd {
                    for index in (eventIndex + 1)..<blockEnd where isTwoSpaceYAMLLine(lines[index]) {
                        insertion = index
                        break
                    }
                }
                lines.insert(contentsOf: hermesEntry(command: command), at: insertion)
            } else {
                lines.insert(contentsOf: [eventHeader] + hermesEntry(command: command), at: blockEnd)
            }
        }

        try writeText(lines.joined(separator: "\n") + "\n", to: url)
    }

    private func removeHermesHooks(at url: URL) throws {
        guard var text = try? String(contentsOf: url, encoding: .utf8), text.contains(Self.commandMarker) else { return }
        var lines = text.components(separatedBy: .newlines)
        var index = 0
        while index < lines.count {
            if lines[index].contains(Self.hermesMarker) {
                let removeCount = min(3, lines.count - index)
                lines.removeSubrange(index..<(index + removeCount))
                continue
            }
            index += 1
        }

        let managedEvents = Set(Self.hermesEvents)
        index = 0
        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if lines[index].hasPrefix("  "), !lines[index].hasPrefix("    "), trimmed.hasSuffix(":"), managedEvents.contains(String(trimmed.dropLast())) {
                let next = index + 1
                if next >= lines.count || isTwoSpaceYAMLLine(lines[next]) || isTopLevelYAMLLine(lines[next]) || lines[next].isEmpty {
                    lines.remove(at: index)
                    continue
                }
            }
            index += 1
        }
        text = lines.joined(separator: "\n")
        try writeText(text, to: url)
    }

    private func hermesEntry(command: String) -> [String] {
        [
            "    \(Self.hermesMarker)",
            "    - command: \"\(yamlEscaped(command))\"",
            "      timeout: 1",
        ]
    }

    private var hermesAllowlistURL: URL {
        homeDirectory.appendingPathComponent(".hermes/shell-hooks-allowlist.json")
    }

    private func hermesCommands(helper: URL) -> [(event: String, command: String)] {
        Self.hermesEvents.map { event in
            (
                event,
                bridgeCommand(helper: helper, agentID: .hermes, surface: .hermesCLI, event: event)
            )
        }
    }

    private func readHermesAllowlist() throws -> [String: Any] {
        let url = hermesAllowlistURL
        guard fileManager.fileExists(atPath: url.path) else { return ["approvals": []] }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { return ["approvals": []] }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["approvals"] == nil || root["approvals"] is [[String: Any]] else {
            throw AgentHookManagerError.malformedConfiguration("Hermes Hook 授权文件格式异常，未做修改")
        }
        return root
    }

    private func readHermesApprovals() throws -> [[String: Any]] {
        try readHermesAllowlist()["approvals"] as? [[String: Any]] ?? []
    }

    private func authorizeHermesHooks(helper: URL) throws {
        var root = try readHermesAllowlist()
        var approvals = root["approvals"] as? [[String: Any]] ?? []
        let commands = hermesCommands(helper: helper)
        let managedPairs = Set(commands.map { "\($0.event)\u{0}\($0.command)" })
        approvals.removeAll { entry in
            guard let event = entry["event"] as? String,
                  let command = entry["command"] as? String else { return false }
            return managedPairs.contains("\(event)\u{0}\(command)")
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let approvedAt = formatter.string(from: Date())
        let attributes = try? fileManager.attributesOfItem(atPath: helper.path)
        let modifiedAt = (attributes?[.modificationDate] as? Date).map(formatter.string(from:))
        approvals.append(contentsOf: commands.map { pair in
            var entry: [String: Any] = [
                "event": pair.event,
                "command": pair.command,
                "approved_at": approvedAt,
            ]
            entry["script_mtime_at_approval"] = modifiedAt ?? NSNull()
            return entry
        })
        root["approvals"] = approvals
        try writeJSONObject(root, to: hermesAllowlistURL)
    }

    private func revokeHermesHookAuthorization() throws {
        guard fileManager.fileExists(atPath: hermesAllowlistURL.path) else { return }
        var root = try readHermesAllowlist()
        var approvals = root["approvals"] as? [[String: Any]] ?? []
        approvals.removeAll { entry in
            (entry["command"] as? String)?.contains(Self.commandMarker) == true
        }
        root["approvals"] = approvals
        try writeJSONObject(root, to: hermesAllowlistURL)
    }

    private func yamlEscaped(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func isTopLevelYAMLLine(_ line: String) -> Bool {
        !line.isEmpty && !line.hasPrefix(" ") && !line.hasPrefix("#")
    }

    private func isTwoSpaceYAMLLine(_ line: String) -> Bool {
        line.hasPrefix("  ") && !line.hasPrefix("    ") && !line.trimmingCharacters(in: .whitespaces).hasPrefix("#")
    }

    private func readJSONObject(at url: URL) throws -> [String: Any] {
        guard fileManager.fileExists(atPath: url.path) else { return [:] }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { return [:] }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AgentHookManagerError.malformedConfiguration("\(url.lastPathComponent) 不是 JSON 对象，未做修改")
        }
        return object
    }

    private func writeJSONObject(_ object: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try writeData(data + Data([0x0A]), to: url)
    }

    private func writeText(_ text: String, to url: URL) throws {
        guard let data = text.data(using: .utf8) else {
            throw AgentHookManagerError.malformedConfiguration("无法编码 Hook 配置")
        }
        try writeData(data, to: url)
    }

    private func writeData(_ data: Data, to url: URL) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
