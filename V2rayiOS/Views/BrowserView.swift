import SwiftUI
import WebKit

struct BrowserView: View {
    @EnvironmentObject var vm: MainViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var coordinator = BrowserCoordinator()
    @State private var address = "https://www.google.com"

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TextField("https://", text: $address)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    .onSubmit(go)
                Button("Go", action: go)
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: 80)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            if let server = vm.selectedServer {
                HStack(spacing: 4) {
                    Image(systemName: vm.isConnected ? "arrow.triangle.branch" : "arrow.triangle.branch.circle")
                        .foregroundStyle(vm.isConnected ? .green : .secondary)
                    Text(vm.isConnected ? "代理：\(server.name)" : "未连接：\(server.name)")
                        .font(.caption)
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
            }

            BrowserWebView(session: coordinator)
                .ignoresSafeArea(edges: .bottom)
        }
        .onAppear {
            coordinator.load("https://www.google.com")
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("关闭") { dismiss() }
            }
        }
    }

    private func go() {
        let url = address.hasPrefix("http") ? address : "https://\(address)"
        coordinator.load(url)
    }
}

final class BrowserCoordinator: NSObject, ObservableObject, WKNavigationDelegate {
    let webView: WKWebView

    override init() {
        let config = WKWebViewConfiguration()
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.navigationDelegate = self
    }

    func load(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        webView.load(URLRequest(url: url))
    }
}

struct BrowserWebView: UIViewRepresentable {
    let session: BrowserCoordinator

    func makeUIView(context: Context) -> WKWebView {
        session.webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) { }
}
