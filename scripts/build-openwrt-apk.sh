#!/usr/bin/env bash
set -euo pipefail

cd /builder

BUILD_LUCI="${BUILD_LUCI:-0}"

if [ -f setup.sh ]; then
	echo "::group::Extract & Verify OpenWrt SDK"
	cached_tar="$(find /sdk-cache -maxdepth 1 -type f -name '*sdk-*.tar.*' | head -n 1 || true)"
	if [ -z "$cached_tar" ] || [ ! -f /sdk-cache/sha256sums_min ]; then
		echo "错误: /sdk-cache 中未找到预下载的 OpenWrt SDK 压缩包。" >&2
		exit 1
	fi

	if [ -f /sdk-cache/sha256sums ] && [ -f /sdk-cache/sha256sums.asc ] && [ -d /builder/keys ]; then
		gpg --import /builder/keys/*.asc
		gpg --with-fingerprint --verify /sdk-cache/sha256sums.asc /sdk-cache/sha256sums
		rm -f /sdk-cache/sha256sums /sdk-cache/sha256sums.asc
	fi
	rm -rf /builder/keys/

	echo "校验 SDK 完整性: $(basename "$cached_tar")"
	(cd /sdk-cache && sha256sum -c sha256sums_min)

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
