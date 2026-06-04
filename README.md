# luci-app-lucky

这是 Lucky 的 OpenWrt LuCI 插件和 Lucky 本体打包源码。

当前分支已切换到 Lucky `3.0.0 beta5`，上游核心包来自：

`https://release.66666.host/v3.0.0beta5/3.0.0_lucky/`

这里的 APK 指 OpenWrt 新版包管理器使用的 `.apk` 包格式，不是 Android APK。

## 支持架构

`lucky/Makefile` 会按 OpenWrt 构建环境自动选择 Lucky 上游核心包：

- `x86_64`
- `i386`
- `arm64`
- `armv5`
- `armv6`
- `armv7`
- `mips_softfloat`
- `mipsle_softfloat`
- `riscv64`

## 编译 APK 包

进入 OpenWrt 源码根目录后执行：

```sh
git clone https://github.com/gdy666/luci-app-lucky.git package/lucky
make defconfig
make package/lucky/lucky/compile V=s
make package/lucky/luci-app-lucky/compile V=s
```

使用新版 OpenWrt `apk` 包管理器的构建环境时，产物会生成 `.apk` 包；旧版构建环境仍会生成 `.ipk` 包。

## GitHub Actions 自动编译

仓库已内置 `.github/workflows/build-apk.yml`。

当 `lucky/Makefile` 或 `luci-app-lucky/Makefile` 更新并推送到 GitHub 后，GitHub Actions 会自动使用 OpenWrt Snapshot SDK 编译以下架构的 APK：

- `x86_64`
- `i386_pentium4`
- `aarch64_cortex-a53`
- `arm_cortex-a7_neon-vfpv4`
- `mips_24kc`
- `mipsel_24kc`
- `riscv64_riscv64`

编译完成后，工作流会读取 `lucky/Makefile` 中的 `PKG_VERSION`，创建或更新名为 `lucky-${PKG_VERSION}` 的 GitHub Release，并把编译好的 APK 文件上传到 Release。

如需减少或增加架构，修改 `.github/workflows/build-apk.yml` 里的 `matrix.arch` 即可。

## 在路由器上安装 APK

把编译出的 `lucky_*.apk`、`luci-app-lucky_*.apk` 和可选的 `luci-i18n-lucky-zh-cn_*.apk` 上传到路由器同一个目录，然后执行：

```sh
apk add --allow-untrusted ./lucky_*.apk ./luci-app-lucky_*.apk ./luci-i18n-lucky-zh-cn_*.apk
/etc/init.d/rpcd reload
/etc/init.d/uhttpd reload
/etc/init.d/lucky enable
/etc/init.d/lucky restart
```

也可以使用仓库内脚本：

```sh
sh scripts/install-apk.sh /path/to/apk-dir
```

## 升级注意

从旧版本或其他 Lucky LuCI 分支切换前，建议先在 Lucky 后台备份配置。

如果需要清理旧包，可按实际包管理器选择：

```sh
opkg remove lucky luci-i18n-lucky-zh-cn luci-app-lucky
```

或：

```sh
apk del lucky luci-i18n-lucky-zh-cn luci-app-lucky
```

## 截图

![](./previews/001.png)
![](./previews/002.png)
