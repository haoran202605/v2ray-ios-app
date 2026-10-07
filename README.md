# V2Ray iOS Client（纯 App 版）

**无 VPN 扩展、无付费 entitlement**，免费 Apple ID 即可签名到真机。

App 在内部监听 `127.0.0.1:1080`（HTTP）/ `10808`（SOCKS），用内置的 sing-box 处理 VLESS / VMESS / Trojan / SS 协议。你只需要让浏览器或其他支持 SOCKS 的 App 把代理指向 `127.0.0.1:1080` 即可。

## 架构

```
V2rayiOS App (SwiftUI)
 ├─ ServerList / AddServer / Connect / Settings 界面
 ├─ ConfigStore        持久化（App Group 共享容器）
 ├─ LinkParser         解析 vless/vmess/trojan/ss 链接
 ├─ ProxyConfigGen     生成 sing-box JSON 配置
 └─ SingBoxService     在 App 内启动 sing-box 监听本地端口
```

## 前置

- Mac + Xcode 15+
- 免费 Apple ID（Developer > Certificates，免费签 7 天）
- iPhone（iOS 15+）
- sing-box 二进制：从 [sing-box releases](https://github.com/SagerNet/sing-box/releases) 下载 iOS 版（若官方无 iOS 构建，可用社区预编译包或从源码交叉编译）

## 快速开始（Mac 上操作）

```bash
# 1. 安装 xcodegen
brew install xcodegen

# 2. 生成 Xcode 工程
cd v2ray-ios-app
xcodegen generate
open V2rayiOS.xcodeproj
```

在 Xcode 里：
1. **把 Bundle ID 前缀改成你的**
   - 编辑 `project.yml`：`bundleIdPrefix: com.yourname` → `com.<你的前缀>`
   - 重新 `xcodegen generate`
2. **签名**：选当前连接的 iPhone 设备 → Signing & Capabilities → 勾 "Automatically manage signing" → Team 选你的（免费）
3. **添加 sing-box 二进制**
   - 把 `sing-box` 拖进主 App target 的 "Copy Bundle Resources"
   - 在 `SingBoxService.startProxy()` 里把 TODO 替换成 `posix_spawn` 或 `Process` 启动该二进制
4. **选真机 → Run**
   - 首次运行，iPhone 上会提示信任开发者描述文件，去 设置 > 通用 > 设备管理 > 信任

## 使用

1. 打开 App，点右下角 + 添加服务器（粘贴 `vless://` 链接或手动填）
2. 点"连接"
3. Safari 或支持 SOCKS 的 App 把代理指向 `127.0.0.1:1080`
   - Safari：设置 > Safari > 自动代理 → 填 `socks://127.0.0.1:10808`

## 目录结构

```
v2ray-ios-app/
├── project.yml
├── V2rayiOS/
│   ├── V2rayiOSApp.swift
│   ├── Info.plist
│   ├── V2rayiOS.entitlements
│   ├── Models/
│   │   ├── ServerConfig.swift
│   │   ├── AppSettings.swift
│   │   └── ConfigStore.swift
│   ├── Services/
│   │   ├── LinkParser.swift
│   │   ├── ProxyConfigGenerator.swift
│   │   └── SingBoxService.swift
│   ├── ViewModels/
│   │   └── MainViewModel.swift
│   └── Views/
│       ├── ContentView.swift
│       ├── ConnectPanel.swift
│       ├── ServerListPanel.swift
│       ├── AddServerView.swift
│       └── SettingsView.swift
└── README.md
```

## 支持协议

| 协议 | 说明 | 链接格式 |
|------|------|----------|
| VLESS | 支持 TLS / REALITY | `vless://uuid@host:port?...` |
| VMESS | 支持 TLS | `vmess://base64(json)` |
| Trojan | 支持 TLS | `trojan://pass@host:port?...` |
| Shadowsocks | SS 加密 | `ss://base64(method:pass@host:port)` |

## 限制

- **没有系统级 VPN**：iOS 不允许 App 在沙盒外运行 sing-box，所以 App 内能起本地代理但不能做系统流量劫持
- **免费签名 7 天过期**：需要每 7 天重新签一次（Xcode 点 Run 即可）
- 要长期跑 / 提 App Store：需要付费开发者账号 + VPN 扩展 entitlement
