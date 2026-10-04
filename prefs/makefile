ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = CCOCK18Prefs

CCOCK18Prefs_FILES = CCOCK18RootListController.m
CCOCK18Prefs_FRAMEWORKS = UIKit
CCOCK18Prefs_PRIVATE_FRAMEWORKS = Preferences
CCOCK18Prefs_INSTALL_PATH = /Library/PreferenceBundles
CCOCK18Prefs_CFLAGS = -fobjc-arc
CCOCK18Prefs_RESOURCE_DIRS = Resources


include $(THEOS_MAKE_PATH)/bundle.mk

after-CCOCK18Prefs-stage::
	@mkdir -p "$(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences"
	@cp "Resources/CCOCK18Prefs.plist" "$(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/CCOCK18Prefs.plist"