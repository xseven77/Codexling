import Foundation
import Observation
import SQLite3

enum CodexActivityState: String, Sendable {
    case unavailable
    case idle
    case thinking
    case executing
    case reviewing
    case waitingForUser
    case completed
    case interrupted

    var statusBarText: String? {
        switch self {
        case .unavailable, .idle:
            nil
        case .thinking:
            "思考中"
        case .executing:
            "工作中"
        case .reviewing:
            "检查中"
        case .waitingForUser:
            "等待确认"
        case .completed:
            "已完成"
        case .interrupted:
            "已中止"
        }
    }

    var petAnimationState: PetAnimationState {
        switch self {
        case .unavailable, .idle:
            .idle
        case .thinking, .executing:
            .running
        case .reviewing:
            .review
        case .waitingForUser:
            .waiting
        case .completed:
            .waving
        case .interrupted:
            .failed
        }
    }

    var hoverTitle: String {
        switch self {
        case .unavailable:
            "Codex 状态不可用"
        case .idle:
            "Codex 当前空闲"
        case .thinking:
            "Codex 正在思考"
        case .executing:
            "Codex 正在工作"
        case .reviewing:
            "Codex 正在检查结果"
        case .waitingForUser:
            "Codex 等待你确认"
        case .completed:
            "Codex 任务已完成"
        case .interrupted:
            "Codex 任务已中止"
        }
    }
}

struct CodexActivitySnapshot: Equatable, Sendable {
    var state: CodexActivityState
    var detail: String
    var threadTitle: String?
    var activeTaskCount: Int
    var updatedAt: Date

    static let unavailable = CodexActivitySnapshot(
        state: .unavailable,
        detail: "未找到可读取的 Codex 本地活动数据",
        threadTitle: nil,
        activeTaskCount: 0,
        updatedAt: Date()
    )

    var hoverSubtitle: String {
        let cleanDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanDetail.isEmpty { return cleanDetail }
        if let threadTitle, !threadTitle.isEmpty { return threadTitle }
        return state.hoverTitle
    }

    var hoverDisplayTitle: String {
        guard state != .unavailable, state != .idle,
              let threadTitle else {
            return state.hoverTitle
        }
        let cleanTitle = threadTitle
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return state.hoverTitle }
        return cleanTitle.count > 44
            ? String(cleanTitle.prefix(43)) + "…"
            : cleanTitle
    }
}

struct ParsedCodexThreadActivity: Equatable, Sendable {
    var state: CodexActivityState
    var detail: String
    var title: String
    var updatedAt: Date

    var isActive: Bool {
        switch state {
        case .thinking, .executing, .reviewing, .waitingForUser:
            true
        default:
            false
        }
    }
}

