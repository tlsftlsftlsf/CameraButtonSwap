# CameraButtonSwap - iOS 15.0 ~ 17.3.1 相机实况文本按钮左置插件

适用于 iOS 15.0 ~ 17.3.1 系统相机 App 的无根越狱（Rootless / RootHide）Tweak，专为左撇子或习惯左手单手操作的用户深度打造。

---

## 🌟 核心特性 (Features)

- **屏幕长按自由拖拽与持久化记忆 (Custom Drag & Drop)**：
  - **长按拖拽**：在相机取景框内**长按实况文本按钮 0.45 秒**（伴随物理触感微震），即可随心将按钮拖拽到任何您感觉最舒服顺手的屏幕位置！
  - **松开即存**：松开手指即刻自动持久化保存该专属坐标，下次打开相机、锁屏相机时均固定在该专属位置。
  - **双击复位**：快速**双击该按钮**或将其**拖回左下角边缘**，即可随时一键恢复到默认自适应推荐位置。
  - **手势独占保护**：拖动按钮时自动拦截底层取景器的滑动事件，不会误触发切换相机拍摄模式。
- **彻底消除递归闪退 (Zero-Crash Re-entrancy Lock)**：
  - 引入全局防重入锁 `isRelocating` 与坐标位移滤波保护，彻底解决保存自定义坐标后由于 `setFrame:` 相互触发导致的无限递归与栈溢出闪退。
- **精准保护 VisionKit 文本划词与选择系统**：
  - 仅 Hook 90x90 pt 以内的独立按钮实体，严格排除所有全屏分析画布与文本选区层（`VKCImageAnalysisBaseView` 等），彻底解决点击按钮后划词、复制文字失效的问题。
- **纯原生零外部依赖 (Zero Substrate Dependency)**：
  - 通过 Logos `internal` 生成器生成纯原生 Objective-C runtime swizzling，彻底剥离 `CydiaSubstrate.framework` 依赖，完美兼容 Dopamine 2.x/3.x 与 ElleKit。
- **原生 iOS 17.3.1 SDK 直编译与代码签名**：
  - 使用官方 `iPhoneOS17.3.1.sdk` 编译，全面匹配 iOS 17 系统符号与 Mach-O 平台标准；
  - 自动为 dylib 补全 `flags=0x2(adhoc)` 签名，彻底攻克 iOS 17 AMFI / dyld 拒绝加载无签名库的问题。
- **双越狱架构原生支持**：
  - 原生支持官方标准无根越狱（Dopamine / Palera1n - `iphoneos-arm64`）；
  - 原生支持 RootHide 越狱生态（RootHide Dopamine / Bootstrap / Serotonin - `iphoneos-arm64e`）。

---

## 📦 开箱即用（已编译好的 deb 安装包）

