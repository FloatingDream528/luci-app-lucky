# luci-app-lucky

这是 Lucky 的 OpenWrt LuCI 插件和 Lucky 本体 x86_64 APK 打包源码。

当前分支适配 Lucky `3.0.0 beta5`，Lucky 核心包来自：

`https://release.66666.host/v3.0.0beta5/3.0.0_lucky/`

这里的 APK 指 OpenWrt 新版包管理器使用的 `.apk` 包格式，不是 Android APK。

## x86_64 APK 方式

Release 只发布 x86_64 机型使用的 APK。

`lucky` 包内直接打包 `x86_64` Lucky 核心到 `/usr/bin/lucky`。安装或启动服务时不会再下载核心。

内置的 Lucky 核心架构：

- `x86_64`

## GitHub Actions 自动编译

仓库内置 `.github/workflows/build-apk.yml`。

当 `lucky/`、`luci-app-lucky/` 或 workflow 更新并推送到 GitHub 后，GitHub Actions 会使用 OpenWrt Snapshot x86_64 SDK 编译 APK。

编译完成后，工作流会读取 `lucky/Makefile` 中的 `PKG_VERSION`，创建或更新名为 `lucky-${PKG_VERSION}` 的 GitHub Release，并上传 APK 文件。

## 在路由器上安装 APK

不要使用 LuCI 的“上传软件包”按钮安装 Release 中的 APK。该入口执行的是 `apk add /tmp/upload.apk`，不会带 `--allow-untrusted`，第三方未信任签名包会报 `UNTRUSTED signature`。

把 Release 中的 APK 上传到路由器同一个目录，然后执行：

```sh
apk add --allow-untrusted ./lucky-*.apk ./luci-app-lucky-*.apk ./luci-i18n-lucky-zh-cn-*.apk
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
