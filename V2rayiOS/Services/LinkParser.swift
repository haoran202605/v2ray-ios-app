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
        case "vmess":  return parseVMess(link: link, url: url)
        case "trojan": return parseTrojan(link: link, url: url)
        case "ss":     return parseSS(link: link, url: url)
        case "ss-base64":
            // some clients use data-based ss links; fall through to generic base64
            return parseBase64JSON(link: link)
        default:
            return parseBase64JSON(link: link)
        }
    }

    // MARK: - base64-JSON (vmess:// and legacy)

    private static func parseBase64JSON(link: String) -> ServerConfig? {
        let base = link.components(separatedBy: "://").last ?? ""
        guard let data = Data(base64Encoded: base),
              let obj = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        return parseVMessJSON(obj)
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
        } else {
            cfg.name = "VLESS-\(host)"
        }
        return cfg
    }

    // MARK: - vmess://

    private static func parseVMess(link: String, url: URL) -> ServerConfig? {
        _ = url
        return parseBase64JSON(link: link)
    }

    private static func parseVMessJSON(_ obj: Any?) -> ServerConfig? {
        guard let dict = obj as? [String: Any] else { return nil }
        let address = (dict["add"] as? String) ?? ""
        let portStr = (dict["port"] as? String) ?? ""
        let port = Int(portStr) ?? 443
        let id = (dict["id"] as? String) ?? ""
        let net = (dict["net"] as? String).flatMap(TransportType.init(rawValue:)) ?? .tcp
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
        if let path = dict["path"] as? String { cfg.path = path }
        if let host = dict["host"] as? String { cfg.sni = host }
        if let remarks = dict["ps"] as? String, !remarks.isEmpty {
            cfg.name = remarks
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

    private static func parseQuery(link: String) -> [String: String] {
        guard let components = URLComponents(string: link),
              let q = components.queryItems else { return [:] }
        var result = [String: String]()
        for item in q {
            if let key = item.name, let value = item.value {
                result[key] = value
            }
        }
        return result
    }

    private static func decodePct(_ value: String?) -> String? {
        guard let value else { return nil }
        return value.removingPercentEncoding ?? value
    }
}