所有已编译好的安装包均位于本仓库 [`packages/`](packages/) 目录、桌面以及 [GitHub Releases](https://github.com/tlsftlsftlsf/CameraButtonSwap/releases)：

| 越狱类型 | 架构标识 | 安装包文件名 | 适用环境 |
| :--- | :--- | :--- | :--- |
| **标准无根 (Rootless)** | `iphoneos-arm64` | [`packages/com.yourname.camerabuttonswap_2.6.1_iphoneos-arm64.deb`](packages/com.yourname.camerabuttonswap_2.6.1_iphoneos-arm64.deb) | 官方标准 Dopamine 2.x/3.x、Palera1n |
| **RootHide 无根** | `iphoneos-arm64e` | [`packages/com.yourname.camerabuttonswap_2.6.1_iphoneos-arm64e.deb`](packages/com.yourname.camerabuttonswap_2.6.1_iphoneos-arm64e.deb) | RootHide Dopamine、RootHide Bootstrap、Serotonin |

### 📲 安装方法（Sileo / Filza）：

1. 根据您的越狱环境，通过 AirDrop 将对应包发送到手机：
   - 如果是**标准 Dopamine**：安装 `...iphoneos-arm64.deb`；
   - 如果是 **RootHide Dopamine**：安装 `...iphoneos-arm64e.deb`。
2. 使用 **Filza** 打开，点击右上角分享选择 **“用 Sileo 安装”**（或直接在 Sileo 内搜索本地 deb 安装）。
3. 安装完成后注销（Respring）或彻底关闭相机 App 后台并重新打开。长按实况文本按钮即可随心拖拽定制位置！

---

## 📜 版本演进历史 (Changelog)

| 版本 | 状态 | 核心更新说明 |
| :--- | :--- | :--- |
| **v2.6.1** | **Latest (最终稳定版)** | 修复长按拖拽保存后相机闪退的递归重入 Bug，加入全局防重入锁 `isRelocating` 与位移死区滤波；全面支持标准 Rootless (`iphoneos-arm64`) 与 RootHide (`iphoneos-arm64e`) 双架构。 |
| **v2.6.0** | 体验重磅升级 | 引入屏幕长按 0.45s 自由拖拽与持久化记忆功能，支持双击/拖回复位，独占手势保护。 |
| **v2.5.0** | 关键交互修复 | 解决点击实况文本按钮后无法划选文字的问题，精准建立 90x90 pt 尺寸限制与白名单，彻底排除 `VKCImageAnalysisBaseView` 等 VisionKit 全屏分析画布，移除侵入式弹窗。 |
| **v2.4.0** | SDK 与签名重构 | 配置官方 `iPhoneOS17.3.1.sdk` 直编，补全 Ad-hoc 代码签名，彻底解决 iOS 17 dyld/AMFI 拒绝加载问题。 |
| **v2.3.0** | 零依赖纯原生 | 引入 Logos `internal` 生成器生成纯原生 Objective-C runtime 交换代码，彻底剥离 `CydiaSubstrate` 依赖，解决 Dopamine ElleKit 兼容性与 dpkg 路径解压报错。 |
| **v2.2.0** | 路径排查 | 修复文件系统解包路径问题，适配标准 `/var/jb/Library/MobileSubstrate/DynamicLibraries/`。 |
| **v2.1.0** | 注入感知排查 | 增加物理触感震动反馈与注入通知排查机制。 |
| **v2.0.0** | iOS 17 全面适配 | 针对 iOS 17 进行架构重构，引入类级 `setFrame:` / `setCenter:` 拦截与微距按钮避让。 |
| **v1.3.0** | 功能增强 | 增加注入 HUD 指示器与图标特征识别。 |
| **v1.2.0** | 初步适配 | 初步适配 iOS 17 系统相机实况文本层。 |
| **v1.1.0** | 基础发布 | 基础版本，实况文本按钮移动到左侧。 |

---

## 📁 项目结构 (Project Structure)

```
CameraButtonSwap/
├── Makefile                    # Theos 构建配置文件 (支持 rootless / roothide 双模式)
├── control                     # Debian 软件包信息 (Architecture: iphoneos-arm64)
├── CameraButtonSwap.plist      # MobileSubstrate 注入规则 (Camera + SpringBoard)
├── Tweak.x                     # 核心 Hook 代码 (基于 CameraUI + VisionKitCore，纯原生运行时交换)
├── packages/                   # 历代全版本编译好的 deb 安装包
│   ├── com.yourname.camerabuttonswap_1.3.0_iphoneos-arm64.deb
│   ├── com.yourname.camerabuttonswap_2.0.0_iphoneos-arm64.deb
│   ├── com.yourname.camerabuttonswap_2.1.0_iphoneos-arm64.deb
│   ├── com.yourname.camerabuttonswap_2.2.0_iphoneos-arm64.deb
│   ├── com.yourname.camerabuttonswap_2.3.0_iphoneos-arm64.deb
│   ├── com.yourname.camerabuttonswap_2.4.0_iphoneos-arm64.deb
│   ├── com.yourname.camerabuttonswap_2.5.0_iphoneos-arm64.deb
│   ├── com.yourname.camerabuttonswap_2.6.0_iphoneos-arm64.deb
│   ├── com.yourname.camerabuttonswap_2.6.1_iphoneos-arm64.deb       # 标准无根最新稳定版
│   └── com.yourname.camerabuttonswap_2.6.1_iphoneos-arm64e.deb      # RootHide 最新稳定版
├── layout/
│   └── DEBIAN/
│       ├── postinst            # 安装后重启 Camera 进程脚本
│       └── postrm              # 卸载后恢复脚本
└── README.md
```

---

## 🛠 源码编译指南 (Build Instructions)

### 环境要求
- macOS 系统
- [Theos](https://theos.dev/) 开发环境
- iOS 17.3.1 SDK (`iPhoneOS17.3.1.sdk`)
- `dpkg`、`ldid`、`codesign`

### 1. 编译标准无根版本 (Dopamine Rootless)
```bash
export THEOS=~/theos
export PATH="$THEOS/bin:$PATH"

make clean
make package FINALPACKAGE=1
```
生成的包位于 `packages/com.yourname.camerabuttonswap_2.6.1_iphoneos-arm64.deb`。

### 2. 编译 RootHide 版本 (RootHide Dopamine)
```bash
export THEOS=~/theos
export PATH="$THEOS/bin:$PATH"

make clean
make package THEOS_PACKAGE_SCHEME=roothide FINALPACKAGE=1
```
生成的包位于 `packages/com.yourname.camerabuttonswap_2.6.1_iphoneos-arm64e.deb`。

---

## 📄 License

MIT License
