import Foundation

struct HermesCommandResult {
    let output: String
    let errorOutput: String
    let terminationStatus: Int32
}

protocol HermesCommandRunning: Sendable {
    var isAvailable: Bool { get }
    func run(arguments: [String]) throws -> HermesCommandResult
}

enum HermesGatewayConfigurationError: LocalizedError {
    case executableNotFound
    case noGatewayModel
    case commandFailed(command: String, detail: String)
    case verificationFailed(key: String, expected: String, actual: String)

    var errorDescription: String? {
        switch self {
        case .executableNotFound:
            "未找到 Hermes CLI；请先安装 Hermes，或确认 ~/.local/bin/hermes 可执行。"
        case .noGatewayModel:
            "Gateway 当前没有已启用的可用模型，请先在“接入与模型”中开启至少一个账号代理。"
        case .commandFailed(let command, let detail):
            "Hermes 配置命令失败（\(command)）：\(detail)"
        case .verificationFailed(let key, let expected, let actual):
            "Hermes 配置校验失败：\(key) 应为 \(expected)，实际为 \(actual.isEmpty ? "<空>" : actual)。"
        }
    }
}

struct HermesCLICommandRunner: HermesCommandRunning {
    let executableURL: URL?

    init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        var candidates: [URL] = [
            homeDirectory.appendingPathComponent(".local/bin/hermes"),
            homeDirectory.appendingPathComponent(".hermes/bin/hermes"),
            URL(fileURLWithPath: "/opt/homebrew/bin/hermes"),
            URL(fileURLWithPath: "/usr/local/bin/hermes"),
        ]
        if let path = environment["PATH"] {
            candidates.append(contentsOf: path.split(separator: ":").map {
                URL(fileURLWithPath: String($0)).appendingPathComponent("hermes")
            })
        }
        executableURL = candidates.first {
            FileManager.default.isExecutableFile(atPath: $0.path)
        }
    }

    var isAvailable: Bool { executableURL != nil }

    func run(arguments: [String]) throws -> HermesCommandResult {
        guard let executableURL else {
            throw HermesGatewayConfigurationError.executableNotFound
        }
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        return HermesCommandResult(
            output: String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
            errorOutput: String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
            terminationStatus: process.terminationStatus
        )
    }
}

struct HermesGatewayConfigurator: Sendable {
    private static let providerID = "custom:codexling"
    private static let providerKeys = [
        "providers.codexling.name",
        "providers.codexling.api",
        "providers.codexling.api_key",
        "providers.codexling.transport",
        "providers.codexling.default_model",
        "providers.codexling.discover_models",
        "providers.codexling.models",
        "providers.codexling.extra_headers.X-Codexling-Catalog-Version",
        "providers.codexling.extra_headers.X-Agent-Name",
    ]

    let runner: any HermesCommandRunning
    let configURL: URL

