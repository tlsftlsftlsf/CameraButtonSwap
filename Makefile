# 项目目标设备架构
ARCHS = arm64 arm64e

# 目标 iOS 版本（使用原生 iOS 17.3.1 SDK 编译）
TARGET := iphone:clang:17.3.1:15.0

# 无根越狱方案 (Rootless)
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = CameraButtonSwap

# 源文件
CameraButtonSwap_FILES = Tweak.x

# 使用 internal 生成器：生成纯原生 Objective-C runtime hook 代码，彻底摆脱 CydiaSubstrate 依赖！
CameraButtonSwap_LOGOS_DEFAULT_GENERATOR = internal

# 编译选项与框架
CameraButtonSwap_CFLAGS = -fobjc-arc -Wno-unused-function -Wno-deprecated-declarations -Wno-incompatible-pointer-types
CameraButtonSwap_FRAMEWORKS = UIKit Foundation AudioToolbox

# DEBUG 模式下添加调试宏
ifeq ($(DEBUG),1)
CameraButtonSwap_CFLAGS += -DDEBUG
endif

include $(THEOS_MAKE_PATH)/tweak.mk

# 告知 Sileo：安装后需要重启这些进程并注销 SpringBoard
INSTALL_TARGET_PROCESSES = Camera SpringBoard

after-stage::
	@echo "[*] Ensuring ad-hoc code signature for iOS 17 dyld / Dopamine..."
	find $(THEOS_STAGING_DIR) -name "CameraButtonSwap.dylib" -exec codesign -f -s - {} +

