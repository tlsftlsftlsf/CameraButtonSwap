# 项目目标设备架构
ARCHS = arm64 arm64e

# 目标 iOS 版本（兼容 iOS 15+）
TARGET := iphone:clang:15.6:15.0

# 安装目标设备（编译时设置，也可通过环境变量覆盖）
# THEOS_DEVICE_IP = 你的设备IP
# THEOS_DEVICE_PORT = 22
# 无根越狱方案 (Rootless)
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = CameraButtonSwap

# 源文件
CameraButtonSwap_FILES = Tweak.x

# 编译选项
CameraButtonSwap_CFLAGS = -fobjc-arc -Wno-unused-function
CameraButtonSwap_FRAMEWORKS = UIKit Foundation

# 链接 CameraUI 私有框架（运行时动态加载，不需要编译时链接）
# CameraButtonSwap_PRIVATE_FRAMEWORKS = CameraUI

# DEBUG 模式下添加调试宏
ifeq ($(DEBUG),1)
CameraButtonSwap_CFLAGS += -DDEBUG
endif

include $(THEOS_MAKE_PATH)/tweak.mk

# 告知 Sileo：安装后需要重启这些进程
INSTALL_TARGET_PROCESSES = Camera
