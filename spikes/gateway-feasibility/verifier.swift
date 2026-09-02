import Foundation

private struct HTTPResult {
    let status: Int
    let contentType: String
    let body: String
}

private enum VerificationError: Error, CustomStringConvertible {
    case missingExecutable
    case missingReadyLine
    case invalidReadyPayload
    case failedCheck(String)

    var description: String {
        switch self {
        case .missingExecutable: "Pass the mock gateway executable as the first argument."
        case .missingReadyLine: "Gateway did not emit a ready line."
        case .invalidReadyPayload: "Gateway emitted an invalid ready payload."
        case .failedCheck(let message): message
        }
    }
}

private func readLine(from handle: FileHandle) -> String? {
    var data = Data()
    while true {
        let byte = handle.readData(ofLength: 1)
        guard !byte.isEmpty else { return data.isEmpty ? nil : String(data: data, encoding: .utf8) }
        if byte.first == 0x0A { return String(data: data, encoding: .utf8) }
        data.append(byte)
    }
}

private func request(
    baseURL: URL,
    path: String,
    method: String = "GET",
    token: String? = nil
) async throws -> HTTPResult {
    var request = URLRequest(url: baseURL.appending(path: path))
    request.httpMethod = method
    request.timeoutInterval = 4
    if let token {
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 4
    let session = URLSession(configuration: configuration)
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else {
        throw VerificationError.failedCheck("Response was not HTTP.")
    }
    return HTTPResult(
        status: http.statusCode,
        contentType: http.value(forHTTPHeaderField: "Content-Type") ?? "",
        body: String(data: data, encoding: .utf8) ?? ""
    )
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw VerificationError.failedCheck(message) }
}

@main
private struct GatewayFeasibilityVerifier {
    static func main() async {
        do {
            guard CommandLine.arguments.count > 1 else { throw VerificationError.missingExecutable }
            let executable = URL(fileURLWithPath: CommandLine.arguments[1])

            let process = Process()
            let output = Pipe()
            let errors = Pipe()
            process.executableURL = executable
            process.standardOutput = output
            process.standardError = errors
            try process.run()

            guard let readyLine = readLine(from: output.fileHandleForReading) else {
                process.terminate()
                throw VerificationError.missingReadyLine
            }
            guard
                let readyData = readyLine.data(using: .utf8),
                let ready = try JSONSerialization.jsonObject(with: readyData) as? [String: Any],
                let host = ready["host"] as? String,
                let port = ready["port"] as? Int,
                let token = ready["token"] as? String,
                let baseURL = URL(string: "http://\(host):\(port)")
            else {
                process.terminate()
                throw VerificationError.invalidReadyPayload
            }

            let health = try await request(baseURL: baseURL, path: "/health")
            try require(health.status == 200 && health.body.contains("\"status\":\"ok\""), "Public health check failed.")

            let denied = try await request(baseURL: baseURL, path: "/status")
            try require(denied.status == 401, "Control plane accepted a request without the local token.")

            let status = try await request(baseURL: baseURL, path: "/status", token: token)
            try require(status.status == 200 && status.body.contains("\"running\":true"), "Authenticated status check failed.")

            let models = try await request(baseURL: baseURL, path: "/v1/models", token: token)
            try require(models.status == 200 && models.body.contains("coding-smart"), "Model alias endpoint failed.")

            let events = try await request(baseURL: baseURL, path: "/events", token: token)
            try require(events.status == 200, "SSE endpoint did not return success.")
            try require(events.contentType.contains("text/event-stream"), "SSE endpoint returned the wrong content type.")
            try require(events.body.contains("event: request.started"), "SSE request.started event was missing.")
            try require(events.body.contains("event: request.completed"), "SSE request.completed event was missing.")

            let shutdown = try await request(baseURL: baseURL, path: "/shutdown", method: "POST", token: token)
            try require(shutdown.status == 200 && shutdown.body.contains("\"stopping\":true"), "Authenticated shutdown failed.")

            process.waitUntilExit()
            try require(process.terminationStatus == 0, "Gateway exited with status \(process.terminationStatus).")

            print("PASS process_launch ready_handshake loopback_binding public_health local_token models_endpoint sse_events graceful_shutdown")
            print("endpoint=\(baseURL.absoluteString) gateway_exit=\(process.terminationStatus)")
        } catch {
            fputs("FAIL \(error)\n", stderr)
            exit(1)
        }
    }
}
