import Foundation
import Combine
import Darwin

/// Manages the embedded sing-box binary **inside the main app process**
/// using `posix_spawn`.
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
    @Published private(set) var bytesUp: UInt64 = 0
    @Published private(set) var bytesDown: UInt64 = 0

    // MARK: - Private

    private let store = ConfigStore.shared
    private let groupID = AppSettings.appGroupID

    private var pid_t_handle: pid_t = 0
    private var statTimer: Timer?
    private var readPipe: Pipe?
    private var stderrPipe: Pipe?

    /// Inbound local ports sing-box will listen on.
    static let httpPort: UInt16 = 1080
    static let socksPort: UInt16 = 10808

    // MARK: - Public API

    /// Prepares the config JSON for the given server and signals that the
    /// proxy should be (re)started with it.
    func prepare(for server: ServerConfig) {
        let container = store.containerURL()
        let json = ProxyConfigGenerator.generate(for: server, appGroupContainer: container)
        store.writeActiveConfig(json: json)
        store.setSelectedServer(server.id)

        status = "config ready for \(server.name)"
    }

    /// Starts the embedded sing-box binary via `posix_spawn`.
    func startProxy() {
        guard !isRunning else { return }
        errorMessage = nil

        do {
            // 1. Extract the embedded binary to the app group's temp space.
            let binURL = try copyEmbeddedBinary()

            // 2. Make sure the active config file is present.
            guard let cfgJSON = store.readActiveConfig() else {
                throw StartError.noConfig
            }
            let cfgURL = try writeActiveConfigFile(json: cfgJSON)

            // 3. Build the argument vector: `sing-box run -c <cfg>`
            let args: [String] = ["run", "-c", cfgURL.path]

            // 4. Spawn.
            spawn(binary: binURL, arguments: args)

            // 5. Mark running + start a stats poller.
            isRunning = true
            status = "proxy running on 127.0.0.1:\(Self.httpPort) (http) / \(Self.socksPort) (socks)"
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

    /// Stops the running sing-box process and clears stats.
    func stopProxy() {
        if isRunning {
            kill(pid_t_handle, SIGTERM)
            // Give it a moment to exit, then SIGKILL as a fallback.
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self, self.pid_t_handle > 0 else { return }
                kill(self.pid_t_handle, SIGKILL)
            }
        }
        stopStatsPolling()
        isRunning = false
        pid_t_handle = 0
        status = "stopped"
        bytesUp = 0
        bytesDown = 0
    }

    /// The proxy address the user should point their browser / apps to.
    var proxyHTTPURL: String {
        isRunning ? "http://127.0.0.1:\(Self.httpPort)" : ""
    }

    var proxySOCKSURL: String {
        isRunning ? "socks://127.0.0.1:\(Self.socksPort)" : ""
    }

    // MARK: - Binary extraction

    /// Locates the embedded `sing-box` resource, copies it into the
    /// app-group container (where the extension/app can re-read it),
    /// and makes it executable.
    private func copyEmbeddedBinary() throws -> URL {
        // Primary: look for a resource named "sing-box" without extension.
        var url = Bundle.main.url(forResource: "sing-box", withExtension: nil)
        if url == nil {
            // Fallback: a resource with ".bin" extension.
            url = Bundle.main.url(forResource: "sing-box", withExtension: "bin")
        }
        guard let binURL = url else {
            throw StartError.binaryNotFound
        }

        // Destination: inside the app group container's "bin/" subdir.
        guard let container = store.containerURL() else {
            throw StartError.noAppGroup
        }
        let destDir = container.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        let destURL = destDir.appendingPathComponent("sing-box")

        // Re-copy every time so a replaced resource takes effect.
        if FileManager.default.fileExists(atPath: destURL.path) {
            try FileManager.default.removeItem(at: destURL)
        }
        try FileManager.default.copyItem(at: binURL, to: destURL)

        // chmod +x (0755).
        try FileManager.default.setAttributes([.posixPermissions: 0o755],
                                              ofItemAtPath: destURL.path)
        return destURL
    }

    /// Writes the active sing-box config JSON into the app group container.
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
        // argv is null-terminated; build the array as [execPath, ...args, ""].
        let execPath = binary.path
        var argv: [UnsafeMutablePointer<CChar>?] =
            arguments.map { $0.withCString { strdup($0) } }
        argv.insert(execPath.withCString { strdup($0) }, at: 0)
        argv.append(nil)

        var pid: pid_t = 0
        let spawnAttr = UnsafeMutablePointer<posix_spawnattr_t>.allocate(capacity: 1)
        let spawnFileActions = UnsafeMutablePointer<posix_spawn_file_actions_t>.allocate(capacity: 1)
        defer {
            spawnAttr.deallocate()
            spawnFileActions.deallocate()
            argv.forEach { if let p = $0 { free(p) } }
        }

        posix_spawnattr_init(spawnAttr)
        posix_spawn_file_actions_init(spawnFileActions)

        // Redirect stdout/stderr to pipes we own (so we can log).
        let outPipe = Pipe()
        let errPipe = Pipe()
        self.readPipe = outPipe
        self.stderrPipe = errPipe

        posix_spawn_file_actions_addopen(spawnFileActions, STDOUT_FILENO,
                                         outPipe.fileHandleForWriting.path)
        posix_spawn_file_actions_addopen(spawnFileActions, STDERR_FILENO,
                                         errPipe.fileHandleForWriting.path)

        let execPathC = strdup(execPath)
        defer { free(execPathC) }

        let ret = posix_spawn(&pid, execPathC, spawnFileActions, spawnAttr,
                              &argv[0], environ)
        if ret != 0 {
            throw StartError.spawnFailed(errno: ret)
        }

        // Keep writes open long enough, then close the write ends we held.
        outPipe.fileHandleForWriting.closeFile()
        errPipe.fileHandleForWriting.closeFile()

        // Stream stdout + stderr into NSLog.
        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                if let s = String(data: data, encoding: .utf8) {
                    NSLog("[V2RayiOS/sing-box] \(s)")
                }
            }
        }
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                if let s = String(data: data, encoding: .utf8) {
                    NSLog("[V2RayiOS/sing-box-err] \(s)")
                }
            }
        }

        pid_t_handle = pid
    }

    // MARK: - Stats polling

    /// sing-box's API service or its own counters are not exposed here in
    /// the MVP. We approximate by polling /proc-equivalent state via a
    /// lightweight check that the process is still alive. Real byte
    /// counters should come from sing-box's REST API (`experimental.api`).
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
        guard pid_t_handle > 0 else { return false }
        return kill(pid_t_handle, 0) == 0
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
