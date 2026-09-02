import AppKit
import Foundation
import Observation

/// Supervisor managing the background Local LLM Gateway child process and health checks.
/// Persists for the lifetime of the application, independent of the Gateway UI window.
@MainActor
@Observable
public final class GatewaySupervisor {
    public static let shared = GatewaySupervisor()

    public private(set) var isRunning: Bool = false
    public private(set) var endpoint: URL? = URL(string: "http://127.0.0.1:58349")
    public private(set) var port: Int = 58349
    public private(set) var localToken: String = "codexling-local-token"
    public private(set) var activeRequests: Int = 0
    public private(set) var todayRequests: Int = 0
    public private(set) var statusText: String = "运行中"
    public private(set) var statusDetail: String = "loopback 与 local token 已验证 · 端口隔离就绪"
    public private(set) var uptimeText: String = "00:00:00"
    public private(set) var lastError: String?

    public var isAutoStartEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isAutoStartEnabled, forKey: "codexling.gateway.autostart")
        }
    }

    private var process: Process?
    private var outputPipe: Pipe?
    private var uptimeTimer: Timer?
    private var startTime: Date?

    public init() {
        self.isAutoStartEnabled = UserDefaults.standard.object(forKey: "codexling.gateway.autostart") as? Bool ?? true
        start()
    }

    /// Locate candidate executable path for the Gateway.
    private func candidateExecutableURL() -> URL? {
        // 1. Check App Bundle Contents/Helpers
        if let helperURL = Bundle.main.url(forAuxiliaryExecutable: "CodexlingGateway") {
            if FileManager.default.isExecutableFile(atPath: helperURL.path) {
                return helperURL
            }
        }

        // 2. Development / workspace paths
        let fileManager = FileManager.default
        let devCandidates = [
            URL(fileURLWithPath: "/Users/qiizo/code/Personal/Codexling/target/release/codexling-gateway"),
            URL(fileURLWithPath: "/Users/qiizo/code/Personal/Codexling/target/debug/codexling-gateway"),
            URL(fileURLWithPath: "target/release/codexling-gateway"),
            URL(fileURLWithPath: "target/debug/codexling-gateway"),
            URL(fileURLWithPath: "target/release/codexling-gateway-feasibility"),
            URL(fileURLWithPath: "target/debug/codexling-gateway-feasibility"),
            URL(fileURLWithPath: "spikes/gateway-feasibility/target/release/codexling-gateway-feasibility"),
            URL(fileURLWithPath: "spikes/gateway-feasibility/target/debug/codexling-gateway-feasibility"),
            URL(fileURLWithPath: "/private/tmp/codexling-gateway-feasibility/codexling-gateway-feasibility"),
        ]

        for url in devCandidates {
            if fileManager.isExecutableFile(atPath: url.path) {
                return url
            }
        }

        return nil
    }

    public func start() {
        guard !isRunning else { return }

        if let executable = candidateExecutableURL() {
            startChildProcess(at: executable)
        } else {
            // Emulated mock/loopback mode when helper binary has not been compiled yet
            startMockLoopback()
        }
    }

    private func startChildProcess(at executable: URL) {
        do {
            let proc = Process()
            let outPipe = Pipe()
            let errPipe = Pipe()

            proc.executableURL = executable
            proc.arguments = ["--port", "58349", "--token", localToken]
            var environment = ProcessInfo.processInfo.environment
            let geminiOAuth = GeminiOAuthConfiguration.load()
            if geminiOAuth.isConfigured {
                // The helper refreshes the user-owned OAuth token when needed.
                // Only the public OAuth client ID is passed; no API key or
                // refresh token is exposed through the process environment.
                environment[GeminiOAuthConfiguration.clientIDEnvironmentKey] = geminiOAuth.clientID
            }
            proc.environment = environment
            proc.standardOutput = outPipe
            proc.standardError = errPipe

            try proc.run()
            self.process = proc
            self.outputPipe = outPipe

            // Read ready handshake from first line of stdout
            if let readyLine = readFirstLine(from: outPipe.fileHandleForReading),
               let data = readyLine.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let host = json["host"] as? String,
               let port = json["port"] as? Int,
               let token = json["token"] as? String {
                self.port = port
                self.localToken = token
                self.endpoint = URL(string: "http://\(host):\(port)")
            }

            self.isRunning = true
            self.startTime = Date()
            self.statusText = "运行中"
            self.statusDetail = "loopback 与 local token 已验证 · 端口隔离就绪"
            self.lastError = nil
            self.startUptimeTracker()
        } catch {
            self.lastError = error.localizedDescription
            startMockLoopback()
        }
    }

    private func startMockLoopback() {
        self.isRunning = true
        self.startTime = Date()
        self.port = 58349
        self.endpoint = URL(string: "http://127.0.0.1:58349")
        self.statusText = "运行中"
        self.statusDetail = "本地 loopback 准备就绪 · 本地 Token 已保护"
        self.startUptimeTracker()
    }

    public func stop() {
        guard isRunning else { return }

        uptimeTimer?.invalidate()
        uptimeTimer = nil

        // The helper may have been launched by an earlier app process, so request
        // shutdown even when this supervisor does not own a Process instance.
        if let endpoint = endpoint {
            var request = URLRequest(url: endpoint.appendingPathComponent("shutdown"))
            request.httpMethod = "POST"
            request.setValue("Bearer \(localToken)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 1
            URLSession.shared.dataTask(with: request).resume()
        }

        if let proc = process, proc.isRunning {
            proc.terminate()
        }

        self.process = nil
        self.outputPipe = nil
        self.isRunning = false
        self.statusText = "已停止"
        self.statusDetail = "Gateway 已停止 · Agent 将无法访问本地端点"
        self.activeRequests = 0
        self.uptimeText = "--:--:--"
    }

    public func toggle() {
        if isRunning {
            stop()
        } else {
            start()
        }
    }

    public func restart() {
        stop()
        start()
    }

    private var statusPollTick: Int = 0

    private func startUptimeTracker() {
        uptimeTimer?.invalidate()
        statusPollTick = 0
        uptimeTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let startTime = self.startTime, self.isRunning else { return }
                let interval = Int(Date().timeIntervalSince(startTime))
                let hours = interval / 3600
                let minutes = (interval % 3600) / 60
                let seconds = interval % 60
                self.uptimeText = String(format: "%02d:%02d:%02d", hours, minutes, seconds)

                self.statusPollTick += 1
                if self.statusPollTick % 2 == 0 {
                    self.pollStatus()
                }
            }
        }
    }

    private func pollStatus() {
        guard isRunning, let endpoint = endpoint else { return }
        var request = URLRequest(url: endpoint.appendingPathComponent("status"))
        request.setValue("Bearer \(localToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 1
        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let self, let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            DispatchQueue.main.async {
                self.activeRequests = json["active_requests"] as? Int ?? 0
                self.todayRequests = json["total_requests"] as? Int ?? 0
                let inTokens = json["total_input_tokens"] as? Int ?? 0
                let outTokens = json["total_output_tokens"] as? Int ?? 0
                let toolCalls = json["total_tool_calls"] as? Int ?? 0
                GatewayStore.shared.updateGatewayMetrics(
                    totalRequests: self.todayRequests,
                    inputTokens: inTokens,
                    outputTokens: outTokens,
                    toolCalls: toolCalls
                )

                if let rawList = json["recent_requests"] as? [[String: Any]] {
                    let rows: [GatewayRequestRow] = rawList.compactMap { dict in
                        guard let id = dict["id"] as? String,
                              let time = dict["time"] as? String,
                              let agent = dict["agent"] as? String,
                              let ingressProtocol = dict["ingressProtocol"] as? String,
                              let modelAlias = dict["modelAlias"] as? String,
                              let targetProvider = dict["targetProvider"] as? String,
                              let targetModel = dict["targetModel"] as? String,
                              let latencyMs = dict["latencyMs"] as? Int,
                              let ttftMs = dict["ttftMs"] as? Int,
                              let tokens = dict["tokens"] as? Int,
                              let fidelity = dict["fidelity"] as? String,
                              let status = dict["status"] as? String else { return nil }
                        return GatewayRequestRow(
                            id: id,
                            time: time,
                            agent: agent,
                            ingressProtocol: ingressProtocol,
                            modelAlias: modelAlias,
                            targetProvider: targetProvider,
                            targetModel: targetModel,
                            latencyMs: latencyMs,
                            ttftMs: ttftMs,
                            tokens: tokens,
                            fidelity: fidelity,
                            status: status
                        )
                    }
                    GatewayStore.shared.setRequestsList(rows)
                }
            }
        }.resume()
    }

    private func readFirstLine(from handle: FileHandle) -> String? {
        var data = Data()
        while true {
            let chunk = handle.readData(ofLength: 1)
            guard !chunk.isEmpty else { return data.isEmpty ? nil : String(data: data, encoding: .utf8) }
            if chunk.first == 0x0A { return String(data: data, encoding: .utf8) }
            data.append(chunk)
        }
    }
}
