import Foundation

let token = String(repeating: "a", count: 64)
func http(_ body: String = "{}", authorization: String? = nil, extras: String = "") -> Data {
    Data("POST /rpc HTTP/1.1\r\nHost: 127.0.0.1:8767\r\nAuthorization: Bearer \(authorization ?? token)\r\nContent-Length: \(body.utf8.count)\r\n\(extras)\r\n\(body)".utf8)
}
func rejected(_ data: Data) {
    do { _ = try CodexHTTPRequest.body(data, token: token); fatalError("Accepted malformed/unauthorized HTTP") }
    catch { }
}
let valid = try CodexHTTPRequest.body(http(), token: token)
precondition(valid == Data("{}".utf8))
let request = http("{\"message\":\"中文\"}")
for length in 0..<request.count {
    let incomplete = try CodexHTTPRequest.body(Data(request.prefix(length)), token: token)
    precondition(incomplete == nil)
}
rejected(http(authorization: "wrong"))
rejected(http(extras: "Origin: https://example.com\r\n"))
rejected(http(extras: "Transfer-Encoding: chunked\r\n"))
rejected(http(extras: "Content-Length: 2\r\n"))
rejected(http() + http())
rejected(Data(repeating: 65, count: CodexHTTPRequest.maximumBytes + 1))
print("Codex bridge HTTP: authenticated requests, UTF-8 chunking, origin rejection, framing, size limit passed")
