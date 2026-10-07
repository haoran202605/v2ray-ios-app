import Foundation

/// Parses share links into ServerConfig. Supports vless://, vmess://, trojan://, ss://
enum LinkParser {

    static func parse(_ raw: String) -> ServerConfig? {
        let link = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = link.components(separatedBy: "://")
        guard parts.count >= 2, let scheme = parts.first else { return nil }
        guard let url = URL(string: link) else { return nil }

        switch scheme {
        case "vless":  return parseVLESS(link: link, url: url)
        case "vmess":  return parseVMessJSON(link: link)
        case "trojan": return parseTrojan(link: link, url: url)
        case "ss":     return parseSS(link: link, url: url)
        default:
            return parseVMessJSON(link: link)
        }
    }

    // MARK: - base64-JSON (vmess:// and legacy)

    private static func parseVMessJSON(link: String) -> ServerConfig? {
        let base = link.components(separatedBy: "://").last ?? ""
        guard let data = Data(base64Encoded: base) else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: data) else { return nil }
        guard let dict = obj as? [String: Any] else { return nil }

        let address = (dict["add"] as? String) ?? ""
        let portStr = (dict["port"] as? String) ?? ""
        let port = Int(portStr) ?? 443
        let id = (dict["id"] as? String) ?? ""
        let net = (dict["net"] as? String).flatMap { TransportType(rawValue: $0) } ?? .tcp
        let security = (dict["security"] as? String) ?? "none"

        var cfg = ServerConfig(
            name: "VMESS-\(address)",
            proto: .vmess,
            address: address,
            port: port,
            uuid: id,
            security: SecurityMode(rawValue: security) ?? .none
        )
        cfg.network = net
        if let p = dict["path"] as? String { cfg.path = p }
        if let h = dict["host"] as? String { cfg.sni = h }
        if let ps = dict["ps"] as? String, !ps.isEmpty {
            cfg.name = ps
        }
        return cfg
    }

    // MARK: - vless://

    private static func parseVLESS(link: String, url: URL) -> ServerConfig? {
        guard let host = url.host else { return nil }
        var cfg = ServerConfig(
            name: "",
            proto: .vless,
            address: host,
            port: url.port ?? 443,
            uuid: url.user ?? ""
        )
        cfg.sni = host
        let query = parseQuery(link: link)
        applyQuery(query, to: &cfg)
        if cfg.name.isEmpty {
            cfg.name = "VLESS-\(host)"
        }
        return cfg
    }

    // MARK: - trojan://

    private static func parseTrojan(link: String, url: URL) -> ServerConfig? {
        guard let host = url.host else { return nil }
        var cfg = ServerConfig(
            name: "Trojan-\(host)",
            proto: .trojan,
            address: host,
            port: url.port ?? 443,
            uuid: url.user ?? "",
            security: .tls
        )
        cfg.sni = host
        let query = parseQuery(link: link)
        if let sni = query["sni"] { cfg.sni = sni }
        if let remarks = decodePct(query["remarks"]) {
            cfg.name = remarks
        }
        return cfg
    }

    // MARK: - ss://

    private static func parseSS(link: String, url: URL) -> ServerConfig? {
        let host = url.host ?? ""
        let port = url.port ?? 8388
        let query = parseQuery(link: link)
        var cfg = ServerConfig(
            name: "SS-\(host)",
            proto: .shadowsocks,
            address: host,
            port: port,
            uuid: decodePct(query["password"]) ?? "",
            security: .none
        )
        if let remarks = decodePct(query["remarks"]) {
            cfg.name = remarks
        }
        return cfg
    }

    // MARK: - helpers

    /// Applies shared query params to a config.
    private static func applyQuery(_ query: [String: String], to cfg: inout ServerConfig) {
        if let sec = query["security"], let mode = SecurityMode(rawValue: sec) {
            cfg.security = mode
        }
        if let sni = query["sni"] { cfg.sni = sni }
        if let net = query["type"], let tt = TransportType(rawValue: net) { cfg.network = tt }
        if let path = query["path"] { cfg.path = path }
        if let flow = query["flow"] { cfg.flow = flow }
        if let pk = query["pbk"] { cfg.publicKey = pk }
        if let sid = query["sid"] { cfg.shortId = sid }
        if let fp = query["fp"] { cfg.fingerprint = fp }
        if let remarks = decodePct(query["remarks"]) {
            cfg.name = remarks
        }
    }

    private static func parseQuery(link: String) -> [String: String] {
        guard let components = URLComponents(string: link) else {
            return [:]
        }
        let items = components.queryItems
        guard items != nil else {
            return [:]
        }
        var result = [String: String]()
        for item in items! {
            result[item.name] = item.value
        }
        return result
    }

    private static func decodePct(_ value: String?) -> String? {
        guard let value else { return nil }
        return value.removingPercentEncoding ?? value
    }
}