    init(
        runner: any HermesCommandRunning = HermesCLICommandRunner(),
        configURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".hermes/config.yaml")
    ) {
        self.runner = runner
        self.configURL = configURL
    }

    var isHermesInstalled: Bool { runner.isAvailable }

    var isConfigured: Bool {
        guard runner.isAvailable else { return false }
        // Do not scan the YAML for the word "codexling": hooks, historical
        // sessions and backup entries may legitimately contain it after this
        // provider has been removed.
        if configValue(for: "providers.codexling.api") != nil {
            return true
        }
        return configValue(for: "model.provider") == Self.providerID
    }

    func unconfigure() throws {
        guard runner.isAvailable else {
            throw HermesGatewayConfigurationError.executableNotFound
        }
        let originalConfig = try? Data(contentsOf: configURL)
        do {
            let currentProvider = configValue(for: "model.provider") ?? ""

            // Hermes' `config unset providers.codexling` is not recursive:
            // it reports success while nested values remain in config.yaml.
            // Remove each Codexling-owned leaf explicitly, then ask Hermes to
            // discard an empty parent when its CLI supports that operation.
            for key in Self.providerKeys {
                try unset(key)
            }
            try unset("providers.codexling")

            if currentProvider == Self.providerID {
                try unset("model.provider")
                try unset("model.default")
            }

            for key in Self.providerKeys {
                try verifyUnset(key)
            }
            if currentProvider == Self.providerID {
                try verifyUnset("model.provider")
                try verifyUnset("model.default")
            }
        } catch {
            if let originalConfig {
                try? originalConfig.write(to: configURL, options: .atomic)
            }
            throw error
        }
    }

    func configure(baseURL: String, apiKey: String, models: [String], defaultModel: String) throws {
        guard runner.isAvailable else {
            throw HermesGatewayConfigurationError.executableNotFound
        }
        let uniqueModels = models.reduce(into: [String]()) { result, model in
            let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.contains(where: { $0.isWhitespace }), !result.contains(trimmed) else {
                return
            }
            result.append(trimmed)
        }
        // The preferred default does not have to be the first display entry:
        // for example, Gemini 3.6 Flash is chosen ahead of an unverified 3.7
        // alias. It only needs to be part of the registered allowlist.
        guard uniqueModels.contains(defaultModel) else {
            throw HermesGatewayConfigurationError.noGatewayModel
        }
        let modelsJSON = String(
            data: try JSONSerialization.data(withJSONObject: uniqueModels),
            encoding: .utf8
        ) ?? "[]"
        let originalConfig = try? Data(contentsOf: configURL)
        do {
            try set("providers.codexling.name", to: "Codexling")
            try set("providers.codexling.api", to: baseURL)
            try set("providers.codexling.api_key", to: apiKey)
            try set("providers.codexling.transport", to: "chat_completions")
            try set("providers.codexling.default_model", to: defaultModel)
            try set("providers.codexling.discover_models", to: "false")
            try set("providers.codexling.models", to: modelsJSON)
            try set("providers.codexling.extra_headers.X-Codexling-Catalog-Version", to: "2")
            try set("providers.codexling.extra_headers.X-Agent-Name", to: "Hermes")
            try set("model.provider", to: Self.providerID)
            try set("model.default", to: defaultModel)
            // These are legacy unnamed-custom-endpoint keys. Keeping them
            // alongside a named provider makes Hermes surface an extra bare
            // model row in addition to the Codexling allowlist.
            try unset("model.base_url")
            try unset("model.api_key")
            try verify("providers.codexling.name", equals: "Codexling")
            try verify("providers.codexling.api", equals: baseURL)
            try verify("providers.codexling.api_key", equals: apiKey)
            try verify("providers.codexling.transport", equals: "chat_completions")
            try verify("providers.codexling.default_model", equals: defaultModel)
            try verify("providers.codexling.discover_models", equals: "false")
            try verify("providers.codexling.extra_headers.X-Codexling-Catalog-Version", equals: "2")
            try verify("providers.codexling.extra_headers.X-Agent-Name", equals: "Hermes")
            try verify("model.provider", equals: Self.providerID)
            try verify("model.default", equals: defaultModel)
        } catch {
            if let originalConfig {
                try? originalConfig.write(to: configURL, options: .atomic)
            }
            throw error
        }
    }

    private func set(_ key: String, to value: String) throws {
        let result = try runner.run(arguments: ["config", "set", key, value])
        guard result.terminationStatus == 0 else {
            throw commandError(for: "hermes config set \(key)", result: result)
        }
    }

    private func unset(_ key: String) throws {
        let result = try runner.run(arguments: ["config", "unset", key])
        // Hermes exits non-zero when an optional legacy key does not exist.
        // That is already the desired state, so it must not abort an otherwise
        // valid named-provider configuration.
        let detail = [result.errorOutput, result.output]
            .joined(separator: "\n")
            .lowercased()
        if result.terminationStatus != 0,
           !detail.contains("config key not set"),
           !detail.contains("key not set"),
           !detail.contains("not found") {
            throw commandError(for: "hermes config unset \(key)", result: result)
        }
    }

    private func verify(_ key: String, equals expected: String) throws {
        let result = try runner.run(arguments: ["config", "get", key])
        guard result.terminationStatus == 0 else {
            throw commandError(for: "hermes config get \(key)", result: result)
        }
        let actual = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard actual == expected else {
            throw HermesGatewayConfigurationError.verificationFailed(
                key: key,
                expected: expected,
                actual: actual
            )
        }
    }

    private func configValue(for key: String) -> String? {
        guard let result = try? runner.run(arguments: ["config", "get", key]),
              result.terminationStatus == 0 else {
            return nil
        }
        let value = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func verifyUnset(_ key: String) throws {
        guard let value = configValue(for: key) else { return }
        throw HermesGatewayConfigurationError.verificationFailed(
            key: key,
            expected: "<未设置>",
            actual: value
        )
    }

    private func commandError(for command: String, result: HermesCommandResult) -> HermesGatewayConfigurationError {
        let detail = [result.errorOutput, result.output]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? "未知错误"
        return .commandFailed(command: command, detail: detail)
    }
}
