import Foundation
import Combine
import Darwin

/// Manages the embedded sing-box binary **inside the main app process**.
///
/// Requirements for the real runtime:
/// - A `sing-box` binary (iOS/arm64) added to the main app target's
///   "Copy Bundle Resources".
/// - The binary MUST be signed as part of the app bundle; unsigned
///   executables cannot run inside an iOS app's sandbox.
/// - App Group container for the config file.
final class SingBoxService: ObservableObject {

    // MARK: - Published state

    @Published private(set) var isRunning = false
    @Published private(set) var status: String = "idle"
    @Published private(set) var errorMessage: String?

    // MARK: - Private

    private let store = ConfigStore.shared
    private var childPid: pid_t = 0
    private var statTimer: Timer?

    /// Inbound local ports sing-box will listen on.
    static let httpPort: UInt16 = 1080
    static let socksPort: UInt16 = 10808

    // MARK: - Public API

    /// Prepares the config JSON for the given server.
    func prepare(for server: ServerConfig) {
        let container = store.containerURL()
        let json = ProxyConfigGenerator.generate(for: server, appGroupContainer: container)
        store.writeActiveConfig(json: json)
        store.setSelectedServer(server.id)
        status = "config ready for \(server.name)"
    }

    /// Starts the embedded sing-box binary.
    func startProxy() {
        guard !isRunning else { return }
        errorMessage = nil
        do {
            let binURL = try copyEmbeddedBinary()
            guard let cfgJSON = store.readActiveConfig() else { throw StartError.noConfig }
            let cfgURL = try writeActiveConfigFile(json: cfgJSON)
            let args: [String] = ["run", "-c", cfgURL.path]
            spawn(binary: binURL, arguments: args)
            isRunning = true
            status = "proxy running on 127.0.0.1:\(Self.httpPort) / \(Self.socksPort)"
            startStatsPolling()
        } catch let e as StartError {
            isRunning = false
            status = "start failed"
            errorMessage = "启动失败: \(e.localizedDescription)"
        } catch {
            isRunning = false
            status = "start failed"
            errorMessage = "启动失败: \(error.localizedDescription)"
        }
    }

    /// Stops the running sing-box process.
    func stopProxy() {
        if isRunning {
            kill(childPid, SIGTERM)
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self, self.childPid > 0 else { return }
                kill(self.childPid, SIGKILL)
            }
        }
        stopStatsPolling()
        isRunning = false
        childPid = 0
        status = "stopped"
    }

    var proxyHTTPURL: String {
        isRunning ? "http://127.0.0.1:\(Self.httpPort)" : ""
    }

    var proxySOCKSURL: String {
        isRunning ? "socks://127.0.0.1:\(Self.socksPort)" : ""
    }

    // MARK: - Binary extraction

    private func copyEmbeddedBinary() throws -> URL {
        var url = Bundle.main.url(forResource: "sing-box", withExtension: nil)
        if url == nil {
            url = Bundle.main.url(forResource: "sing-box", withExtension: "bin")
        }
        guard let binURL = url else {
            throw StartError.binaryNotFound
        }
        guard let container = store.containerURL() else {
            throw StartError.noAppGroup
        }
        let destDir = container.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        let destURL = destDir.appendingPathComponent("sing-box")
        if FileManager.default.fileExists(atPath: destURL.path) {
            try FileManager.default.removeItem(at: destURL)
        }
        try FileManager.default.copyItem(at: binURL, to: destURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755],
                                              ofItemAtPath: destURL.path)
        return destURL
    }

    private func writeActiveConfigFile(json: String) throws -> URL {
        guard let container = store.containerURL() else {
            throw StartError.noAppGroup
        }
        let cfgURL = container.appendingPathComponent("singbox-active.json")
        try json.write(to: cfgURL, atomically: true, encoding: .utf8)
        return cfgURL
    }

    // MARK: - posix_spawn

    private func spawn(binary: URL, arguments: [String]) throws {
        let execPath = binary.path
        var argv: [UnsafeMutablePointer<CChar>?] = []
        for a in [execPath] + arguments {
            argv.append(strdup(a))
        }
        argv.append(nil)

        var pid: pid_t = 0

        let spawnAttr: UnsafeMutablePointer<posix_spawnattr_t>? = UnsafeMutablePointer<posix_spawnattr_t>.allocate(capacity: 1)
        spawnAttr?.pointee = posix_spawnattr_t()
        posix_spawnattr_init(spawnAttr)

        let ret = posix_spawn(&pid,
                              strdup(execPath),
                              nil,
                              spawnAttr,
                              argv,
                              environ)

        for p in argv where p != nil { free(p) }
        if let execC = strdup(execPath) { free(execC) }
        spawnAttr?.deallocate()

        if ret != 0 {
            throw StartError.spawnFailed(errno: ret)
        }
        childPid = pid
    }

    // MARK: - Stats polling

    private func startStatsPolling() {
        stopStatsPolling()
        statTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            if !self.isProcessAlive() {
                self.isRunning = false
                self.status = "process exited"
                self.errorMessage = "sing-box 进程已退出"
                self.stopStatsPolling()
            }
        }
    }

    private func stopStatsPolling() {
        statTimer?.invalidate()
        statTimer = nil
    }

    private func isProcessAlive() -> Bool {
        guard childPid > 0 else { return false }
        return kill(childPid, 0) == 0
    }

    // MARK: - Errors

    enum StartError: LocalizedError {
        case binaryNotFound
        case noAppGroup
        case noConfig
        case spawnFailed(errno: Int32)

        var errorDescription: String? {
            switch self {
            case .binaryNotFound:
                return "App Bundle 里找不到 sing-box 二进制，请先把它加进 target 的 Copy Bundle Resources"
            case .noAppGroup:
                return "App Group 容器不可用，请检查 entitlements 里的 group 是否配好"
            case .noConfig:
                return "尚未生成 sing-box 配置，请先选择一个服务器再点连接"
            case .spawnFailed(let errno):
                return "posix_spawn 失败 (errno=\(errno))：二进制可能未签名或架构不匹配"
            }
        }
    }
}
