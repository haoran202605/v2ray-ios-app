import Foundation

/// Persists server list in the App Group container so the VPN extension can read it.
final class ConfigStore {

    static let shared = ConfigStore()

    private let groupID = AppSettings.appGroupID
    private let serversKey = "servers"
    private let lastConfigKey = "active_singbox_config"

    private var defaults: UserDefaults {
        UserDefaults(suiteName: groupID) ?? UserDefaults.standard
    }

    func containerURL() -> URL? {
        let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)
        return container
    }

    func loadServers() -> [ServerConfig] {
        guard let data = defaults.data(forKey: serversKey) else { return [] }
        return (try? JSONDecoder().decode([ServerConfig].self, from: data)) ?? []
    }

    func saveServers(_ servers: [ServerConfig]) {
        guard let data = try? JSONEncoder().encode(servers) else { return }
        defaults.set(data, forKey: serversKey)
    }

    /// Writes the sing-box JSON config the extension will consume.
    func writeActiveConfig(json: String) {
        if let container = containerURL() {
            let path = container.appendingPathComponent("singbox-active.json")
            try? json.write(to: path, atomically: true, encoding: .utf8)
        }
        defaults.set(json, forKey: lastConfigKey)
    }

    func readActiveConfig() -> String? {
        defaults.string(forKey: lastConfigKey)
    }

    func selectedServerID() -> UUID? {
        AppSettings.load().selectedServerID
    }

    func setSelectedServer(_ id: UUID?) {
        var s = AppSettings.load()
        s.selectedServerID = id
        s.save()
    }
}
