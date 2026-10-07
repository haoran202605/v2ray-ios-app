import Foundation

// MARK: - Protocol Types

enum ProxyProtocol: String, Codable, CaseIterable, Identifiable {
    case vless
    case vmess
    case trojan
    case shadowsocks

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .vless: return "VLESS"
        case .vmess: return "VMESS"
        case .trojan: return "Trojan"
        case .shadowsocks: return "Shadowsocks"
        }
    }
}

enum SecurityMode: String, Codable, CaseIterable {
    case tls
    case reality
    case none
}

enum TransportType: String, Codable, CaseIterable {
    case tcp
    case kcp
    case websocket
}

// MARK: - Server Config

struct ServerConfig: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var proto: ProxyProtocol
    var address: String
    var port: Int
    var uuid: String
    var security: SecurityMode = .tls
    var sni: String = ""
    var network: TransportType = .tcp
    var path: String = ""
    var flow: String = ""
    var publicKey: String = ""
    var shortId: String = ""
    var fingerprint: String = "chrome"

    func summary() -> String {
        "\(proto.rawValue.uppercased()) · \(name) · \(address):\(port)"
    }
}
