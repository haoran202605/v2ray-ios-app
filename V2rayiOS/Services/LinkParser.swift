import Foundation

/// Parses share links into ServerConfig. Supports vless://, vmess://, trojan://, ss://
enum LinkParser {

    static func parse(_ raw: String) -> ServerConfig? {
        let link = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let scheme = link.scheme, let url = URL(string: link) else { return nil }

        switch scheme {
        case "vless":  return parseVLESS(link, url)
        case "vmess":  return parseVMess(link, url)
        case "trojan": return parseTrojan(link, url)
        case "ss":     return parseSS(link, url)
        default:
            // maybe raw base64 JSON (vmess)
            if let data = Data(base64Encoded: link),
               let obj = try? JSONSerialization.jsonObject(with: data) {
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
            protocol: .vless,
            address: url.host ?? "",
            port: url.port ?? 443,
            uuid: url.user ?? "",
            security: .tls
        )
        cfg.sni = url.host ?? ""
        let query = (components.query?.split(separator: "&").compactMap {
            let kv = $0.split(separator: ":", maxSplits: 1)
            guard kv.count == 2 else { return nil }
            return (String(kv[0]), String(kv[1]))
        } ?? []).reduce(into: [String: String]()) { $0[String($1.0)] = $1.1 }

        if let sec = query["security"] {
            switch sec {
            case "reality": cfg.security = .reality
            case "tls", "none": cfg.security = SecurityMode(rawValue: sec) ?? .tls
            default: break
            }
        }
        if let sni = query["sni"] { cfg.sni = sni }
        if let net = query["type"] { cfg.network = TransportType(rawValue: net) ?? .tcp }
        if let path = query["path"] { cfg.path = path }
        if let flow = query["flow"] { cfg.flow = flow }
        if let pk = query["pbk"] { cfg.publicKey = pk }
        if let sid = query["sid"] { cfg.shortId = sid }
        if let fp = query["fp"] { cfg.fingerprint = fp }
        if let name = query["remarks"] {
            cfg.name = (name as NSString).removingPercentEncoding ?? name
        } else {
            cfg.name = "VLESS-\(url.host ?? "?")"
        }
        return cfg
    }

    // MARK: - vmess://

    private static func parseVMess(_ link: String, _ url: URL) -> ServerConfig? {
        let base = link.components(separatedBy: "://").last ?? ""
        guard let data = Data(base64Encoded: base),
              let obj = try? JSONSerialization.jsonObject(with: data) else {
            return parseVMessJSON(objPlaceholder)
        }
        return parseVMessJSON(obj)
    }

    private static let objPlaceholder: [String: Any] = [:]

    private static func parseVMessJSON(_ obj: Any?) -> ServerConfig? {
        guard let dict = obj as? [String: Any] else { return nil }
        let address = (dict["add"] as? String) ?? ""
        let port = (dict["port"] as? String).flatMap { Int($0) } ?? (dict["port"] as? Int) ?? 443
        let id = (dict["id"] as? String) ?? ""
        let net = (dict["net"] as? String).flatMap(TransportType.init(rawValue:)) ?? .tcp
        let type = (dict["type"] as? String) ?? "none"
        let security = (dict["security"] as? String) ?? "none"
        var cfg = ServerConfig(
            name: "VMESS-\(address)",
            protocol: .vmess,
            address: address,
            port: port,
            uuid: id,
            security: SecurityMode(rawValue: security) ?? .none
        )
        cfg.network = net
        if let path = dict["path"] as? String { cfg.path = path }
        if let host = dict["host"] as? String { cfg.sni = host }
        if let remarks = dict["ps"] as? String {
            cfg.name = remarks.isEmpty ? cfg.name : remarks
        }
        _ = type
        return cfg
    }

    // MARK: - trojan://

    private static func parseTrojan(_ link: String, _ url: URL) -> ServerConfig? {
        guard let components = URLComponents(string: link) else { return nil }
        var cfg = ServerConfig(
            name: "Trojan-\(url.host ?? "?")",
            protocol: .trojan,
            address: url.host ?? "",
            port: url.port ?? 443,
            uuid: url.user ?? "",
            security: .tls
        )
        cfg.sni = url.host ?? ""
        let query = (components.query?.split(separator: "&").compactMap {
            let kv = $0.split(separator: ":", maxSplits: 1)
            guard kv.count == 2 else { return nil }
            return (String(kv[0]), String(kv[1]))
        } ?? []).reduce(into: [String: String]()) { $0[String($1.0)] = $1.1 }
        if let sni = query["sni"] { cfg.sni = sni }
        if let name = query["remarks"] {
            cfg.name = (name as NSString).removingPercentEncoding ?? name
        }
        return cfg
    }

    // MARK: - ss://

    private static func parseSS(_ link: String, _ url: URL) -> ServerConfig? {
        let base = link.components(separatedBy: "://").last ?? ""
        guard let data = Data(base64Encoded: base.removingPercentEncoding ?? base) else {
            return nil
        }
        let token = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // user:method:password
        let parts = token.split(separator: "@").compactMap { $0 }
        guard let right = parts.last else { return nil }
        let userParts = right.split(separator: ":" , maxSplits: 2)
        guard userParts.count == 3 else { return nil }
        var cfg = ServerConfig(
            name: "SS-\(url.host ?? "?")",
            protocol: .shadowsocks,
            address: url.host ?? "",
            port: url.port ?? 8388,
            uuid: String(userParts[2]),
            security: .none
        )
        let method = String(userParts[1])
        _ = method
        if let q = URLComponents(string: link)?.query,
           let remark = q.split(separator: "&").compactMap({
                let kv = $0.split(separator: "=", maxSplits: 1)
                guard kv.count == 2, kv[0] == "remarks" else { return nil }
                return String(kv[1])
            }).first {
            cfg.name = (remark as NSString).removingPercentEncoding ?? remark
        }
        return cfg
    }
}
