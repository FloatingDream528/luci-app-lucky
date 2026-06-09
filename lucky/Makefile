# SPDX-License-Identifier: GPL-3.0-only
#

include $(TOPDIR)/rules.mk

PKG_NAME:=lucky
PKG_VERSION:=3.0.0_beta6
PKG_RELEASE:=1
LUCKY_UPSTREAM_VERSION:=3.0.0
LUCKY_CORE_ARCH:=x86_64
LUCKY_RELEASE_DIR:=v3.0.0beta6/3.0.0_lucky
LUCKY_RELEASE_BASE:=https://release.66666.host/$(LUCKY_RELEASE_DIR)
LUCKY_CONF_DIR := /etc/config/lucky.daji
LUCKY_TMP_BACKUP := /tmp/luckyconfdir

PKG_LICENSE:=GPL-3.0-only
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=GDY666 <gdy666@foxmail.com>

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)
PKG_SOURCE:=lucky_$(LUCKY_UPSTREAM_VERSION)_Linux_$(LUCKY_CORE_ARCH).tar.gz
PKG_SOURCE_URL:=$(LUCKY_RELEASE_BASE)
PKG_HASH:=364f258a20847b3937994e166177c7f908c0e4edbc21253d3a638ec9313bbde3

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
	rm -rf $(PKG_BUILD_DIR)
	mkdir -p $(PKG_BUILD_DIR)
	$(TAR) -xzf $(DL_DIR)/$(PKG_SOURCE) -C $(PKG_BUILD_DIR)
	test -x $(PKG_BUILD_DIR)/lucky
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
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/lucky $(1)/usr/bin/lucky
	$(INSTALL_BIN) ./files/lucky.init $(1)/etc/init.d/lucky
	$(INSTALL_CONF) $(CURDIR)/files/luckyuci $(1)/etc/config/lucky
endef

define Package/$(PKG_NAME)/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
/etc/init.d/lucky enable >/dev/null 2>&1 || true
exit 0
endef



$(eval $(call BuildPackage,$(PKG_NAME)))
