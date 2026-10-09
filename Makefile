# 项目目标设备架构
ARCHS = arm64 arm64e

# 目标 iOS 版本（兼容 iOS 15+）
TARGET := iphone:clang:15.6:15.0

# 无根越狱方案 (Rootless)
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = CameraButtonSwap

# 源文件
CameraButtonSwap_FILES = Tweak.x

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
