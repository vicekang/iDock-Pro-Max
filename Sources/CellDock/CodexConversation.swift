import Foundation

/// Uses Codex's supported local protocol and its own saved login. No OAuth
/// credentials are read, copied, or sent to another endpoint by CellDock.
@MainActor
final class CodexConversation {
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var buffer = Data()
    private var sequence = 0
    private var generation = UUID()
    private var requests: [Int: (Result<[String: Any], Error>) -> Void] = [:]
    private var threadID: String?
    private var reply: ((Result<String, Error>) -> Void)?
    private var response = ""
    private var deadline: DispatchWorkItem?
    var onRealtimeEvent: ((String, [String: Any]) -> Void)?
    var onConnectionError: ((Error) -> Void)?
    var isReady: Bool { threadID != nil && process?.isRunning == true }

    static var executable: URL? {
        ["/Applications/ChatGPT.app/Contents/Resources/codex",
         "/Applications/Codex.app/Contents/Resources/codex",
         "/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    func start(instructions: String, completion: @escaping (Result<Void, Error>) -> Void) {
        stop()
        guard let executable = Self.executable else {
            completion(.failure(CodexBridgeError("没有找到已安装的 Codex。"))); return
        }
        let current = generation
        let proc = Process(), stdin = Pipe(), stdout = Pipe()
        proc.executableURL = executable
        proc.arguments = ["app-server", "--stdio", "-c", "mcp_servers={}",
                          "--disable", "apps", "--disable", "shell_tool",
                          "--disable", "multi_agent", "-c", "web_search=\"disabled\""]
        proc.standardInput = stdin; proc.standardOutput = stdout
        proc.standardError = FileHandle.nullDevice
        proc.currentDirectoryURL = FileManager.default.temporaryDirectory
        process = proc; input = stdin.fileHandleForWriting; output = stdout.fileHandleForReading
        output?.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { @MainActor in
                guard let self, self.generation == current else { return }
                if data.isEmpty { self.failAll(CodexBridgeError("Codex 连接已关闭。")); return }
                self.consume(data)
            }
        }
        proc.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == current else { return }
                self.failAll(CodexBridgeError("Codex 已退出，请检查登录和使用额度。"))
            }
        }
        do { try proc.run() } catch { stop(); completion(.failure(error)); return }
        request("initialize", ["clientInfo": ["name": "celldock_phone", "version": "0.4.0"],
                               "capabilities": ["experimentalApi": true]]) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error): completion(.failure(error))
            case .success:
                self.send(["method": "initialized"])
                self.request("account/read", ["refreshToken": false]) { result in
                    guard case .success(let info) = result,
                          let account = info["account"] as? [String: Any],
                          account["type"] as? String == "chatgpt" else {
                        completion(.failure(CodexBridgeError("请先在 Codex 中使用 ChatGPT 登录。"))); return
                    }
                    self.request("thread/start", [
                        "ephemeral": true, "environments": [], "selectedCapabilityRoots": [],
                        "cwd": FileManager.default.temporaryDirectory.path,
                        "sandbox": "read-only", "approvalPolicy": "never",
                        "baseInstructions": "You are an AI telephone assistant. Only speak to the caller. You have no tools. Do not output analysis, code, Markdown, or instructions to a computer.",
                        "developerInstructions": instructions
                    ]) { result in
                        switch result {
                        case .failure(let error): completion(.failure(error))
                        case .success(let result):
                            self.threadID = (result["thread"] as? [String: Any])?["id"] as? String
                            if self.threadID != nil { completion(.success(())) }
                            else { completion(.failure(CodexBridgeError("Codex 没有返回会话 ID。"))) }
                        }
                    }
                }
            }
        }
    }

    func respond(to text: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let threadID, reply == nil else {
            completion(.failure(CodexBridgeError("Codex 尚未就绪或正在回复。"))); return
        }
        reply = completion; response = ""
        request("turn/start", ["threadId": threadID, "environments": [], "effort": "low",
                               "input": [["type": "text", "text": text]]]) { [weak self] result in
            if case .failure(let error) = result { self?.finish(.failure(error)) }
        }
        let timeout = DispatchWorkItem { [weak self] in
            self?.finish(.failure(CodexBridgeError("Codex 回复超时。")))
            self?.stop()
        }
        deadline = timeout; DispatchQueue.main.asyncAfter(deadline: .now() + 45, execute: timeout)
    }

    func startRealtime(sdp: String, instructions: String, voice: String? = nil,
                       completion: @escaping (Result<Void, Error>) -> Void) {
        guard let threadID else { completion(.failure(CodexBridgeError("Codex 尚未就绪。"))); return }
        var params: [String: Any] = ["threadId": threadID, "outputModality": "audio",
            "version": "v3", "transport": ["type": "webrtc", "sdp": sdp],
            "includeStartupContext": false, "prompt": instructions,
            "realtimeEndInstructions": "The telephone call has ended. Do not perform any actions or send messages."]
        if let voice { params["voice"] = voice }
        request("thread/realtime/start", params)
        { result in completion(result.map { _ in () }) }
    }

    func appendRealtimeText(_ text: String) {
        guard let threadID else { return }
        request("thread/realtime/appendText", ["threadId": threadID, "text": text]) { [weak self] result in
            if case .failure(let error) = result { self?.onConnectionError?(error) }
        }
    }

    func stop() {
        generation = UUID()
        output?.readabilityHandler = nil
        process?.terminationHandler = nil
        try? input?.close()
        if process?.isRunning == true { process?.terminate() }
        process = nil; input = nil; output = nil; buffer.removeAll(); threadID = nil
        failAll(CodexBridgeError("Codex 会话已结束。"))
    }

    private func request(_ method: String, _ params: [String: Any], completion: @escaping (Result<[String: Any], Error>) -> Void) {
        sequence += 1; let id = sequence
        requests[id] = completion
        send(["id": id, "method": method, "params": params])
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [weak self] in
            self?.requests.removeValue(forKey: id)?(.failure(CodexBridgeError("Codex 请求超时：\(method)")))
        }
    }

    private func send(_ message: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: message) else { return }
        do { try input?.write(contentsOf: data + Data([10])) }
        catch { failAll(error) }
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        guard buffer.count <= 4_000_000 else { stop(); return }
        while let newline = buffer.firstIndex(of: 10) {
            let line = Data(buffer[..<newline]); buffer.removeSubrange(...newline)
            guard let message = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { continue }
            if let id = message["id"] as? Int, let callback = requests.removeValue(forKey: id) {
                if let error = message["error"] as? [String: Any] {
                    callback(.failure(CodexBridgeError(error["message"] as? String ?? "Codex 请求失败。")))
                } else { callback(.success(message["result"] as? [String: Any] ?? [:])) }
                continue
            }
            // Caller speech must never acquire host tools or approval authority.
            if let id = message["id"], message["method"] != nil {
                send(["id": id, "error": ["code": -32601, "message": "Phone conversation has no tools or approval authority"]])
                continue
            }
            let params = message["params"] as? [String: Any] ?? [:]
            if let method = message["method"] as? String, method.hasPrefix("thread/realtime/") {
                onRealtimeEvent?(method, params)
                continue
            }
            switch message["method"] as? String {
            case "item/agentMessage/delta": response += params["delta"] as? String ?? ""
            case "turn/completed":
                let turn = params["turn"] as? [String: Any] ?? [:]
                if turn["status"] as? String == "completed", !response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    finish(.success(response.trimmingCharacters(in: .whitespacesAndNewlines)))
                } else {
                    let error = turn["error"] as? [String: Any]
                    finish(.failure(CodexBridgeError(error?["message"] as? String ?? "Codex 未能完成回复。")))
                }
            default: break
            }
        }
    }

    private func finish(_ result: Result<String, Error>) {
        deadline?.cancel(); deadline = nil
        let callback = reply; reply = nil; response = ""; callback?(result)
    }

    private func failAll(_ error: Error) {
        let wasConnected = threadID != nil
        threadID = nil
        let pending = requests.values; requests.removeAll()
        for callback in pending { callback(.failure(error)) }
        finish(.failure(error))
        if wasConnected { onConnectionError?(error) }
    }
}

struct CodexBridgeError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
