import SwiftUI

struct ServerListPanel: View {
    @EnvironmentObject var vm: MainViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("服务器 (\(vm.servers.count))")
                    .font(.headline)
                Spacer()
                Button {
                    vm.showAddServer = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                }
            }
            .padding([.horizontal, .top])

            if vm.servers.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "network")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("还没有服务器")
                        .font(.headline)
                    Text("点击右上角 + 添加，或在设置中导入链接")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(vm.servers) { server in
                        ServerRow(server: server)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                vm.select(server)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    vm.removeServer(server)
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }
}

struct ServerRow: View {
    @EnvironmentObject var vm: MainViewModel
    let server: ServerConfig

    private var isSelected: Bool {
        vm.selectedServer?.id == server.id
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(server.name)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Text(server.protocol.displayName)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.15))
                        .foregroundColor(.blue)
                        .cornerRadius(4)
                }
                Text("\(server.address):\(server.port)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
        }
        .padding(.vertical, 4)
        .background(isSelected ? Color.blue.opacity(0.1) : .clear)
        .cornerRadius(8)
    }
}
