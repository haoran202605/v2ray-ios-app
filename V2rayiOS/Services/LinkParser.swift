import Foundation

/// Parses share links into ServerConfig. Supports vless://, vmess://, trojan://, ss://
enum LinkParser {

    static func parse(_ raw: String) -> ServerConfig? {
        let link = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let scheme = link.components(separatedBy: "://").first,
              let url = URL(string: link) else { return nil }

        switch scheme {
        case "vless":  return parseVLESS(link, url)
        case "vmess":  return parseVMess(link, url)
        case "trojan": return parseTrojan(link, url)
        case "ss":     return parseSS(link, url)
        default:
            if let data = Data(base64Encoded: link) {
                let obj = try? JSONSerialization.jsonObject(with: data)
                return parseVMessJSON(obj)
            }
            return nil
        }
    }

    // MARK: - vless://

    private static func parseVLESS(_ link: String, _ url: URL) -> ServerConfig? {
        guard let components = URLComponents(string: link) else { return nil }
        var cfg = ServerConfig(
            name: "",
            proto: .vless,
            address: url.host ?? "",
            port: url.port ?? 443,
            uuid: url.user ?? ""
        )
        cfg.sni = url.host ?? ""
        var query = [String: String]()
        if let q = components.queryItems {
            for item in q {
                if let key = item.name, let value = item.value {
                    query[key] = value
                }
            }
        }
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
        if let remarks = query["remarks"] {
            let decoded = (remarks as NSString).removingPercentEncoding ?? remarks
            cfg.name = decoded
        } else {
            cfg.name = "VLESS-\(url.host ?? "?")"
        }
        return cfg
    }

    // MARK: - vmess://

    private static func parseVMess(_ link: String, _ url: URL) -> ServerConfig? {
        let base = link.components(separatedBy: "://").last ?? ""
        guard let data = Data(base64Encoded: base) else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return parseVMessJSON(obj)
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

    private static func parseTrojan(_ link: String, _ url: URL) -> ServerConfig? {
        guard let components = URLComponents(string: link) else { return nil }
        var cfg = ServerConfig(
            name: "Trojan-\(url.host ?? "?")",
            proto: .trojan,
            address: url.host ?? "",
            port: url.port ?? 443,
            uuid: url.user ?? "",
            security: .tls
        )
        cfg.sni = url.host ?? ""
        var query = [String: String]()
        if let q = components.queryItems {
            for item in q {
                if let key = item.name, let value = item.value {
                    query[key] = value
                }
            }
        }
        if let sni = query["sni"] { cfg.sni = sni }
        if let remarks = query["remarks"] {
            let decoded = (remarks as NSString).removingPercentEncoding ?? remarks
            cfg.name = decoded
        }
        return cfg
    }

    // MARK: - ss://

    private static func parseSS(_ link: String, _ url: URL) -> ServerConfig? {
        let base = link.components(separatedBy: "://").last ?? ""
        let decoded = (base as NSString).removingPercentEncoding ?? base
        guard let token = String(data: decoded.data(using: .utf8) ?? Data(), encoding: .utf8) else {
            return nil
        }
        let parts = token.components(separatedBy: "@")
        guard let right = parts.last, right.contains(":") else { return nil }
        let userParts = right.components(separatedBy: ":")
        guard userParts.count >= 3 else { return nil }
        var cfg = ServerConfig(
            name: "SS-\(url.host ?? "?")",
            proto: .shadowsocks,
            address: url.host ?? "",
            port: url.port ?? 8388,
            uuid: userParts[2],
            security: .none
        )
        if let q = URLComponents(string: link)?.query {
            let items = q.components(separatedBy: "&")
            if let remark = items.first(where: { $0.hasPrefix("remarks=") }) {
                let key = remark.components(separatedBy: "=").first ?? "remarks"
                let value = remark.components(separatedBy: "=").dropFirst().joined(separator: "=")
                let decoded = (value as NSString).removingPercentEncoding ?? value
                cfg.name = decoded
            }
        }
        return cfg
    }
}