struct CodexActivityEventParser: Sendable {
    func parse(data: Data, title: String, now: Date = Date()) -> ParsedCodexThreadActivity {
        let isoFormatter = ISO8601DateFormatter()
        var isActive = false
        var state: CodexActivityState = .idle
        var detail = ""
        var updatedAt = Date.distantPast
        var outstandingCalls: [String: String] = [:]

        for line in data.split(separator: 0x0A) {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let payload = object["payload"] as? [String: Any] else {
                continue
            }

            if let timestamp = object["timestamp"] as? String,
               let date = isoFormatter.date(from: timestamp) {
                updatedAt = max(updatedAt, date)
            }

            switch object["type"] as? String {
            case "event_msg":
                let type = payload["type"] as? String
                switch type {
                case "task_started":
                    isActive = true
                    state = .thinking
                    outstandingCalls.removeAll()
                    if detail.isEmpty { detail = "正在分析任务并准备执行" }
                case "task_complete":
                    isActive = false
                    state = .completed
                    outstandingCalls.removeAll()
                    if detail.isEmpty { detail = "任务已经完成" }
                case "turn_aborted":
                    isActive = false
                    state = .interrupted
                    outstandingCalls.removeAll()
                    detail = "任务已停止或被中止"
                case "agent_message":
                    if let message = payload["message"] as? String,
                       payload["phase"] as? String == "commentary" {
                        detail = sanitize(message)
                    }
                case "agent_reasoning":
                    if isActive, outstandingCalls.isEmpty {
                        state = .thinking
                    }
                case "patch_apply_end":
                    if isActive {
                        state = .reviewing
                        if detail.isEmpty { detail = "正在检查代码改动" }
                    }
                default:
                    break
                }

            case "response_item":
                let type = payload["type"] as? String
                switch type {
                case "custom_tool_call", "function_call":
                    guard isActive else { break }
                    let callID = (payload["call_id"] as? String)
                        ?? (payload["id"] as? String)
                        ?? UUID().uuidString
                    let name = payload["name"] as? String ?? "tool"
                    let input = (payload["input"] as? String)
                        ?? (payload["arguments"] as? String)
                        ?? ""
                    let normalizedName = input.contains("require_escalated") ? "approval" : name
                    outstandingCalls[callID] = normalizedName
                    if isWaitingTool(normalizedName) {
                        state = .waitingForUser
                    } else if isReviewTool(normalizedName) {
                        state = .reviewing
                    } else {
                        state = .executing
                    }
                    detail = toolDescription(normalizedName)

                case "custom_tool_call_output", "function_call_output":
                    if let callID = payload["call_id"] as? String {
                        outstandingCalls.removeValue(forKey: callID)
                    }
                    if isActive {
                        state = outstandingCalls.isEmpty ? .thinking : stateForCalls(outstandingCalls.values)
                    }

                case "message":
                    if payload["phase"] as? String == "commentary",
                       let message = responseMessageText(payload) {
                        detail = sanitize(message)
                    }
                case "reasoning":
                    if isActive, outstandingCalls.isEmpty {
                        state = .thinking
                    }
                default:
                    break
                }
            default:
                break
            }
        }

        if isActive, !outstandingCalls.isEmpty {
            state = stateForCalls(outstandingCalls.values)
            if let name = outstandingCalls.values.first {
                detail = toolDescription(name)
            }
        }

        if !isActive, state == .completed, now.timeIntervalSince(updatedAt) > 20 {
            state = .idle
            detail = "当前没有正在执行的 Codex 任务"
        }
        if updatedAt == .distantPast { updatedAt = now }

        return ParsedCodexThreadActivity(
            state: state,
            detail: detail,
            title: title,
            updatedAt: updatedAt
        )
    }

    private func responseMessageText(_ payload: [String: Any]) -> String? {
        guard let content = payload["content"] as? [[String: Any]] else { return nil }
        return content.compactMap { item in
            let type = item["type"] as? String
            guard type == "output_text" || type == "text" else { return nil }
            return item["text"] as? String
        }.joined(separator: " ")
    }

    private func stateForCalls(_ names: Dictionary<String, String>.Values) -> CodexActivityState {
        if names.contains(where: isWaitingTool) { return .waitingForUser }
        if names.contains(where: isReviewTool) { return .reviewing }
        return .executing
    }

    private func isWaitingTool(_ name: String) -> Bool {
        name == "request_user_input" || name == "approval"
    }

    private func isReviewTool(_ name: String) -> Bool {
        name.contains("view_image") || name.contains("screenshot")
    }

    private func toolDescription(_ name: String) -> String {
        return switch name {
        case "approval", "request_user_input":
            "需要你的确认后才能继续"
        case "exec", "exec_command", "write_stdin":
            "正在运行本地命令"
        case "apply_patch":
            "正在修改项目文件"
        case "wait", "wait_agent":
            "正在等待后台任务返回"
        case "view_image", "imagegen", "image_gen__imagegen":
            "正在处理图像"
        default:
            name.contains("web") || name.contains("search")
                ? "正在检索相关信息"
                : "正在调用工具处理任务"
        }
    }

    private func sanitize(_ text: String) -> String {
        var value = text
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if value.count > 100 {
            value = String(value.prefix(99)) + "…"
        }
        return value
    }
}

struct CodexActivityService: Sendable {
    let databaseURLs: [URL]
    let parser = CodexActivityEventParser()

    init(databaseURLs: [URL]? = nil) {
        if let databaseURLs {
            self.databaseURLs = databaseURLs
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            self.databaseURLs = [
                home.appendingPathComponent(".codex/state_5.sqlite"),
                home.appendingPathComponent(".codex/sqlite/state_5.sqlite")
            ]
        }
    }

