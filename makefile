THEOS_PACKAGE_SCHEME = rootless
ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0

INSTALL_TARGET_PROCESSES = SpringBoard
include $(THEOS)/makefiles/common.mk

TWEAK_NAME = CCOCK18
CCOCK18_FILES = tweak.xm PACC.x PAnim.x PACCIndicator.x PACCMedia.x PACCCoordinator.x PACCDesign.x PACCEdit.xm PACCLIQ.x

CCOCK18_CFLAGS = -fobjc-arc 
CCOCK18_FRAMEWORKS = UIKit
include $(THEOS_MAKE_PATH)/tweak.mk
SUBPROJECTS += prefs

include $(THEOS_MAKE_PATH)/aggregate.mk
after-install::
	install.exec "sbreload"