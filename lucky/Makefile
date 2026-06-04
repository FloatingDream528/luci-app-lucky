# SPDX-License-Identifier: GPL-3.0-only
#

include $(TOPDIR)/rules.mk

PKG_NAME:=lucky
PKG_VERSION:=3.0.0_beta5
PKG_RELEASE:=1
PKGARCH:=all 
LUCKY_UPSTREAM_VERSION:=3.0.0
LUCKY_RELEASE_DIR:=v3.0.0beta5/3.0.0_lucky
LUCKY_RELEASE_BASE:=https://release.66666.host/$(LUCKY_RELEASE_DIR)
LUCKY_CONF_DIR := /etc/config/lucky.daji
LUCKY_TMP_BACKUP := /tmp/luckyconfdir

PKG_LICENSE:=GPL-3.0-only
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=GDY666 <gdy666@foxmail.com>

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)
PKG_HASH:=skip

include $(INCLUDE_DIR)/package.mk

define Package/$(PKG_NAME)
	SECTION:=net
	CATEGORY:=Network
	TITLE:=Lucky gdy
	DEPENDS:=+ca-bundle
	URL:=https://github.com/gdy666/lucky
endef

define Package/$(PKG_NAME)/description
  Main functions of Lucky: ipv4/ipv6 portforward,ddns,IOT wake on lan ,reverse proxy and more...
endef




define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
endef



define Package/$(PKG_NAME)/conffiles
/etc/config/lucky
endef

define Build/Compile
endef

define Package/$(PKG_NAME)/install
	$(INSTALL_DIR) $(1)/usr/bin/
	$(INSTALL_DIR) $(1)/etc/init.d/
	$(INSTALL_DIR) $(1)/etc/config/
	$(INSTALL_BIN) ./files/lucky-update $(1)/usr/bin/lucky-update
	$(INSTALL_BIN) ./files/lucky.init $(1)/etc/init.d/lucky
	$(INSTALL_CONF) $(CURDIR)/files/luckyuci $(1)/etc/config/lucky
endef

define Package/$(PKG_NAME)/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
/usr/bin/lucky-update || true
/etc/init.d/lucky enable >/dev/null 2>&1 || true
exit 0
endef



$(eval $(call BuildPackage,$(PKG_NAME)))
