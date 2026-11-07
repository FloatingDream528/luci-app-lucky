#!/usr/bin/env bash
set -euo pipefail

cd /builder

TARGET="${TARGET:-x86/64}"
VERSION_PATH="${VERSION_PATH:-snapshots}"
DOWNLOAD_FILE="${DOWNLOAD_FILE:-sdk-.*x86_64.tar.[xz|zst]}"
DOWNLOAD_PATH="${VERSION_PATH}/targets/${TARGET}"
CDN_HOST="${OPENWRT_CDN_URL:-https://downloads.cdn.openwrt.org}"
FALLBACK_HOST="https://downloads.openwrt.org"
BUILD_LUCI="${BUILD_LUCI:-0}"

fetch_with_fallback() {
	local rel_path="$1"
	local out_file="$2"
	if curl -fSL --connect-timeout 10 --retry 3 --retry-delay 2 "${CDN_HOST}/${rel_path}" -o "$out_file"; then
		return 0
	fi
	echo "CDN 下载失败，回退至官方源: ${FALLBACK_HOST}/${rel_path}"
	curl -fSL --connect-timeout 15 --retry 5 --retry-delay 3 "${FALLBACK_HOST}/${rel_path}" -o "$out_file"
}

if [ -f setup.sh ]; then
	echo "::group::Prepare OpenWrt SDK (${TARGET} - ${VERSION_PATH})"
	cached_tar="$(find /sdk-cache -maxdepth 1 -type f -name '*sdk-*.tar.*' | head -n 1 || true)"
	if [ -n "$cached_tar" ] && [ -f /sdk-cache/sha256sums_min ]; then
		echo "命中 GitHub Actions SDK 缓存: $(basename "$cached_tar")"
		(cd /sdk-cache && sha256sum -c sha256sums_min)
		rm -rf /builder/keys/
	else
		echo "未命中缓存，正在从高速 CDN (${CDN_HOST}) 拉取 OpenWrt SDK..."
		rm -rf /sdk-cache/*
		fetch_with_fallback "${DOWNLOAD_PATH}/sha256sums" sha256sums
		fetch_with_fallback "${DOWNLOAD_PATH}/sha256sums.asc" sha256sums.asc

		gpg --import /builder/keys/*.asc && rm -rf /builder/keys/
		gpg --with-fingerprint --verify sha256sums.asc sha256sums

		file_name="$(grep "$DOWNLOAD_FILE" sha256sums | cut -d "*" -f 2 | head -n 1)"
		if [ -z "$file_name" ]; then
			echo "错误: 未在 sha256sums 中匹配到 SDK 压缩包 ($DOWNLOAD_FILE)" >&2
			exit 1
		fi

		fetch_with_fallback "${DOWNLOAD_PATH}/${file_name}" "/sdk-cache/${file_name}"
		grep "$file_name" sha256sums > /sdk-cache/sha256sums_min
		(cd /sdk-cache && sha256sum -c sha256sums_min)
		rm -f sha256sums sha256sums.asc
		cached_tar="/sdk-cache/${file_name}"
	fi

	tar xf "$cached_tar" --strip=1 --no-same-owner -C /builder
	rm -f setup.sh
	echo "::endgroup::"
fi

git config --global --add safe.directory /feed || true

echo "::group::Configure & Update Feeds (BUILD_LUCI=${BUILD_LUCI})"
sed \
	-e 's,https://git.openwrt.org/feed/,https://github.com/openwrt/,' \
	-e 's,https://git.openwrt.org/openwrt/,https://github.com/openwrt/,' \
	-e 's,https://git.openwrt.org/project/,https://github.com/openwrt/,' \
	feeds.conf.default > feeds.conf.all

if [ "$BUILD_LUCI" = "1" ]; then
	grep -E '^src-[^[:space:]]+[[:space:]]+(base|packages|luci)[[:space:]]' feeds.conf.all > feeds.conf
	echo "src-link lucky /feed" >> feeds.conf
	PACKAGES="lucky luci-app-lucky"
else
	grep -E '^src-[^[:space:]]+[[:space:]]+base[[:space:]]' feeds.conf.all > feeds.conf
	rm -rf /tmp/lucky-feed
	mkdir -p /tmp/lucky-feed
	cp -a /feed/lucky /tmp/lucky-feed/
	echo "src-link lucky /tmp/lucky-feed" >> feeds.conf
	PACKAGES="lucky"
fi
rm -f feeds.conf.all

cat feeds.conf
./scripts/feeds update -a

for pkg in $PACKAGES; do
	./scripts/feeds install -p lucky -f "$pkg"
done
echo "::endgroup::"

echo "::group::make defconfig"
make defconfig
echo "::endgroup::"

for pkg in $PACKAGES; do
	echo "::group::Compile package/${pkg}"
	make \
		BUILD_LOG=1 \
		CONFIG_AUTOREMOVE=y \
		V="${V:-s}" \
		-j"$(nproc)" \
		"package/${pkg}/compile"
	echo "::endgroup::"
done

mkdir -p /artifacts
cp -rf bin /artifacts/
if [ -d logs ]; then
	cp -rf logs /artifacts/
fi
