# CameraButtonSwap - iOS 15.0 ~ 17.3.1 相机实况文本按钮左置插件 (v2.6.0 自由拖拽版)

适用于 iOS 15.0 ~ 17.3.1 系统相机 App 的无根越狱（Rootless）Tweak，专为左撇子或习惯左手单手操作的用户深度打造。

---

## 🌟 功能特性 (v2.6.0 重磅升级)

- **屏幕长按自由拖拽与持久化记忆 (Custom Drag & Drop)**：
  - **长按拖拽**：在相机取景框内**长按实况文本按钮 0.45 秒**，伴随触感微震，即可随意将按钮拖拽到任何您感觉最舒服顺手的屏幕位置！
  - **松开即存**：松开手指即刻自动持久化保存该专属坐标，下次打开相机或任何时候均在您的自定义位置。
  - **双击复位**：快速**双击该按钮**或将其**拖回左下角边缘**，即可随时一键恢复到默认自适应推荐位置。
  - **手势独占保护**：拖动按钮时自动拦截底层取景器的滑动事件，不会误触发切换相机拍摄模式。
- **精准保护 VisionKit 文本划词与选择系统**：
  - 仅 Hook 90x90 pt 以内的独立按钮实体，严格排除所有全屏分析画布与文本选区层（`VKCImageAnalysisBaseView` 等），彻底解决点击按钮后划词、复制文字失效的问题。
- **原生 iOS 17.3.1 SDK 编译**：使用官方 `iPhoneOS17.3.1.sdk` 直编，全面匹配 iOS 17 系统符号与 Mach-O 平台标准。
- **纯原生零外部依赖**：通过 Logos `internal` 生成器生成纯原生 Objective-C runtime swizzling，彻底剥离 `CydiaSubstrate.framework` 依赖，完美兼容 Dopamine 2.x/3.x 与 ElleKit。
- **Ad-hoc 代码签名补全**：自动为 dylib 补全 `flags=0x2(adhoc)` 签名，彻底攻克 iOS 17 AMFI / dyld 拒绝加载无签名库的问题。
- **智能避让微距按钮**：默认模式下，极近距离触发微距模式（左下角花朵按钮）时自动智能避让。
- **支持锁屏相机**：注入规则包含 `com.apple.camera` 与 `com.apple.springboard`，桌面打开或锁屏右滑打开相机均全面生效。

---

## 📦 开箱即用（已编译好的 deb）

已编译好的无根越狱包位于本仓库根目录与桌面：
- [`packages/com.yourname.camerabuttonswap_2.6.0_iphoneos-arm64.deb`](packages/com.yourname.camerabuttonswap_2.6.0_iphoneos-arm64.deb)

### 安装方法（Sileo / Filza）：

1. 在手机上下载或通过 AirDrop 隔空投送 `com.yourname.camerabuttonswap_2.6.0_iphoneos-arm64.deb` 到手机。
2. 使用 **Filza** 打开，点击右上角分享选择 **“用 Sileo 安装”**（或直接在 Filza 内点击右上角安装）。
3. 安装完成后注销（Respring）或彻底关闭相机 App 后台并重新打开。长按实况文本按钮即可随心拖拽定制位置！

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
