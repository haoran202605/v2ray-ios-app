import SwiftUI

struct ContentView: View {
    @EnvironmentObject var vm: MainViewModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ConnectPanel()
                ServerListPanel()
            }
            .navigationTitle("V2Ray iOS")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        vm.showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $vm.showAddServer) {
                AddServerView()
                    .environmentObject(vm)
            }
            .sheet(isPresented: $vm.showSettings) {
                SettingsView()
                    .environmentObject(vm)
            }
            .alert("错误", isPresented: .constant(vm.errorMessage != nil)) {
                Button("好的") { vm.errorMessage = nil }
            } message: {
                Text(vm.errorMessage ?? "")
            }
            .onAppear {
                vm.refresh()
            }
        }
    }
}
