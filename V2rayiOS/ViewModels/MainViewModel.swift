import SwiftUI
import Combine

@MainActor
class MainViewModel: ObservableObject {

    @Published var servers: [ServerConfig] = []
    @Published var selectedServer: ServerConfig?
    @Published var isConnected = false
    @Published var isConnecting = false
    @Published var errorMessage: String?
    @Published var statusMessage = ""
    @Published var showAddServer = false
    @Published var showSettings = false

    private let store = ConfigStore.shared
    let singbox = SingBoxService()
    private var cancellables: Set<AnyCancellable> = []

    init() {
        load()
        observeService()
    }

    private func observeService() {
        singbox.$isRunning
            .receive(on: DispatchQueue.main)
            .sink { [weak self] running in self?.isConnected = running }
            .store(in: &cancellables)

        singbox.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] s in
                guard let self, s != "idle" else { return }
                self.statusMessage = s
            }
            .store(in: &cancellables)

        singbox.$errorMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.errorMessage = $0 }
            .store(in: &cancellables)
    }

    // MARK: - Servers

    func refresh() { load() }

    func load() {
        servers = store.loadServers()
        if let id = store.selectedServerID(), let s = servers.first(where: { $0.id == id }) {
            selectedServer = s
        } else {
            selectedServer = servers.first
        }
    }

    func addServer(_ config: ServerConfig) {
        guard !servers.contains(where: { $0.id == config.id }) else { return }
        servers.append(config)
        store.saveServers(servers)
        selectedServer = config
    }

    func importLinks(_ links: [String]) -> Int {
        var count = 0
        for link in links {
            if let cfg = LinkParser.parse(link) {
                if !servers.contains(where: { $0.uuid == cfg.uuid && $0.address == cfg.address && $0.port == cfg.port }) {
                    servers.append(cfg)
                    count += 1
                }
            }
        }
        if count > 0 { store.saveServers(servers) }
        return count
    }

    func removeServer(_ s: ServerConfig) {
        if selectedServer?.id == s.id {
            selectedServer = servers.first(where: { $0.id != s.id })
        }
        servers.removeAll { $0.id == s.id }
        store.saveServers(servers)
    }

    // MARK: - Connect / Disconnect

    func select(_ s: ServerConfig) {
        selectedServer = s
        store.setSelectedServer(s.id)
    }

    func connect() {
        guard let s = selectedServer else {
            errorMessage = "请先添加或选择一个服务器"
            return
        }
        isConnecting = true
        errorMessage = nil
        statusMessage = "正在启动 \(s.name) ..."

        singbox.prepare(for: s)
        singbox.startProxy()
        isConnecting = false

        isConnected = singbox.isRunning
        statusMessage = isConnected
            ? "代理已启动：\(singbox.proxySOCKSURL)"
            : singbox.status
    }

    func disconnect() {
        singbox.stopProxy()
        isConnected = false
        statusMessage = "已断开连接"
    }
}
