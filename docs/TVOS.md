# Apple TV（tvOS）构建与安装

更新日期：2026-10-12。状态：**Release 与 Debug 产物均已在 tvOS 模拟器验证运行**（Release 已实际播放短剧、Debug 经 Metro 加载 bundle）；真机安装与遥控器行为尚未验收。

## 结论

本仓库的 React Native TV 工程（`react-native-tvos 0.81.5-2`）原生支持 Apple TV。`ios/` 下的 Xcode 工程本身就是 tvOS 工程（`SDKROOT=appletvos`、`TVOS_DEPLOYMENT_TARGET 15.1`），业务代码无平台分支，可直接编译出 tvOS 产物。

与 Android 版（Kotlin APK 可自由侧载）不同，**tvOS 没有自由侧载通道**：应用装到 Apple TV 只能走 Xcode 直装开发设备、TestFlight 或 App Store，均要求**付费 Apple Developer Program（$99/年）**；免费账号不支持 tvOS 设备部署。

## 已确认的依赖支持

| 依赖 | 版本 | tvOS 支持 |
| --- | --- | --- |
| react-native | react-native-tvos 0.81.5-2 | Android TV / Apple TV 双平台 |
| react-native-video | 6.19.3 | podspec 声明 `tvos => 13.0`（AVPlayer 后端） |
| @react-native-async-storage/async-storage | 2.2.0 | podspec 声明 `tvos => 11.0` |

## 构建前置条件

- macOS + Xcode（含 tvOS SDK）。本机验证：Xcode 26.5、tvOS 26.5 SDK。
- Node.js ≥ 22（RN 打包脚本需要）。
- CocoaPods。若不在 PATH（如 `/opt/homebrew/bin/pod`），可用 `POD_BIN=/opt/homebrew/bin/pod` 指定。

## 构建步骤

```sh
# 1. 安装 JS 依赖
npm ci

# 2. 生成原生工程（需要 CocoaPods；Release 构建请按下方「Hermes 引擎包下载失败的对策」选用 **release** 版 Hermes 包）
(cd ios && pod install)

# 3. 构建
./scripts/build-tvos.sh            # 默认 tvOS 模拟器 Release，免签名，用于编译验证
./scripts/build-tvos.sh device     # tvOS 真机 Release；不设 DEVELOPMENT_TEAM 时产出未签名 .app
DEVELOPMENT_TEAM=ABCDE12345 ./scripts/build-tvos.sh device   # 指定 Team 时自动签名
```

产物：`outputs/hongguotv-<版本>-tvos.app`，同目录更新 `SHA256SUMS`。

### pod 下载走代理

CocoaPods 下载依赖时使用系统代理环境变量。本机 Clash Verge 混合端口为 `127.0.0.1:7897`：

```sh
export http_proxy=http://127.0.0.1:7897 https_proxy=http://127.0.0.1:7897
(cd ios && pod install)
```

### Hermes 引擎包下载失败的对策（关键：Debug / Release 包必须区分）

`pod install` 会从 Maven 中央仓库下载 Hermes 预编译包（约 21–29MB），国内网络可能缓慢或中断（报错形如 `curl: (18) Transferred a partial file`），可用本地压缩包完全绕开外网：

```sh
HERMES_ENGINE_TARBALL_PATH=/绝对路径/hermes-ios-0.81.5-release.tar.gz (cd ios && pod install)
```

**⚠️ 必须按构建配置选对包**，RN 的两个预编译包内部 ABI 不同：

| 包 | Hermes 是否带 JS 调试器（`debugJavaScript` 符号） | 对应构建配置 |
| --- | --- | --- |
| `hermes-ios-0.81.5-debug.tar.gz` | 带 | **Debug**（RN 的 `React-RuntimeHermes` 在 Debug 配置编译时定义了 `HERMES_ENABLE_DEBUGGER=1`，vtable 与它一致） |
| `hermes-ios-0.81.5-release.tar.gz` | 不带 | **Release**（Release 配置未定义该宏，vtable 不含调试器槽位） |

