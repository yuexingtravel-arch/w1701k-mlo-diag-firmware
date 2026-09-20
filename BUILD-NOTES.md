# 构建说明

## 源码

- 构建树：`/home/felix/w1701k-mlo-build/source`
- 分支：`codex/w1701k-wifi7-save-fix`
- 基础提交：`94bf0a31351fdd5a36159c3e41c167954cd05048`
- 目标：`airoha/an7581/gemtek_w1701k-ubi`
- 内核：6.18.38

源码改动保存在 `source-changes-20260921.diff`，工作树状态保存在 `source-status-20260921.txt`。差异文件包含未跟踪的 `0012-mt7996-fix-ps-sync-complete.patch`。

## 包版本

- `luci-app-wifi7 1.1.1-r20260921`
- mt76 package release 2

最终 manifest 已确认包含 `luci-app-wifi7 - 1.1.1-r20260921`。

## 构建环境注意事项

Windows PATH 中存在 `Files/Calibre2/` 这样的相对项，WSL 继承后会触发 GNU `find -execdir` 的安全检查并导致构建失败。最终构建仅对该构建进程使用以下干净 PATH：

```text
/home/felix/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
```

该处理没有修改 Windows 的全局 PATH。

## 最终 sysupgrade 镜像

```text
immortalwrt-mlo-safe-20260921-r0-94bf0a3-mlosafe2-airoha-an7581-gemtek_w1701k-ubi-squashfs-sysupgrade.itb
SHA-256: 3159ba360f77b96bdabcf0a6d15c6af9c60a929ad069df5b80be95c0261bb661
```

该最终镜像在目标 AP 上执行 `sysupgrade -T` 返回 0。AP 当前固件主体已完成实机刷写，随后以独立 IPK 更新到相同的 1.1.1 页面代码；最终整机镜像把该页面版本直接内置到 rootfs。
