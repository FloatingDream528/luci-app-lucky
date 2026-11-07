#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PKG_DIR="${1:-$SCRIPT_DIR}"

if ! command -v apk >/dev/null 2>&1; then
	echo "错误: 当前系统未找到 apk 包管理器，请在使用 OpenWrt apk 包管理器的固件上运行。" >&2
	exit 1
fi

collect_apks() {
	dir="$1"
	for pattern in \
		"$dir"/lucky-*.apk \
		"$dir"/luci-app-lucky-*.apk \
		"$dir"/luci-i18n-lucky-zh-cn-*.apk
	do
		[ -f "$pattern" ] || continue
		printf '%s\n' "$pattern"
	done
}

APK_LIST="$(collect_apks "$PKG_DIR")"
if [ -z "$APK_LIST" ] && [ "$PKG_DIR" = "$SCRIPT_DIR" ] && [ "$PWD" != "$SCRIPT_DIR" ]; then
	APK_LIST="$(collect_apks "$PWD")"
fi

if [ -z "$APK_LIST" ]; then
	echo "错误: 未在 $PKG_DIR 找到 lucky / luci-app-lucky 的 .apk 安装包。" >&2
	exit 1
fi

set --
OLD_IFS="$IFS"
IFS='
'
for pkg in $APK_LIST; do
	set -- "$@" "$pkg"
done
IFS="$OLD_IFS"

echo "正在安装以下软件包:"
for pkg in "$@"; do
	echo "  - $(basename "$pkg")"
done

/etc/init.d/lucky stop >/dev/null 2>&1 || true
apk add --allow-untrusted "$@"

rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache/ 2>/dev/null || true
/etc/init.d/rpcd reload >/dev/null 2>&1 || true
/etc/init.d/uhttpd reload >/dev/null 2>&1 || true
/etc/init.d/lucky enable >/dev/null 2>&1 || true
/etc/init.d/lucky restart >/dev/null 2>&1 || /etc/init.d/lucky start >/dev/null 2>&1 || true

echo "Lucky APK 安装完成！请刷新 LuCI 网页并在「服务 -> Lucky」中查看状态。"
