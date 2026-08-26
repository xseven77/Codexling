import Foundation

struct AgentIntegrationStatus: Identifiable, Equatable, Sendable {
    let id: AgentID
    let name: String
    let priority: Int
    var cliInstalled: Bool
    var desktopInstalled: Bool
    var detail: String

    var isInstalled: Bool {
        cliInstalled || desktopInstalled
    }

    var guide: AgentInstallGuide {
        AgentInstallGuideCatalog.guide(for: id)
    }
}

enum AgentInstallMethodKind: String, Sendable, Codable {
    case command
    case download
    case run
}

struct AgentInstallMethod: Identifiable, Sendable, Equatable {
    var id: String { title }
    let title: String
    let kind: AgentInstallMethodKind
    let command: String?
    let urlString: String?
    let note: String?
}

struct AgentInstallGuide: Sendable, Equatable {
    let agentID: AgentID
    let name: String
    let tagline: String
    let summary: String
    let integrationMechanism: String
    let methods: [AgentInstallMethod]
    let documentationURLString: String?
}

enum AgentInstallGuideCatalog {
    static func guide(for agentID: AgentID) -> AgentInstallGuide {
        switch agentID {
        case .codex:
            return AgentInstallGuide(
                agentID: .codex,
                name: "Codex",
                tagline: "OpenAI 官方代码智能助手与执行引擎",
                summary: "Codex 是 OpenAI 打造的代码生成与工程辅助工具，支持终端 CLI 与桌面交互环境。Codexling 通过本地 App Server 与活动日志自动接入，无需额外安装 Hook。",
                integrationMechanism: "通过本地 App Server 与活动日志（~/.codex/）自动感知会话与任务状态。",
                methods: [
                    AgentInstallMethod(
                        title: "Homebrew 安装 CLI (推荐)",
                        kind: .command,
                        command: "brew install codex",
                        urlString: nil,
                        note: "适合 macOS 终端用户快速安装。"
                    ),
                    AgentInstallMethod(
                        title: "npm 全局安装 CLI",
                        kind: .command,
                        command: "npm install -g @openai/codex",
                        urlString: nil,
                        note: "需要 Node.js 18+ 环境。"
                    ),
                    AgentInstallMethod(
                        title: "下载 macOS 桌面应用",
                        kind: .download,
                        command: nil,
                        urlString: "https://chatgpt.com/download",
                        note: "下载 ChatGPT / Codex macOS 客户端，登录后即可使用。"
                    )
                ],
                documentationURLString: "https://github.com/openai/codex"
            )

        case .deepseekHarness:
            return AgentInstallGuide(
                agentID: .deepseekHarness,
                name: "Deepseek Harness",
                tagline: "DeepSeek 官方代码智能评估与自动化 Harness",
                summary: "Deepseek Harness 是 DeepSeek 推出的轻量级代码任务执行与自动化评估工具。Codexling 实时解析本地 Session 日志，自动追踪会话与任务状态。",
                integrationMechanism: "通过读取 ~/.dsh/sessions 下的压缩会话 JSONL 实现无缝状态同步。",
                methods: [
                    AgentInstallMethod(
                        title: "npm 全局安装 (推荐)",
                        kind: .command,
                        command: "npm install -g @deepseek/harness",
                        urlString: nil,
                        note: "安装后将在终端提供 dsh 命令行工具。"
                    ),
                    AgentInstallMethod(
                        title: "npx 即开即用",
                        kind: .run,
                        command: "npx @deepseek/harness",
                        urlString: nil,
                        note: "无需全局安装，每次直接运行最新版本。"
                    ),
                    AgentInstallMethod(
                        title: "pnpm 全局安装",
                        kind: .command,
                        command: "pnpm add -g @deepseek/harness",
                        urlString: nil,
                        note: "使用 pnpm 包管理器全局安装。"
                    )
                ],
                documentationURLString: "https://github.com/deepseek-ai"
            )

        case .hermes:
            return AgentInstallGuide(
                agentID: .hermes,
                name: "Hermes",
                tagline: "自主 Coding Agent 与 Gateway 任务引擎",
                summary: "Hermes 是支持 Gateway JSON-RPC 远程通信与 Electron 桌面客户端的自主代码智能体。Codexling 通过本地 SQLite 状态库实时读取活跃任务。",
                integrationMechanism: "通过读取 ~/.hermes/state.db 数据库追踪会话与任务执行进度。",
                methods: [
                    AgentInstallMethod(
                        title: "官方一键脚本安装 (推荐)",
                        kind: .command,
                        command: "curl -fsSL https://hermes-agent.dev/install.sh | bash",
                        urlString: nil,
                        note: "自动配置 hermes 命令行工具与运行环境。"
                    ),
                    AgentInstallMethod(
                        title: "npm 全局安装 CLI",
                        kind: .command,
                        command: "npm install -g hermes-agent",
                        urlString: nil,
                        note: "通过 npm 包管理器安装 CLI 工具。"
                    ),
                    AgentInstallMethod(
                        title: "启动 Electron 桌面应用",
                        kind: .run,
                        command: "hermes desktop",
                        urlString: nil,
                        note: "安装 CLI 后，执行 hermes desktop 即可启动桌面客户端。"
                    )
                ],
                documentationURLString: "https://hermes-agent.dev"
            )

        case .antigravity:
            return AgentInstallGuide(
                agentID: .antigravity,
                name: "Antigravity",
                tagline: "Google Antigravity 多智能体协同开发套件与 IDE",
                summary: "Google Antigravity 是面向多智能体协同的高阶开发工具与 IDE。Codexling 通过解析原子步骤日志（transcript.jsonl）实现精确到思考、执行与确认状态的同步。",
                integrationMechanism: "通过读取 ~/.gemini/antigravity/ 活跃会话流与任务索引自动接入。",
                methods: [
                    AgentInstallMethod(
                        title: "官方安装脚本 / CLI (推荐)",
                        kind: .command,
                        command: "curl -fsSL https://antigravity.google.com/install.sh | bash",
                        urlString: nil,
                        note: "安装后提供 agy 命令行工具与 agentapi 服务。"
                    ),
                    AgentInstallMethod(
                        title: "下载 Antigravity 桌面 IDE",
                        kind: .download,
                        command: nil,
                        urlString: "https://antigravity.google.com",
                        note: "下载 Antigravity.app 并安装至 /Applications/ 目录。"
                    )
                ],
                documentationURLString: "https://antigravity.google.com"
            )

        default:
            return AgentInstallGuide(
                agentID: agentID,
                name: agentID.rawValue,
                tagline: "Coding Agent 扩展",
                summary: "该 Agent 支持通过本地会话或配置文件与 Codexling 联动。",
                integrationMechanism: "通过本地会话读取接入。",
                methods: [],
                documentationURLString: nil
            )
        }
    }
}

/// 提供各 Agent 的接入状态（CLI/Desktop 探测 + 会话读取说明）。
///
/// 各 Agent 均通过会话读取接入，无需安装 Hook：
/// - Codex：App Server + 本地活动适配（内置）
/// - Deepseek Harness：读取 ~/.dsh/sessions 下的 session JSONL
/// - Hermes：Gateway JSON-RPC（session.list / session.active_list 等）
/// - Antigravity：读取 ~/.gemini/antigravity 下的 transcript JSONL
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
            homeDirectory.appendingPathComponent(".cargo/bin").path,
            homeDirectory.appendingPathComponent(".bun/bin").path,
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
                "/Applications/ChatGPT.app",
                "/Applications/Codex.app",
                homeDirectory.appendingPathComponent("Applications/ChatGPT.app").path,
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
            // Deepseek Harness 是 npx/npm 分发的 CLI，无独立 macOS .app。
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
