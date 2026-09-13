import Foundation
import Network

enum CodexHTTPError: Error, Equatable { case malformed, unauthorized, tooLarge }

enum CodexHTTPRequest {
    static let maximumBytes = 262_144
    /// The control surface accepts one authenticated JSON request per connection.
    /// Browser-origin requests and ambiguous HTTP framing are always rejected.
    static func body(_ data: Data, token: String) throws -> Data? {
        guard data.count <= maximumBytes else { throw CodexHTTPError.tooLarge }
        guard let boundary = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        guard let header = String(data: data[..<boundary.lowerBound], encoding: .utf8) else { throw CodexHTTPError.malformed }
        let lines = header.components(separatedBy: "\r\n")
        guard lines.first == "POST /rpc HTTP/1.1" else { throw CodexHTTPError.malformed }
        var fields: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { throw CodexHTTPError.malformed }
            let key = line[..<colon].lowercased()
            guard fields[key] == nil else { throw CodexHTTPError.malformed }
            fields[key] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        guard fields["origin"] == nil, fields["authorization"] == "Bearer \(token)" else { throw CodexHTTPError.unauthorized }
        guard fields["transfer-encoding"] == nil,
              let rawLength = fields["content-length"], let length = Int(rawLength),
              length >= 0, length <= maximumBytes - boundary.upperBound else { throw CodexHTTPError.malformed }
        let end = boundary.upperBound + length
        guard data.count >= end else { return nil }
        guard data.count == end else { throw CodexHTTPError.malformed }
        return Data(data[boundary.upperBound..<end])
    }
}

final class CodexBridgeHTTPServer {
    typealias Handler = ([String: Any], @escaping ([String: Any]) -> Void) -> Void
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "app.celldock.codex.http")
    private var connections: [ObjectIdentifier: NWConnection] = [:]

    func start(token: String, handler: @escaping Handler) throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: 8767)
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { connection.cancel(); return }
            let id = ObjectIdentifier(connection)
            self.connections[id] = connection
            connection.stateUpdateHandler = { [weak self] state in
                if case .cancelled = state { self?.connections.removeValue(forKey: id) }
                if case .failed = state { connection.cancel() }
            }
            connection.start(queue: self.queue)
            self.read(connection, data: Data(), token: token, handler: handler)
            self.queue.asyncAfter(deadline: .now() + 75) { connection.cancel() }
        }
        self.listener = listener; listener.start(queue: queue)
    }

    func stop() {
        listener?.cancel(); listener = nil
        queue.async { [weak self] in
            guard let self else { return }
            let current = Array(self.connections.values)
            self.connections.removeAll()
            current.forEach { $0.cancel() }
        }
    }

    private func read(_ connection: NWConnection, data: Data, token: String, handler: @escaping Handler) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] chunk, _, complete, error in
            guard let self else { connection.cancel(); return }
            var data = data; if let chunk { data.append(chunk) }
            do {
                if let body = try CodexHTTPRequest.body(data, token: token) {
                    guard let request = try JSONSerialization.jsonObject(with: body) as? [String: Any] else { throw CodexHTTPError.malformed }
                    DispatchQueue.main.async { handler(request) { response in self.respond(connection, status: 200, response: response) } }
                } else if complete || error != nil { connection.cancel() }
                else { self.read(connection, data: data, token: token, handler: handler) }
            } catch {
                self.respond(connection, status: error is CodexHTTPError && (error as? CodexHTTPError) == .unauthorized ? 401 : 400,
                             response: ["ok": false, "error": "Invalid or unauthorized request"])
            }
        }
    }

    private func respond(_ connection: NWConnection, status: Int, response: [String: Any]) {
        let body = (try? JSONSerialization.data(withJSONObject: response, options: [.sortedKeys])) ?? Data("{}".utf8)
        let header = "HTTP/1.1 \(status) \(status == 200 ? "OK" : "Error")\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(header.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
    }
}