    func loadSnapshot(now: Date = Date()) -> CodexActivitySnapshot {
        guard let databaseURL = databaseURLs.first(where: {
            FileManager.default.fileExists(atPath: $0.path)
        }) else {
            return .unavailable
        }

        let rows = loadRecentThreads(databaseURL: databaseURL)
        guard !rows.isEmpty else {
            return CodexActivitySnapshot(
                state: .idle,
                detail: "当前没有可读取的 Codex 任务",
                threadTitle: nil,
                activeTaskCount: 0,
                updatedAt: now
            )
        }

        let activities = rows.enumerated().compactMap { index, row -> ParsedCodexThreadActivity? in
            guard let data = readTail(
                of: URL(fileURLWithPath: row.rolloutPath),
                expandForLifecycle: index == 0
            ) else { return nil }
            return parser.parse(data: data, title: row.title, now: now)
        }
        guard !activities.isEmpty else { return .unavailable }

        let active = activities.filter(\.isActive)
        let selected: ParsedCodexThreadActivity
        if !active.isEmpty {
            selected = active.max { lhs, rhs in
                activityPriority(lhs.state) == activityPriority(rhs.state)
                    ? lhs.updatedAt < rhs.updatedAt
                    : activityPriority(lhs.state) < activityPriority(rhs.state)
            }!
        } else {
            selected = activities.max { $0.updatedAt < $1.updatedAt }!
        }

        return CodexActivitySnapshot(
            state: selected.state,
            detail: selected.detail,
            threadTitle: selected.title,
            activeTaskCount: active.count,
            updatedAt: selected.updatedAt
        )
    }

    private func loadRecentThreads(databaseURL: URL) -> [(rolloutPath: String, title: String)] {
        var database: OpaquePointer?
        guard sqlite3_open_v2(
            databaseURL.path,
            &database,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX,
            nil
        ) == SQLITE_OK, let database else {
            return []
        }
        defer { sqlite3_close(database) }

        let sql = """
        SELECT rollout_path, title
        FROM threads
        WHERE archived = 0
        ORDER BY updated_at DESC
        LIMIT 12
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        var rows: [(String, String)] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let pathText = sqlite3_column_text(statement, 0) else { continue }
            let path = String(cString: pathText)
            let title = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? "Codex 任务"
            rows.append((path, title))
        }
        return rows
    }

    func readTail(
        of url: URL,
        maxBytes: UInt64 = 4 * 1_024 * 1_024,
        expandForLifecycle: Bool = true
    ) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd() else { return nil }
        guard end > 0 else { return nil }

        var start = end
        var accumulated = Data()
        while start > 0 {
            let chunkSize = min(maxBytes, start)
            start -= chunkSize
            try? handle.seek(toOffset: start)
            guard let chunk = try? handle.read(upToCount: Int(chunkSize)),
                  !chunk.isEmpty else { return nil }
            accumulated.insert(contentsOf: chunk, at: accumulated.startIndex)

            var data = accumulated
            if start > 0, let firstNewline = data.firstIndex(of: 0x0A) {
                data.removeSubrange(data.startIndex...firstNewline)
            }

            if start == 0 || !expandForLifecycle || containsLifecycleEvent(data) {
                return data
            }
        }
        return accumulated
    }

    private func containsLifecycleEvent(_ data: Data) -> Bool {
        ["task_started", "task_complete", "turn_aborted"].contains { marker in
            data.range(of: Data(marker.utf8)) != nil
        }
    }

    private func activityPriority(_ state: CodexActivityState) -> Int {
        switch state {
        case .waitingForUser: 5
        case .executing: 4
        case .reviewing: 3
        case .thinking: 2
        case .interrupted: 1
        default: 0
        }
    }
}

@Observable
@MainActor
final class CodexActivityStore {
    var snapshot = CodexActivitySnapshot.unavailable
    var onSnapshotChanged: ((CodexActivitySnapshot) -> Void)?

    private let service: CodexActivityService
    private var timer: Timer?
    private var refreshTask: Task<Void, Never>?

    init(service: CodexActivityService = CodexActivityService()) {
        self.service = service
    }

    func start() {
        stop()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        refreshTask?.cancel()
        refreshTask = nil
    }

    private func refresh() {
        guard refreshTask == nil else { return }
        let service = self.service
        refreshTask = Task { [weak self] in
            let next = await Task.detached {
                service.loadSnapshot()
            }.value
            guard !Task.isCancelled, let self else { return }
            refreshTask = nil
            if next != snapshot {
                snapshot = next
                onSnapshotChanged?(next)
            }
        }
    }
}
