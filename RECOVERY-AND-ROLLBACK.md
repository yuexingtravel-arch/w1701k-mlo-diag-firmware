# W1701K 恢复与回退说明

本说明适用于本仓库的 Gemtek W1701K 诊断固件。设备板型必须是 `gemtek,w1701k-ubi`。

## 已准备的回退层级

1. **正常软件回退**：设备仍可通过 LuCI 或 SSH 管理时，刷回已验证的 W1701K `squashfs-sysupgrade.itb`。
2. **物理 Reset / 设备恢复流程**：管理网络不可达时，使用已验证可恢复初始状态的 Reset 流程。
3. **Recovery / UART**：只有前两种方式均不可用时才进入底层恢复。测试现场没有连接 3.3 V USB-TTL UART，因此本版本的风险边界不包含实测 UART 恢复。

完整设备备份、原系统回退镜像、配置包、overlay、UBI 卷和 MTD 分区镜像已经单独离线保存并完成 SHA-256 校验。它们包含设备专属配置、主机密钥、授权密钥、校准数据和硬件标识，因此不上传到 GitHub。

## 刷写前检查

- 确认设备型号及板型为 W1701K / `gemtek,w1701k-ubi`。
- 使用 `FIRMWARE-SHA256SUMS.txt` 核对下载文件。
- 日常升级只选择 `*-squashfs-sysupgrade.itb`。
- 在设备端先运行 `sysupgrade -T`，只有返回 0 才继续。
- 不使用 `-F` 强刷，不把 W1700K、XR1710G 或其他 AN7581 设备镜像混用。
- 保持备用 AP、稳定供电和有线管理路径可用。
- 刷写期间不拔线、不断电、不按 Reset。

## 标准刷写

```sh
sha256sum /tmp/immortalwrt-mlo-diag-20260916-r0-94bf0a3-mlodiag1-airoha-an7581-gemtek_w1701k-ubi-squashfs-sysupgrade.itb
sysupgrade -T /tmp/immortalwrt-mlo-diag-20260916-r0-94bf0a3-mlodiag1-airoha-an7581-gemtek_w1701k-ubi-squashfs-sysupgrade.itb
sysupgrade -v /tmp/immortalwrt-mlo-diag-20260916-r0-94bf0a3-mlodiag1-airoha-an7581-gemtek_w1701k-ubi-squashfs-sysupgrade.itb
```

本次实机刷写采用保留配置的标准 `sysupgrade -v`，并已通过启动、overlay、SSH/LuCI、三频无线和 2.5G LAN 验证。

## 立即停止或回退的条件

出现以下任一情况时，不启用 MLO 测试：

- 启动循环或管理地址超过 15 分钟不可达；
- 任一无线 PHY 消失；
- 2.5G 上联失败；
- UBI/UBIFS 错误；
- firmware reset/assert、RCU stall、kernel panic 或 watchdog；
- 配置异常且无法通过普通重载恢复。

设备仍可管理时，刷回离线保存并已通过 `sysupgrade -T` 的旧版 W1701K sysupgrade 镜像。管理失效时，使用物理 Reset 恢复流程。不要直接盲写 UBI/MTD 原始镜像。

## 固件角色

- `squashfs-sysupgrade.itb`：标准升级和正常回退路径。
- `initramfs-recovery.itb`：RAM/recovery 环境使用。
- `chainload-uboot.itb`：引导链用途，不能替代标准 sysupgrade 镜像。

当前发布版启用了 `CONFIG_TESTING_OPTIONS`，用于 MLO 诊断。完成诊断后，长期运行应换成保留 mt7996 PS-sync 修复但关闭测试接口的生产构建。