**用错包的症状**：Release 构建把 Debug 包链接进去后，应用**启动即崩溃**（SIGSEGV / `HermesRuntimeImpl::debugJavaScript` 处读取空 `sourceURL`，地址 0x17）。原因：RN 侧按 Release 语义编译出的 vtable 里 `registerForProfiling` 槽位，在带调试器的框架 vtable 中对应 `debugJavaScript`，虚调用错位导致参数为空。详情见下文「已知问题与修复记录」。

本机已缓存两个副本：`ios/Pods/hermes-engine-artifacts/hermes-ios-0.81.5-{debug,release}.tar.gz`。

**不用再手工挑包了**：`ios/Podfile` 的 `post_install` 给 `hermes-engine` 聚合 target 挂了一个脚本构建阶段 `[Hermes] Swap framework per configuration`，每次构建按配置自动检测并换包（见下方「已知问题与修复记录」第 3 节）。`scripts/build-tvos.sh` 的 Release 前置检查仅作信息提示（用 `nm` 检查 `CDPHandler` 符号），不再阻断。

另外两个补充说明：
- 镜像仓库：`ENTERPRISE_REPOSITORY` 环境变量可指定同结构的 Maven 镜像基地址。
- 切换包后如 `pod install` 不重新解压，先删除 `ios/Pods/hermes-engine` 再重跑；若改过 fmt 版本后报冲突，还需删除 `ios/Podfile.lock` 与 `ios/Pods/Local Podspecs/RCT-Folly.podspec.json`（见下文 fmt 补丁）。

## 已知问题与修复记录（2026-10-12）

### 1. fmt 11.0.2 与 Xcode 26（clang 19）不兼容 → 升到 11.1.4

首次 Release 构建永久失败在 `fmt` pod：`call to consteval function 'fmt::basic_format_string...' is not a constant expression`。修复：

- `node_modules/react-native/third-party-podspecs/fmt.podspec`：版本 `11.0.2` → `11.1.4`（该 tag 存在）。
- `node_modules/react-native/third-party-podspecs/RCT-Folly.podspec`：`spec.dependency "fmt", "11.0.2"` → `"11.1.4"`（它精确 pin，只改 fmt podspec 会解析冲突）。
- 重装：删除 `ios/Podfile.lock` 与 `ios/Pods/Local Podspecs/RCT-Folly.podspec.json` 后 `pod install`（否则 CocoaPods 缓存仍取 11.0.2）。

⚠️ 这两个文件在 `node_modules` 内，**`npm ci` 重装依赖后会丢失**，需按此步骤重新应用。

### 2. Release 启动崩溃：Hermes 预编译包用错（Debug 包用于 Release）→ 已修复

- 现象：Release 模拟器产物安装后启动即崩（两次），崩溃点在 `HermesRuntimeImpl::debugJavaScript + 120`（`ldrb w9, [x2, #0x17]` 读取空 `sourceURL`）。
- 排查过程（供参考）：Debug 配置 + Metro 运行正常 → 崩溃为 Release 特有；反汇编与 `nm` 对比确认——`HermesRuntimeImpl` 的 vtable 中 `debugJavaScript` 槽位只在 `HERMES_ENABLE_DEBUGGER` 开启时存在，而 RN 侧 `React-RuntimeHermes` 仅 **Debug** 配置定义该宏（见 `ios/Pods/Pods.xcodeproj`），Release 编译出的 vtable 视图把 `registerForProfiling` 排到 `debugJavaScript` 的位置，虚调用错位。
- 根因：此前为绕开网络，`pod install` 用 `HERMES_ENGINE_TARBALL_PATH` 指向了 **debug 包**，Release 构建因此链接了带调试器的 Hermes。
- 修复：改用 `hermes-ios-0.81.5-release.tar.gz` 重装 Pods → Release 模拟器构建后**启动正常**（进程存活、UI 完整渲染，见下方验证记录）。

### 3. Xcode Debug 构建链接失败（`CDPHandler::registerCallbacks` undefined）→ 已机制化修复

