# 原生 Swift tvOS 客户端（ios-native）

红果TV 的原生 SwiftUI + AVKit 客户端，替代原 React Native(tvos) 实现。服务端 Node（`server/`，端口 8787）**保持不变**。

## 架构

- **纯 SwiftUI**，无 CocoaPods / 无第三方依赖；部署目标 **tvOS 17.0**。
- 页面：推荐（Infuse 风格海报墙）/ 搜索 / 收藏 / 最近观看 / 设置 / 详情 / 播放器。
- 播放器：`AVPlayerViewController`（经 `UIViewControllerRepresentable` 包装），支持续播 seek、周期保存进度、看完归零。
- **鉴权流**：tvOS 的 AVPlayer 不支持 `AVURLAssetHTTPHeaderFieldsKey`，采用自定义 scheme 方案：
  `AuthURLProtocol` 把 `http://` 换为 `authstream://`，转发请求时注入 `Authorization: Bearer <token>`（token 经 UserDefaults 桥接，见 `LocalStore.syncTokenToUserDefaults`）。
- 本地状态（服务地址/口令/收藏/进度）JSON 持久化到 `Documents/hongguotv-state.json`。

## 目录

```
ios-native/
├── project.yml                     # xcodegen 工程描述（工程生成源）
├── HongguoTV.xcodeproj             # xcodegen 生成（勿手改，改 project.yml 后重新生成）
├── bin/xcodegen                    # XcodeGen 2.44.0 二进制（brew 在 macOS 26.5 不可用时的离线工具）
└── HongguoTV/
    ├── HongguoTVApp.swift          # @main，注册 AuthURLProtocol
    ├── Models.swift                # Codable 契约（与服务端 src/domain/model.ts 对应）
    ├── APIClient.swift             # health/home/search/detail/play
    ├── LocalStore.swift            # 设置/收藏/进度持久化
    ├── Theme.swift                 # 主题色、FocusCard 聚焦放大、玻璃面板、海报组件
    ├── ContentView.swift           # TabBar：推荐/搜索/收藏/最近观看/设置
    ├── HomeView.swift / SearchView.swift / LibraryView.swift
    ├── DetailView.swift            # 背景毛玻璃 + 信息区 + 选集 + NativePlayer
    ├── PlayerView.swift            # AVPlayerViewController 包装 + 测试播放器
    ├── SettingsView.swift          # 服务地址/口令/连接校验/测试播放
    ├── AuthURLProtocol.swift       # 鉴权流 URLProtocol
    └── Info.plist                  # ATS 允许内网 HTTP、横屏、arm64
```

## 构建与运行

```bash
# 重新生成工程（改过 project.yml 或增删源文件后执行）
cd ios-native && ./bin/xcodegen generate --spec project.yml

# Release 构建（模拟器）
xcodebuild -project ios-native/HongguoTV.xcodeproj -scheme HongguoTV \
  -configuration Release -sdk appletvsimulator \
  -destination 'generic/platform=tvOS Simulator' \
  -derivedDataPath build/native build CODE_SIGNING_ALLOWED=NO

# 安装到已启动的 Apple TV 模拟器并启动
xcrun simctl install booted build/native/Build/Products/Release-appletvsimulator/HongguoTV.app
xcrun simctl launch booted com.hongguotv.tvos
```

默认服务地址 `http://localhost:8787`（模拟器与 Mac 共享网络栈，直连本机服务端）。

## 已验证（2026-10-13）

- Release（appletvsimulator）构建通过。
- 首页真实数据加载、Tab 切换、分页滚动。
- 详情页 + 播放链路：play 接口 → authstream 鉴权流 → AVPlayer 出画面、进度推进、内置字幕正常。
- 产物：`outputs/hongguotv-native-0.2.0-tvos.app.tar.gz`（SHA256 见 outputs/SHA256SUMS 或提交说明）。

## 备注

- 手写 pbxproj 曾出现 Xcode 26 只编译前 9 个源文件的问题，改用 xcodegen 生成标准工程后解决；**请勿再手改 pbxproj**。
- 真机 Apple TV 验证与签名（Team）尚未配置；连真机需在 Xcode 里选 Team 并把 bundle id 改为自有账号。
