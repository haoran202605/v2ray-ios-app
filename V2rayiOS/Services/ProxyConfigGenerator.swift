import Foundation

/// Generates sing-box JSON config from a V2Ray-style server definition.
/// sing-box fully supports vless / vmess / trojan / shadowsocks.
enum ProxyConfigGenerator {

    /// Top-level sing-box config (tunnel-side).
    static func generate(for server: ServerConfig, appGroupContainer: URL?) -> String {
        let inbound = [
            "type": "mixed",
            "tag": "tun-in",
            "local_address": "127.0.0.1",
            "local_port": 2052,
            "inet4_family": true,
            "inet6_family": true,
            "sniff": true,
            "override_network": ["tcp", "udp"],
            "routing_options": [
                "auto_detect_interface": true
            ]
        ] as [String: Any]

        let outbound = buildOutbound(for: server)

        let config: [String: Any] = [
            "log": [
                "level": "warning",
                "output": appGroupContainer?.appendingPathComponent("singbox.log").path ?? "stdout"
            ],
            "dns": [
                "hosts": [
                    "ipset": ["geoip:cn", "geosite:private"]
                ],
                "servers": [
                    ["address": "https://1.1.1.1/dns-query"],
                    ["address": "https://8.8.8.8/dns-query"]
                ] as [Any]
            ],
            "inbounds": [inbound],
            "outbounds": [outbound],
            "experimental": [:]
        ]

        let data = try! JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted])
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private static func buildOutbound(for s: ServerConfig) -> [String: Any] {
        switch s.protocol {
        case .vless:   return vlessOutbound(s)
        case .vmess:   return vmessOutbound(s)
        case .trojan:  return trojanOutbound(s)
        case .shadowsocks: return ssOutbound(s)
        }
    }

    private static func vlessOutbound(_ s: ServerConfig) -> [String: Any] {
        var o: [String: Any] = [
            "type": "vless",
            "tag": "vless",
            "server": s.address,
            "server_port": s.port,
            "uuid": s.uuid,
            "network": s.network.rawValue
        ]

        var security: [String: Any] = [:]
        switch s.security {
        case .reality:
            o["multiplex"] = "disable"
            security = [
                "enabled": true,
                "type": "reality",
                "public_key": s.publicKey,
                "fingerprint": s.fingerprint,
                "short_id": s.shortId,
                "server_name": s.sni
            ]
        case .tls:
            security = [
                "enabled": true,
                "type": "tls",
                "server_name": s.sni,
                "fingerprint": s.fingerprint
            ]
        case .none:
            break
        }
        if !security.isEmpty { o["security"] = security }
        if !s.flow.isEmpty { o["flow"] = s.flow }
        if s.network == .websocket {
            o["ws_options"] = ["path": s.path.isEmpty ? "/" : s.path, "headers": ["Host": s.sni]]
        }
        if s.network == .kcp {
            o["kcp_options"] = ["seed": s.path, "header_type": "none"]
        }
        return o
    }

    private static func vmessOutbound(_ s: ServerConfig) -> [String: Any] {
        var o: [String: Any] = [
            "type": "vmess",
            "tag": "vmess",
            "server": s.address,
            "server_port": s.port,
            "uuid": s.uuid,
            "security": s.security.rawValue == "none" ? "auto" : "auto",
            "network": s.network.rawValue
        ]
        var security: [String: Any] = [:]
        if s.security != .none {
            security = ["enabled": true, "type": "tls", "server_name": s.sni]
            o["security"] = security
        }
        if s.network == .websocket {
            o["ws_options"] = ["path": s.path.isEmpty ? "/" : s.path, "headers": ["Host": s.sni]]
        }
        return o
    }

    private static func trojanOutbound(_ s: ServerConfig) -> [String: Any] {
        var o: [String: Any] = [
            "type": "trojan",
            "tag": "trojan",
            "server": s.address,
            "server_port": s.port,
            "uuid": s.uuid,
            "network": s.network.rawValue
        ]
        if s.security != .none {
            o["security"] = ["enabled": true, "type": "tls", "server_name": s.sni]
        }
        if s.network == .websocket {
            o["ws_options"] = ["path": s.path.isEmpty ? "/" : s.path, "headers": ["Host": s.sni]]
        }
        return o
    }

    private static func ssOutbound(_ s: ServerConfig) -> [String: Any] {
        return [
            "type": "shadowsocks",
            "tag": "ss",
            "server": s.address,
            "server_port": s.port,
            "method": "aes-256-gcm",
            "password": s.uuid
        ]
    }
}