- 现象：Xcode（或命令行）Debug 配置构建报 `Undefined symbol: facebook::hermes::inspector_modern::chrome::CDPHandler::registerCallbacks(...)`，另有 `CDPAgent` / `CDPDebugAPI` / `State` / `Debugger::captureStackTrace` 等 20+ 个调试器符号缺失（完整清单见 `/tmp/tvdebug2.log`）。
- 根因：与第 2 节同一问题的镜像。RN 侧 `React-hermes` / `React-RuntimeHermes` 在 **Debug** 配置编译时开启 `HERMES_ENABLE_DEBUGGER` 并引用 Hermes 调试器符号；而本地 Pods 里装的是 **release 版** Hermes 框架（不含这些符号）→ 链接失败。`nm` 核验：release 框架 `CDPHandler`=0 处，debug 框架=477 处；`strings` 读不到符号表（Mach-O `__LINKEDIT`），必须用 `nm`。
- 修复（机制化，一劳永逸）：`ios/Podfile` 的 `post_install` 中为 `hermes-engine` 聚合 target 注入脚本构建阶段 `[Hermes] Swap framework per configuration`：
  1. 用 `GCC_PREPROCESSOR_DEFINITIONS` 是否含 `DEBUG=1` 判断当前构建配置；
  2. 用 `nm <框架二进制> | grep -c CDPHandler` 探测当前框架是否带调试器；
  3. 不匹配则从 `$PODS_ROOT/hermes-engine-artifacts/hermes-ios-<版本>-{debug,release}.tar.gz` 解包覆盖 `$PODS_ROOT/hermes-engine/destroot/.../hermes.xcframework`；
  4. **无条件刷新链接器副本**：`[CP] Copy XCFrameworks` 阶段（脚本阶段按字母序排在 `[Hermes]` 之前，CocoaPods 保存工程时会重排、`move` 无效）先于换包把旧框架 rsync 到 `$PODS_XCFRAMEWORKS_BUILD_DIR/hermes-engine/Pre-built`，所以换包阶段必须用**与 [CP] 相同的 `$PODS_XCFRAMEWORKS_BUILD_DIR` 路径**直接 `rsync --delete` 覆盖该副本（按 `$PLATFORM_NAME` 选 slice：`appletvsimulator`→`tvos-arm64_x86_64-simulator`、`appletvos`→`tvos-arm64`），结果与阶段顺序无关。
- 验证：Debug 构建成功 → 模拟器运行正常（需 Metro）；随后反向回归 Release（构建阶段自动换回 release 包）→ 模拟器运行正常并实际播放视频。

### 4. 其他

- RNCAsyncStorage 的 `TVOS_DEPLOYMENT_TARGET=11.0` 低于 tvOS SDK 下限 12.0 → 仅警告，不影响构建（本工程目标 15.1）。

## 验证记录（2026-10-12，Release / tvOS 模拟器）

- 构建：`scripts/build-tvos.sh simulator` → `** BUILD SUCCEEDED **`。
- 产物：`outputs/hongguotv-0.1.1-tvos.app`（约 35MB，lipo 显示 x86_64/arm64 双切片）+ `outputs/hongguotv-0.1.1-tvos.app.tar.gz` + `outputs/SHA256SUMS`。
- Info.plist 核验：`CFBundleIdentifier=com.hongguotv.tvos`、`CFBundleDisplayName=红果 TV`、`CFBundleShortVersionString=0.1.1`、`MinimumOSVersion=15.1`；`main.jsbundle` 已内嵌（Release 不依赖 Metro）。
- 运行：模拟器（Apple TV 4K 3rd gen，UDID `362C3320-CC4A-47D4-8E66-2601C176710F`）`simctl install` + `launch` 成功，进程持续存活。
- 端到端：内容服务在线时，Release 应用**实际播放短剧**（「重回婚闹那天，我救下了嫂子」第 1 集/共 60 集，字幕与播放控制完整渲染），证明 Hermes 换包后 Release 运行时链路（React Native 初始化 → Hermes → react-native-video → 服务代理播放）全部正常。
- Debug 链路：命令行 Debug 构建成功（此前 `CDPHandler` undefined 已修复），模拟器运行正常（Metro 在线加载 bundle，设置页完整渲染）。
- 已知限制：Release 应用「连接并保存 / 测试播放器」依赖内容服务（node bridge 8787 端口），本机服务未运行时功能不可用属预期；未覆盖真机。

