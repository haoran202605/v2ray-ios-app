import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var vm: MainViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var importText = ""
    @State private var importResult: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("系统代理", isOn: .constant(false))
                        .disabled(true)
                    Text("本应用使用系统级 VPN 模式，无需系统代理")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section("导入服务器") {
                    TextField("粘贴 vless:// vmess:// trojan:// ss:// 链接",
                              text: $importText, axis: .vertical)
                        .font(.system(.caption))
                    if let r = importResult {
                        Text(r)
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    Button("导入") {
                        let lines = importText.components(separatedBy: .newlines)
                        let n = vm.importLinks(lines)
                        importResult = "成功导入 \(n) 个服务器"
                        importText = ""
                    }
                    .disabled(importText.isEmpty)
                }

                Section("关于") {
                    LabeledContent("版本", value: "1.0")
                    LabeledContent("内核", value: "sing-box")
                    LabeledContent("协议", value: "VLESS / VMESS / Trojan / SS")
                }
            }
            .navigationTitle("设置")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
