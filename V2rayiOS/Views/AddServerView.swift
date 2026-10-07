import SwiftUI

struct AddServerView: View {
    @EnvironmentObject var vm: MainViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var address = ""
    @State private var portStr = "443"
    @State private var uuid = ""
    @State private var protocolType: ProxyProtocol = .vless
    @State private var security: SecurityMode = .tls
    @State private var sni = ""
    @State private var network: TransportType = .tcp
    @State private var path = ""
    @State private var flow = ""
    @State private var publicKey = ""
    @State private var shortId = ""
    @State private var fingerprint = "chrome"
    @State private var link = ""

    @State private var useLinkMode = false

    var body: some View {
        NavigationStack {
            Form {
                modeSection
                if useLinkMode {
                    importSection
                } else {
                    basicSection
                    protocolSection
                    networkSection
                    if security == .reality {
                        realitySection
                    }
                }
            }
            .navigationTitle(useLinkMode ? "导入链接" : "添加服务器")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if useLinkMode {
                        Button("导入") {
                            let imported = vm.importLinks([link])
                            if imported > 0 { dismiss() }
                        }
                        .disabled(link.isEmpty)
                    } else {
                        Button("添加") {
                            saveManual()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Sections (split into computed props to avoid type-check timeout)

    @ViewBuilder
    private var modeSection: some View {
        Section {
            Toggle("粘贴链接模式", isOn: $useLinkMode)
        }
    }

    @ViewBuilder
    private var importSection: some View {
        Section {
            TextField("vless://vmess://trojan://ss:// 链接", text: $link, axis: .vertical)
                .font(.system(.caption))
            if !link.isEmpty {
                Button {
                    let imported = vm.importLinks([link])
                    if imported > 0 {
                        dismiss()
                    }
                } label: {
                    Label("导入", systemImage: "arrow.down.circle")
                }
            }
        } header: {
            Text("导入链接")
        }
    }

    @ViewBuilder
    private var basicSection: some View {
        Section {
            TextField("名称", text: $name)
            TextField("地址", text: $address)
                .keyboardType(.asciiCapable)
            TextField("端口", text: $portStr)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
        } header: {
            Text("基本信息")
        }
    }

    @ViewBuilder
    private var protocolSection: some View {
        Section {
            Picker("协议", selection: $protocolType) {
                ForEach(ProxyProtocol.allCases, id: \.self) { p in
                    Text(p.displayName).tag(p)
                }
            }
            TextField("UUID", text: $uuid)
            Picker("安全", selection: $security) {
                ForEach(SecurityMode.allCases, id: \.self) { s in
                    Text(s.rawValue).tag(s)
                }
            }
        } header: {
            Text("协议")
        }
    }

    @ViewBuilder
    private var networkSection: some View {
        Section {
            Picker("传输", selection: $network) {
                ForEach(TransportType.allCases, id: \.self) { n in
                    Text(n.rawValue).tag(n)
                }
            }
            TextField("SNI / Host", text: $sni)
            TextField("路径 (ws)", text: $path)
        } header: {
            Text("网络")
        }
    }

    @ViewBuilder
    private var realitySection: some View {
        Section {
            TextField("公钥 (pbk)", text: $publicKey)
            TextField("短ID (sid)", text: $shortId)
            TextField("指纹 (fp)", text: $fingerprint)
            TextField("流量 (flow)", text: $flow)
        } header: {
            Text("REALITY")
        }
    }

    // MARK: - Actions

    private func saveManual() {
        guard !uuid.isEmpty, !address.isEmpty else { return }
        let config = ServerConfig(
            name: name.isEmpty ? "VLESS-\(address)" : name,
            proto: protocolType,
            address: address,
            port: Int(portStr) ?? 443,
            uuid: uuid,
            security: security,
            sni: sni.isEmpty ? address : sni,
            network: network,
            path: path,
            flow: flow,
            publicKey: publicKey,
            shortId: shortId,
            fingerprint: fingerprint
        )
        vm.addServer(config)
        dismiss()
    }
}
