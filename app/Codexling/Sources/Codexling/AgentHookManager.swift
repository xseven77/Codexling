import Foundation

struct AgentIntegrationStatus: Identifiable, Equatable, Sendable {
    let id: AgentID
    let name: String
    let priority: Int
    var cliInstalled: Bool
    var desktopInstalled: Bool
    var detail: String
}

/// 提供各 Agent 的接入状态（CLI/Desktop 探测 + 会话读取说明）。
///
/// 三个 Agent（Codex / Deepseek Harness / Hermes）都通过会话读取接入，无需安装 Hook：
/// - Codex：App Server + 本地活动适配（内置）
/// - Deepseek Harness：读取 ~/.dsh/sessions 下的 session JSONL
/// - Hermes：Gateway JSON-RPC（session.list / session.active_list 等）
struct AgentHookManager {
    let fileManager: FileManager
    let homeDirectory: URL

    init(
        fileManager: FileManager = .default,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory
    }

    func integrationStatuses() -> [AgentIntegrationStatus] {
        BuiltInAgentCatalog.prioritized.map { descriptor in
            let cliInstalled = locateExecutable(for: descriptor.id) != nil
            let desktopInstalled = desktopApplicationExists(for: descriptor.id)
            return AgentIntegrationStatus(
                id: descriptor.id,
                name: descriptor.displayName,
                priority: descriptor.priority,
                cliInstalled: cliInstalled,
                desktopInstalled: desktopInstalled,
                detail: integrationDetail(for: descriptor.id)
            )
        }
    }

    private func locateExecutable(for agentID: AgentID) -> URL? {
        if agentID == .antigravity {
            let candidate = homeDirectory.appendingPathComponent(".gemini/antigravity/bin/agentapi")
            if fileManager.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }

        let executable: String
        switch agentID {
        case .codex: executable = "codex"
        case .hermes: executable = "hermes"
        case .deepseekHarness: executable = "dsh"
        case .antigravity: executable = "agy"
        default: return nil
        }

        let prefixes = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            homeDirectory.appendingPathComponent(".local/bin").path,
            homeDirectory.appendingPathComponent(".nvm/current/bin").path,
            homeDirectory.appendingPathComponent(".gemini/antigravity/bin").path,
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
            paths = [
                "/Applications/Codex.app",
                homeDirectory.appendingPathComponent("Applications/Codex.app").path,
            ]
        case .hermes:
            paths = [
                "/Applications/Hermes.app",
                homeDirectory.appendingPathComponent("Applications/Hermes.app").path,
            ]
        case .antigravity:
            paths = [
                "/Applications/Antigravity.app",
                homeDirectory.appendingPathComponent("Applications/Antigravity.app").path,
            ]
        case .deepseekHarness:
            // Deepseek Harness 是 npx 分发的 CLI，无桌面 App。
            paths = []
        default:
            paths = []
        }
        return paths.contains { fileManager.fileExists(atPath: $0) }
    }

    private func integrationDetail(for agentID: AgentID) -> String {
        switch agentID {
        case .codex: "App Server · 本地活动"
        case .hermes: "Gateway JSON-RPC · 会话读取"
        case .deepseekHarness: "Session JSONL · 会话读取"
        case .antigravity: "Transcript JSONL · 本地活动"
        default: ""
        }
    }
}
