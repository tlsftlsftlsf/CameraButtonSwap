# CameraButtonSwap - iOS 15.0 ~ 17.3.1 相机实况文本按钮左置插件 (v2.0.0)

适用于 iOS 15.0 ~ 17.3.1 系统相机 App 的无根越狱（Rootless）Tweak，专为左撇子或习惯左手单手操作的用户深度打造。

---

## 🌟 功能特性

- **实况文本按钮左置**：在相机取景框检测到文字并弹出「扫描文本 / 实况文本」按钮时，自动将其精准镜像移动到**屏幕左侧（左下角）**，方便左手大拇指单手快速点击。
- **智能避让微距按钮**：极近距离同时触发微距模式（左下角花朵按钮）时，实况文本按钮会自动上移至微距按钮正上方（保留 12pt 间距），防止重叠误触。
- **iOS 17 / 17.3.1 深度重构**：
  - **精准类级 Hook**：直接拦截 `CAMImageAnalysisButton`、`VKImageAnalysisButton`、`VKCCornerLookupButton` 的 `setFrame:` 与 `setCenter:`，在任何布局引擎将其置于右侧时即刻拦截重算。
  - **宿主容器布局拦截**：Hook `CAMFullscreenViewfinder` 与 `CAMBottomBar` 的 `layoutSubviews`，直接获取内部 `_imageAnalysisButton` 实例进行左置。
  - **容器冒泡与约束反转**：彻底解决 iOS 17 嵌套小容器与 Auto Layout 强行回弹问题，自动反转 Trailing 为 Leading 约束，并提供 GPU 图层平移兜底。
  - **可视化注入 HUD**：应用打开或唤醒时，顶部悬浮黑金胶囊提示 `⚡️ CameraButtonSwap 已注入 (iOS 17 适配版)`，一眼确认 ElleKit 注入状态。
  - **双通道排查日志**：系统控制台 `NSLog` 与本地文件 `/var/mobile/Library/Logs/CameraButtonSwap.log` 同步记录，排查无死角。
- **支持锁屏相机**：注入规则包含 `com.apple.camera` 与 `com.apple.springboard`，桌面打开或锁屏右滑打开相机均全面生效。
- **无根越狱（Rootless）全兼容**：原生编译为 `iphoneos-arm64` 架构，完美支持 Dopamine (iOS 15.0 ~ 17.3.1) / Palera1n / ElleKit。

---

## 📦 开箱即用（已编译好的 deb）

已编译好的无根越狱包位于本仓库根目录与桌面：
- [`packages/com.yourname.camerabuttonswap_2.0.0_iphoneos-arm64.deb`](packages/com.yourname.camerabuttonswap_2.0.0_iphoneos-arm64.deb)

### 安装方法（Sileo / Filza）：

1. 在手机上下载或通过 AirDrop 隔空投送 `com.yourname.camerabuttonswap_2.0.0_iphoneos-arm64.deb` 到手机。
2. 使用 **Filza** 打开，点击右上角分享选择 **“用 Sileo 安装”**（或直接在 Filza 内点击右上角安装）。
3. 安装完成后，完全关闭相机 App 后台并重新打开。打开时屏幕顶部会短暂弹出 **「⚡️ CameraButtonSwap 已注入 (iOS 17 适配版)」** 黑金胶囊提示，确认注入生效。

---

## 📁 项目结构

```
CameraButtonSwap/
├── Makefile                    # Theos 构建配置文件 (THEOS_PACKAGE_SCHEME = rootless)
├── control                     # Debian 软件包信息 (Architecture: iphoneos-arm64)
├── CameraButtonSwap.plist      # MobileSubstrate 注入规则 (Camera + SpringBoard)
├── Tweak.x                     # 核心 Hook 代码 (基于 CameraUI + VisionKitCore)
├── packages/
│   └── com.yourname.camerabuttonswap_2.0.0_iphoneos-arm64.deb # 编译好的 deb 安装包
├── layout/
│   └── DEBIAN/
│       ├── postinst            # 安装后重启 Camera 进程脚本
│       └── postrm              # 卸载后恢复脚本
└── README.md
```

---

## 🛠 源码编译指南

### 环境要求
- macOS 系统
- [Theos](https://theos.dev/) 开发环境
- iOS 15+ SDK（如 `iPhoneOS15.6.sdk`）
- `dpkg`、`ldid`

### 编译命令
```bash
export THEOS=~/theos
export PATH="$THEOS/bin:$PATH"

# 编译并打包为无根越狱 deb
make clean
make package FINALPACKAGE=1
```

生成的 `.deb` 文件会自动存放在 `packages/` 目录下。

---

## 📄 License

MIT License
