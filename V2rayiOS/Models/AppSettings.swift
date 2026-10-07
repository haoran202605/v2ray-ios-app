import Foundation

struct AppSettings: Codable {
    var useSystemProxy: Bool = false
    var autoStartVPN: Bool = false
    var selectedServerID: UUID? = nil

    static let appGroupID = "group.com.yourname.v2rayios"

    static func load() -> AppSettings {
        let defaults = UserDefaults(suiteName: AppSettings.appGroupID) ?? UserDefaults.standard
        guard let data = defaults.data(forKey: "app_settings"),
              let s = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        return s
    }

    func save() {
        let defaults = UserDefaults(suiteName: AppSettings.appGroupID) ?? UserDefaults.standard
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: "app_settings")
        }
    }
}
