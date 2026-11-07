#!/usr/bin/env bash
set -euo pipefail

CHECK_ONLY=0
if [ "${1:-}" = "--check-only" ]; then
	CHECK_ONLY=1
fi

RELEASE_ROOT="${LUCKY_RELEASE_ROOT:-https://release.66666.host}"
CORE_ARCH="${LUCKY_CORE_ARCH:-x86_64}"
TARGET_TAG="${LUCKY_TARGET_TAG:-}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PYTHON_BIN=""
for candidate in python3 python; do
	if command -v "$candidate" >/dev/null 2>&1 &&
		"$candidate" -c 'import sys; raise SystemExit(0 if sys.version_info[0] == 3 else 1)' >/dev/null 2>&1; then
		PYTHON_BIN="$candidate"
		break
	fi
done

if [ -z "$PYTHON_BIN" ]; then
	echo "未找到 Python 3，无法解析 Lucky 最新版本。" >&2
	exit 1
fi

cd "$REPO_ROOT"

fetch() {
	curl --connect-timeout 15 --retry 5 --retry-delay 3 -fsSL "$1"
}

format_pkg_version() {
	printf '%s' "$1" | sed -E 's/^v//; s/(alpha|beta|rc)/_\1/'
}

if [ -n "$TARGET_TAG" ]; then
	latest_tag="$TARGET_TAG"
else
	root_html="$(fetch "${RELEASE_ROOT}/")"
	latest_tag="$(printf '%s' "$root_html" | "$PYTHON_BIN" -c '
import re
import sys

html = sys.stdin.read()
tags = set(re.findall(r"v\d+\.\d+\.\d+(?:(?:alpha|beta|rc)\d*)?", html))
if not tags:
    raise SystemExit("未从官方发布页解析到任何 Lucky 版本标签")

rank_map = {"alpha": 0, "beta": 1, "rc": 2, None: 3}
pattern = re.compile(r"^v(\d+)\.(\d+)\.(\d+)(?:(alpha|beta|rc)(\d*))?$")

versions = []
for tag in tags:
    m = pattern.match(tag)
    if not m:
        continue
    major, minor, patch, pre_type, pre_num = m.groups()
    pre_rank = rank_map[pre_type]
    seq_num = int(pre_num or 0) if pre_type is not None else 0
    versions.append(((int(major), int(minor), int(patch), pre_rank, seq_num), tag))

if not versions:
    raise SystemExit("没有匹配到合法的 Lucky 版本目录")

print(max(versions)[1])
')"
fi

package_version="$(format_pkg_version "$latest_tag")"
release_tag="lucky-${package_version}"

if [ "$CHECK_ONLY" -eq 1 ]; then
	echo "LUCKY_TAG=${latest_tag}"
	echo "PKG_VERSION=${package_version}"
	echo "RELEASE_TAG=${release_tag}"
	if [ -n "${GITHUB_OUTPUT:-}" ]; then
		{
			printf 'latest_tag=%s\n' "$latest_tag"
			printf 'pkg_version=%s\n' "$package_version"
			printf 'release_tag=%s\n' "$release_tag"
		} >> "$GITHUB_OUTPUT"
	fi
	exit 0
fi

tag_html="$(fetch "${RELEASE_ROOT}/${latest_tag}/")"
release_subdir="$(
	printf '%s\n' "$tag_html" |
		grep -Eo '\./[0-9][^"/]*_lucky/' |
		sed 's#^\./##; s#/$##' |
		grep -v '_docker$' |
		head -n 1 || true
)"

if [ -z "$release_subdir" ]; then
	echo "未在 ${RELEASE_ROOT}/${latest_tag}/ 找到 Lucky 核心目录。" >&2
	exit 1
fi

release_dir="${latest_tag}/${release_subdir}"
release_html="$(fetch "${RELEASE_ROOT}/${release_dir}/")"
source_file="$(
	printf '%s\n' "$release_html" |
		grep -Eo "lucky_[^\"<> ]+_Linux_${CORE_ARCH}\\.tar\\.gz" |
		sort -u |
		head -n 1 || true
)"

if [ -z "$source_file" ]; then
	echo "未在 ${RELEASE_ROOT}/${release_dir}/ 找到 Linux_${CORE_ARCH} 核心包。" >&2
	exit 1
fi

upstream_version="${source_file#lucky_}"
upstream_version="${upstream_version%_Linux_${CORE_ARCH}.tar.gz}"
source_url="${RELEASE_ROOT}/${release_dir}/${source_file}"