## 真机签名与安装

1. 需要付费 Apple Developer Program 账号（免费账号无法向 Apple TV 设备部署）。
2. Xcode 打开 `ios/HongguoTV.xcworkspace`，选择 Team 后 Product → Run 到已连接的 Apple TV，或 Archive 后用 TestFlight 分发（内测 100 台/年）。
3. Bundle ID 为 `com.hongguotv.tvos`（已在工程中配置，与 Android 的 `com.hongguotv` / `com.hongguotv.nativeapp` 区分）。
4. 应用内容来自非官方红果接口且播放版权短剧：**App Store 公开上架基本无法过审**，本构建面向个人设备自用（Xcode/TestFlight 通道）。

## 运行要求

- Apple TV 与内容服务（Node bridge，默认端口 8787）须在同一家庭网络；在应用「设置」中填写服务器局域网地址。
- 视频流量经内容服务代理转发，服务设备需保持在线。

## 尚未验收

- **Apple TV 真机**：模拟器运行正常 ≠ 真机通过。需付费开发者账号 + 真机后验证 AVPlayer 媒体兼容（Range/请求头、码流格式）、遥控器焦点/方向键/播放键、长连播与断点续播。
- 长连播/断点续播与搜索链路在真机/长期运行下的稳定性；服务在线时推荐/搜索完整链路的逐项验收（本次已验证单集播放）。

## 构建脚本说明

`scripts/build-tvos.sh`：

- `simulator`（默认）：`-sdk appletvsimulator` Release 构建，无需签名，用于编译验证与 CI。
- `device`：`-sdk appletvos` 构建；未提供 `DEVELOPMENT_TEAM` 时以 `CODE_SIGNING_ALLOWED=NO` 产出未签名 .app，之后可在 Xcode 中补签名；提供 `DEVELOPMENT_TEAM` 时自动签名。
- 前置检查：node、node_modules、Podfile.lock、xcworkspace；缺失时给出明确提示。
- 版本号取自 `package.json`（0.1.1），与工程 `MARKETING_VERSION` 一致。

## Web 调试器（不编译原生 App 的调试方式）

工程 UI 是 React Native（tvOS 专用组件），**无法直接"网页打开"**；但数据层（`src/domain/`、`src/data/provider.ts`、`src/data/useCatalog.ts`）是纯 TypeScript，无 RN 依赖，可直接在浏览器复用。

`web-debug/` 是一个独立 Vite + React + TS 调试器，复用上述数据层，浏览器里连内容服务调试接口/数据链路：

```sh
cd web-debug
npm install        # 网络差时先 export 代理变量
npm run dev        # 开发模式，默认 http://localhost:5173（被占用自动 +1）
npm run build      # 产物在 web-debug/dist
```

用法：打开页面 → 填服务地址（默认 `http://localhost:8787`）→「连接」→ 推荐网格（键盘方向键 + Enter 模拟焦点）→ 详情 → 选集播放（HTML5 `<video>`；带访问口令时走 fetch→Blob，因为 `<video>` 无法携带自定义请求头）。

局限（调试用途，非产品）：UI 与 tvOS 版视觉/焦点行为不完全一致；`storage.ts`（AsyncStorage）不迁移，收藏/最近观看为内存态。

## 已知问题与修复记录（续）

- **tvOS 遥控器 Menu 键返回失效**：react-native-tvos 默认关闭 Menu 键手势（`RCTTVRemoteHandler.__useMenuKey = NO`），须在应用启动时调用 `TVEventControl.enableTVMenuKey()`，Menu 键才会进入 `BackHandler`（`BackHandler.ios.js` 监听 `eventType === 'menu'`）。已在 `App.tsx` 挂载时启用，播放器/详情/网格返回均生效。
- **服务地址默认值**：设置页服务地址默认预填 `http://localhost:8787`（无存档时 `settings.baseUrl` 同样回落到该默认值）；模拟器上 localhost 指模拟器自身，真机 Apple TV 上需改为服务机局域网地址。
