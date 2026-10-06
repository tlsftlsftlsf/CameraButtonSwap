# CameraButtonSwap - iOS 15.4.1 相机实况文本按钮左置插件

适用于 iOS 15.4.1 系统相机 App 的无根越狱（Rootless）Tweak，专为左撇子或习惯左手单手操作的用户设计。

---

## 🌟 功能特性

- **实况文本按钮左置**：在相机取景框检测到文字并弹出「扫描文本 / 实况文本」按钮时，自动将其镜像移动到**屏幕左侧（左下角）**，方便左手大拇指快速点击。
- **智能避让微距按钮**：极近距离同时触发微距模式（左下角花朵按钮）时，实况文本按钮会自动上移至微距按钮正上方（保留 12pt 间距），防止重叠误触。
- **支持锁屏相机**：注入规则包含 `com.apple.camera` 与 `com.apple.springboard`，无论是桌面打开相机还是锁屏右滑打开相机均可生效。
- **无根越狱（Rootless）适配**：原生编译为 `iphoneos-arm64` 架构，支持 Dopamine / Palera1n / ElleKit，安装即用。

---

## 📦 开箱即用（已编译好的 deb）

已编译好的无根越狱包位于本仓库目录：
- [`packages/com.yourname.camerabuttonswap_1.1.0_iphoneos-arm64.deb`](packages/com.yourname.camerabuttonswap_1.1.0_iphoneos-arm64.deb)

### 安装方法（Sileo / Filza）：

1. 在手机上下载或通过 AirDrop 隔空投送 `com.yourname.camerabuttonswap_1.1.0_iphoneos-arm64.deb` 到手机。
2. 使用 **Filza** 打开，点击右上角分享选择 **“用 Sileo 安装”**（或直接在 Filza 内点击右上角安装）。
3. 安装完成后，完全关闭相机 App 后台并重新打开即可生效。

---

## 📁 项目结构

```
CameraButtonSwap/
├── Makefile                    # Theos 构建配置文件 (THEOS_PACKAGE_SCHEME = rootless)
├── control                     # Debian 软件包信息 (Architecture: iphoneos-arm64)
├── CameraButtonSwap.plist      # MobileSubstrate 注入规则 (Camera + SpringBoard)
├── Tweak.x                     # 核心 Hook 代码 (基于 CameraUI.framework)
├── packages/
│   └── com.yourname.camerabuttonswap_1.1.0_iphoneos-arm64.deb # 编译好的 deb 安装包
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

## 🔍 技术实现细节

- **目标私有类**：
  - `CAMImageAnalysisButton`: iOS 15 系统相机内部真正的实况文本按钮类。
  - `CAMFullscreenViewfinder`: 全屏取景器主容器，负责管理 `_imageAnalysisButton` 与 `_autoMacroButton`。
  - `CAMBottomBar`: 底部操作栏，负责管理底部文本按钮与背景遮罩。
- **预加载保障**：在 `%ctor` 构造函数中显式动态加载 `/System/Library/PrivateFrameworks/CameraUI.framework`，解决进程初始化早期私有类未注册导致的 Hook 失败问题。

---

## 📄 License

MIT License