# 保存到 lucky/dl/ 目录：openwrt/gh-action-sdk 会将工作区挂载为 /feed，
# lucky/Makefile 通过 $(CURDIR)/dl/ 可直接读取本地预下载包，彻底避免容器内二次拉取超时
rm -rf "$REPO_ROOT/lucky/dl"
mkdir -p "$REPO_ROOT/lucky/dl"
target_file="$REPO_ROOT/lucky/dl/$source_file"

echo "正在下载 Lucky 核心包到 lucky/dl/ 目录..."
curl --connect-timeout 15 --retry 5 --retry-delay 3 -fsSL "$source_url" -o "$target_file"
source_hash="$(sha256sum "$target_file" | awk '{ print $1 }')"

# 校验远程 sha256 文件
sha256_url="${source_url}.sha256"
if remote_sha256="$(fetch "$sha256_url" 2>/dev/null | awk '{ print $1 }')" && [ -n "$remote_sha256" ]; then
	if [ "$source_hash" != "$remote_sha256" ]; then
		echo "错误: 下载的核心包 ($source_hash) 与远程校验和 ($remote_sha256) 不匹配！" >&2
		exit 1
	fi
	echo "校验和 ($source_hash) 匹配成功。"
else
	echo "提示: 未找到远程 sha256 校验文件 ($sha256_url)，使用本地计算的哈希值。"
fi

export PACKAGE_VERSION="$package_version"
export UPSTREAM_VERSION="$upstream_version"
export CORE_ARCH
export RELEASE_DIR="$release_dir"
export SOURCE_HASH="$source_hash"
export RELEASE_ROOT
export SOURCE_URL="$source_url"
export LUCKY_TAG="$latest_tag"

"$PYTHON_BIN" <<'PY'
import os
import re
from pathlib import Path


def update_assignments(path, values):
    file_path = Path(path)
    text = file_path.read_text(encoding="utf-8")
    for key, value in values.items():
        text, count = re.subn(
            rf"^{re.escape(key)}:=.*$",
            f"{key}:={value}",
            text,
            flags=re.MULTILINE,
        )
        if count == 0:
            raise SystemExit(f"{path} 缺少 {key} 配置")
    file_path.write_text(text, encoding="utf-8", newline="\n")


update_assignments(
    "lucky/Makefile",
    {
        "PKG_VERSION": os.environ["PACKAGE_VERSION"],
        "PKG_RELEASE": "1",
        "LUCKY_UPSTREAM_VERSION": os.environ["UPSTREAM_VERSION"],
        "LUCKY_CORE_ARCH": os.environ["CORE_ARCH"],
        "LUCKY_RELEASE_DIR": os.environ["RELEASE_DIR"],
        "PKG_HASH": os.environ["SOURCE_HASH"],
    },
)

update_assignments(
    "luci-app-lucky/Makefile",
    {
        "PKG_VERSION": os.environ["PACKAGE_VERSION"],
    },
)
PY

{
	printf 'LUCKY_TAG=%s\n' "$LUCKY_TAG"
	printf 'PKG_VERSION=%s\n' "$PACKAGE_VERSION"
	printf 'LUCKY_UPSTREAM_VERSION=%s\n' "$UPSTREAM_VERSION"
	printf 'LUCKY_CORE_ARCH=%s\n' "$CORE_ARCH"
	printf 'LUCKY_RELEASE_ROOT=%s\n' "$RELEASE_ROOT"
	printf 'LUCKY_RELEASE_DIR=%s\n' "$RELEASE_DIR"
	printf 'LUCKY_SOURCE_FILE=%s\n' "$source_file"
	printf 'LUCKY_SOURCE_URL=%s\n' "$SOURCE_URL"
	printf 'PKG_HASH=%s\n' "$SOURCE_HASH"
} > .lucky-release.env

if [ -n "${GITHUB_ENV:-}" ]; then
	{
		printf 'LUCKY_TAG=%s\n' "$LUCKY_TAG"
		printf 'LUCKY_PKG_VERSION=%s\n' "$PACKAGE_VERSION"
		printf 'LUCKY_UPSTREAM_VERSION=%s\n' "$UPSTREAM_VERSION"
		printf 'LUCKY_CORE_ARCH=%s\n' "$CORE_ARCH"
		printf 'LUCKY_RELEASE_DIR=%s\n' "$RELEASE_DIR"
		printf 'LUCKY_SOURCE_URL=%s\n' "$SOURCE_URL"
		printf 'LUCKY_CORE_HASH=%s\n' "$SOURCE_HASH"
	} >> "$GITHUB_ENV"
fi

echo "Lucky 目标版本: ${LUCKY_TAG} (PKG_VERSION=${PACKAGE_VERSION})"
echo "核心包: ${SOURCE_URL}"
echo "sha256: ${SOURCE_HASH}"
