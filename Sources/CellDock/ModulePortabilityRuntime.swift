import CryptoKit
import Foundation

enum ModulePortabilityRuntime {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Returns true only after a detached switch has been acknowledged. Never
    /// repeat the launch after an ambiguous transport result: reconnect/read.
    static func prepareMacSession(controller: ADBModuleController) throws -> Bool {
        let probe = try controller.shellChecked(
            "cat /sys/class/android_usb/android0/functions; " +
            "if test -f /run/celldock-portable/pid; then " +
            "pid=$(cat /run/celldock-portable/pid); " +
            "case $pid in ''|*[!0-9]*) exit 20;; esac; " +
            "if kill -0 \"$pid\" 2>/dev/null && " +
            "tr '\\000' ' ' </proc/$pid/cmdline | grep -Fq '\(ModulePortabilityPolicy.scriptPath)'; " +
            "then echo watcher_ready; fi; fi", timeout: 8)
        guard probe.status == 0 else { throw Failure(message: "无法读取模块的临时 USB 配置。") }
        let lines = probe.output.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard let functions = lines.first,
              [ModulePortabilityPolicy.fullFunctions, ModulePortabilityPolicy.mobileFunctions].contains(functions) else {
            throw Failure(message: "模块实际 USB 接口组合不在已验证范围内，未执行切换。")
        }
        if lines.contains("watcher_ready") {
            // A preceding launch can be in its one-second acknowledgement
            // window. Wait for enumeration; do not launch a second process.
            return functions == ModulePortabilityPolicy.mobileFunctions
        }
        let directory = ModulePortabilityPolicy.directory
        let prepare = try controller.shellChecked(
            "umask 077; mkdir -p '\(directory)'; rm -f '\(directory)/started'", timeout: 8)
        guard prepare.status == 0 else { throw Failure(message: "无法准备模块的临时切换目录。") }
        let data = Data(ModulePortabilityPolicy.sessionScript.utf8)
        try controller.push(data, to: ModulePortabilityPolicy.scriptPath, mode: 0o100700)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let verify = try controller.shellChecked("sha256sum '\(ModulePortabilityPolicy.scriptPath)'", timeout: 8)
        guard verify.status == 0, verify.output.split(whereSeparator: { $0.isWhitespace }).first == Substring(digest) else {
            throw Failure(message: "模块切换脚本的校验失败，未执行切换。")
        }
        let launch = try controller.shellChecked(
            "setsid /bin/sh '\(ModulePortabilityPolicy.scriptPath)' </dev/null " +
            "> '\(directory)/session.log' 2>&1 & pid=$!; " +
            "sleep 0.3; kill -0 \"$pid\" && test -s '\(directory)/started'", timeout: 8)
        guard launch.status == 0 else { throw Failure(message: "模块临时切换未能启动，请重新插拔模块。") }
        return functions == ModulePortabilityPolicy.mobileFunctions
    }

    static func saveBackup(imei: String, firmware: String, configuration: String, target: String) throws {
        guard imei.count == 15, imei.allSatisfy(\.isNumber) else {
            throw Failure(message: "无法确认模块身份，未写入持久配置。")
        }
        let identity = SHA256.hash(data: Data(imei.utf8)).map { String(format: "%02x", $0) }.joined()
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CellDock/ModulePortability/\(identity)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let record: [String: Any] = ["schema": 1, "moduleHash": identity, "firmware": firmware,
                                   "usbnet": 1, "original": configuration, "requested": target,
                                   "createdAt": ISO8601DateFormatter().string(from: Date())]
        let data = try JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys])
        let path = directory.appendingPathComponent(UUID().uuidString + ".json")
        guard FileManager.default.createFile(atPath: path.path, contents: data, attributes: [.posixPermissions: 0o600]),
              try Data(contentsOf: path) == data else {
            throw Failure(message: "无法保存并核对模块原始配置，未执行写入。")
        }
    }
}
