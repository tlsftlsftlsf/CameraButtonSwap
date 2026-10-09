# CameraButtonSwap - iOS 15.0 ~ 17.3.1 相机实况文本按钮左置插件 (v2.4.0)

适用于 iOS 15.0 ~ 17.3.1 系统相机 App 的无根越狱（Rootless）Tweak，专为左撇子或习惯左手单手操作的用户深度打造。

---

## 🌟 功能特性 (v2.4.0 关键更新)

- **原生 iOS 17.3.1 SDK 编译**：使用官方 `iPhoneOS17.3.1.sdk` 直编，全面匹配 iOS 17 系统符号与 Mach-O 平台标准。
- **纯原生零外部依赖**：通过 Logos `internal` 生成器生成纯原生 Objective-C runtime swizzling，彻底剥离 `CydiaSubstrate.framework` 依赖，完美兼容 Dopamine 2.x/3.x 与 ElleKit。
- **Ad-hoc 代码签名补全**：自动为 dylib 补全 `flags=0x2(adhoc)` 签名，彻底攻克 iOS 17 AMFI / dyld 拒绝加载无签名库的问题。
- **三重即时反馈**：
  - **硬件触感震动**：进入相机或注入瞬间触发物理触感震动；
  - **系统级 Alert 提示**：安全弹出「⚡️ CameraButtonSwap 插件已成功注入」弹窗（2.5 秒自动关闭）；
  - **顶部黑金胶囊 HUD**：状态栏下方悬浮提示。
- **多通道排查日志**：支持 `os_log` / `NSLog`、`/var/mobile/Media/camerabuttonswap.log` 及沙盒目录日志同步记录。
- **实况文本按钮左置**：在相机取景框检测到文字并弹出「扫描文本 / 实况文本」按钮时，自动将其精准镜像移动到**屏幕左侧（左下角）**，方便左手大拇指单手快速点击。
- **智能避让微距按钮**：极近距离同时触发微距模式（左下角花朵按钮）时，实况文本按钮会自动上移至微距按钮正上方（保留 12pt 间距），防止重叠误触。
- **支持锁屏相机**：注入规则包含 `com.apple.camera` 与 `com.apple.springboard`，桌面打开或锁屏右滑打开相机均全面生效。

---

## 📦 开箱即用（已编译好的 deb）

已编译好的无根越狱包位于本仓库根目录与桌面：
- [`packages/com.yourname.camerabuttonswap_2.4.0_iphoneos-arm64.deb`](packages/com.yourname.camerabuttonswap_2.4.0_iphoneos-arm64.deb)

### 安装方法（Sileo / Filza）：

1. 在手机上下载或通过 AirDrop 隔空投送 `com.yourname.camerabuttonswap_2.4.0_iphoneos-arm64.deb` 到手机。
2. 使用 **Filza** 打开，点击右上角分享选择 **“用 Sileo 安装”**（或直接在 Filza 内点击右上角安装）。
3. 安装完成后注销（Respring）或彻底关闭相机 App 后台并重新打开。打开时即可感受到触感震动与注入提示。

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
