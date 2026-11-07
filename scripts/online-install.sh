#!/bin/sh
set -eu

REPO="${LUCKY_GH_REPO:-FloatingDream528/luci-app-lucky}"
GH_PROXY="${GH_PROXY:-}"

# 规范化镜像代理前缀（例如 GH_PROXY=https://ghfast.top/）
if [ -n "$GH_PROXY" ]; then
	case "$GH_PROXY" in
		*/) ;;
		*) GH_PROXY="${GH_PROXY}/" ;;
	esac
fi

if ! command -v apk >/dev/null 2>&1; then
	echo "错误: 当前系统未找到 apk 包管理器，本脚本仅适用于采用 apk 的新版 OpenWrt。" >&2
	exit 1
fi

ARCH="${LUCKY_APK_ARCH:-$(apk --print-arch 2>/dev/null || true)}"
if [ -z "$ARCH" ] && [ -f /etc/apk/arch ]; then
	ARCH="$(head -n 1 /etc/apk/arch | tr -d '[:space:]')"
fi

case "$ARCH" in
	x86_64|aarch64_generic|arm_cortex-a7_neon-vfpv4|mips_24kc|mipsel_24kc|i386_pentium4)
		;;
	*)
		echo "错误: 当前路由器 APK 架构为 '${ARCH:-unknown}'，暂不在预编译矩阵列表内：" >&2
		echo "  支持列表: x86_64, aarch64_generic, arm_cortex-a7_neon-vfpv4, mips_24kc, mipsel_24kc, i386_pentium4" >&2
		echo "  如需强制指定架构下载，可执行: LUCKY_APK_ARCH=<架构名> sh $0" >&2
		exit 1
		;;
esac

fetch_stdout() {
	url="$1"
	if command -v curl >/dev/null 2>&1; then
		curl -fsSL --connect-timeout 15 --retry 3 "$url"
	elif command -v uclient-fetch >/dev/null 2>&1; then
		uclient-fetch -qO- "$url"
	elif command -v wget >/dev/null 2>&1; then
		wget -qO- "$url"
	else
		echo "错误: 系统中未找到 curl / uclient-fetch / wget 下载工具。" >&2
		exit 1
	fi
}

fetch_file() {
	url="$1"
	dest="$2"
	if command -v curl >/dev/null 2>&1; then
		curl -fL --connect-timeout 15 --retry 3 "$url" -o "$dest"
	elif command -v uclient-fetch >/dev/null 2>&1; then
		uclient-fetch -O "$dest" "$url"
	else
		wget -O "$dest" "$url"
	fi
}

echo "检测到路由器 APK 架构: $ARCH"
echo "正在查询 ${REPO} 最新版本信息..."

API_URL="https://api.github.com/repos/${REPO}/releases?per_page=1"
RELEASE_JSON="$(fetch_stdout "$API_URL")"

ZIP_URL=""
if command -v jsonfilter >/dev/null 2>&1; then
	ZIP_URL="$(
		printf '%s' "$RELEASE_JSON" |
			jsonfilter -e '@[0].assets[*].browser_download_url' 2>/dev/null |
			grep -- "-${ARCH}\\.zip$" |
			head -n 1 || true
	)"
fi

if [ -z "$ZIP_URL" ]; then
	ZIP_URL="$(
		printf '%s' "$RELEASE_JSON" |
			grep -Eo "https://github\.com/${REPO}/releases/download/[^\" ]+-${ARCH}\.zip" |
			head -n 1 || true
	)"
fi

if [ -z "$ZIP_URL" ]; then
	echo "错误: 未能从最新 Release 中找到架构 ${ARCH} 对应的 Zip 压缩包。" >&2
	exit 1
fi

DOWNLOAD_URL="${GH_PROXY}${ZIP_URL}"

if ! command -v unzip >/dev/null 2>&1; then
	echo "当前系统未安装 unzip，正在通过 apk 自动安装 unzip..."
	apk update && apk add unzip
fi

TMP_DIR="/tmp/lucky-apk-install.$$"
cleanup() {
	rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM
mkdir -p "$TMP_DIR"

ZIP_FILE="$TMP_DIR/lucky-${ARCH}.zip"
echo "正在下载: $DOWNLOAD_URL"
fetch_file "$DOWNLOAD_URL" "$ZIP_FILE"

echo "正在解压安装包..."
unzip -oq "$ZIP_FILE" -d "$TMP_DIR"

if [ -f "$TMP_DIR/install-apk.sh" ]; then
	sh "$TMP_DIR/install-apk.sh" "$TMP_DIR"
else
	apk add --allow-untrusted \
		"$TMP_DIR"/lucky-*.apk \
		"$TMP_DIR"/luci-app-lucky-*.apk \
		"$TMP_DIR"/luci-i18n-lucky-zh-cn-*.apk
	rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache/ 2>/dev/null || true
	/etc/init.d/rpcd reload >/dev/null 2>&1 || true
	/etc/init.d/uhttpd reload >/dev/null 2>&1 || true
	/etc/init.d/lucky enable >/dev/null 2>&1 || true
	/etc/init.d/lucky restart >/dev/null 2>&1 || /etc/init.d/lucky start >/dev/null 2>&1 || true
	echo "Lucky APK 安装完成！"
fi
