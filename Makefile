THEOS_DEVICE_IP=192.168.1.227

TARGET := iphone:clang:latest:18.5
INSTALL_TARGET_PROCESSES = WeChat

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Jev-Chat

Jev-Chat_FILES = WIACore.xm WIAUI.xm WIAFeatures.xm WIASettings.xm WIAPreserve.xm FloatingButtonWindow.m CustomToastView.m
Jev-Chat_CFLAGS = -fobjc-arc -Wno-error

include $(THEOS_MAKE_PATH)/tweak.mk
