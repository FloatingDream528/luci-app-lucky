#!/bin/sh
set -eu

PKG_DIR="${1:-.}"

if ! command -v apk >/dev/null 2>&1; then
	echo "当前系统未找到 apk 包管理器，请在使用新版 OpenWrt apk 包管理器的固件上运行。"
	exit 1
fi

set --
for pattern in \
	"$PKG_DIR"/lucky-*.apk \
	"$PKG_DIR"/luci-app-lucky-*.apk \
	"$PKG_DIR"/luci-i18n-lucky-zh-cn-*.apk
do
	[ -e "$pattern" ] || continue
	set -- "$@" "$pattern"
done

if [ "$#" -eq 0 ]; then
	echo "未在 $PKG_DIR 找到 lucky/luci-app-lucky 的 .apk 包。"
	exit 1
fi

/etc/init.d/lucky stop >/dev/null 2>&1 || true
apk add --allow-untrusted "$@"

/etc/init.d/rpcd reload >/dev/null 2>&1 || true
/etc/init.d/uhttpd reload >/dev/null 2>&1 || true
/usr/bin/lucky-update >/dev/null 2>&1 || true
/etc/init.d/lucky enable >/dev/null 2>&1 || true
/etc/init.d/lucky restart >/dev/null 2>&1 || /etc/init.d/lucky start >/dev/null 2>&1 || true

echo "Lucky APK 安装完成。"
