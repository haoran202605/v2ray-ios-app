import SwiftUI

struct ConnectPanel: View {
    @EnvironmentObject var vm: MainViewModel

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(vm.selectedServer?.name ?? "未选择服务器")
                        .font(.headline)
                    Text(vm.statusMessage.isEmpty ? (vm.isConnected ? "已连接" : "未连接") : vm.statusMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: statusIcon)
                    .font(.largeTitle)
                    .foregroundColor(statusColor)
            }

            Button {
                vm.isConnected ? vm.disconnect() : vm.connect()
            } label: {
                HStack {
                    Image(systemName: vm.isConnected ? "power" : "bolt.fill")
                    Text(vm.isConnected ? "断开连接" : "连接")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(vm.isConnected ? .red.opacity(0.15) : .blue.opacity(0.15))
                .foregroundColor(vm.isConnected ? .red : .blue)
                .cornerRadius(10)
            }
            .disabled(vm.isConnecting || vm.selectedServer == nil)

            if vm.isConnecting {
                ProgressView()
                    .padding(.top, 4)
            }
        }
        .padding()
    }

    private var statusIcon: String {
        switch (vm.isConnected, vm.isConnecting) {
        case (true, _): return "wifi"
        case (_, true): return "wifi.exclamationmark"
        case (false, false): return "wifi.slash"
        }
    }

    private var statusColor: Color {
        switch (vm.isConnected, vm.isConnecting) {
        case (true, _): return .green
        case (_, true): return .yellow
        case (false, false): return .gray
        }
    }
}
