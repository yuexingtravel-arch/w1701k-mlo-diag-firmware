# 恢复与回退

## 已保存的材料

本次刷写前配置备份位于 `preflash-backup/`，包含 sysupgrade 配置归档、包清单、MTD/UBI 布局和 SHA-256。

更完整的旧系统恢复材料保存在本机：

- `output/w1701k-current-backup-20260916/`
- `output/w1701k-mlo-diag-20260916/`

前者包含当前系统 FIT 镜像、sysupgrade 配置包、overlay、MTD NAND dump、UBI volume dump、factory/recovery/ubootenv 数据和校验清单。它们可用于低层恢复，但原始分区写入必须在能确认分区布局和启动路径时执行。

## 恢复层级

### 1. 配置错误，但设备仍能登录

先恢复 `preflash-backup/w1701k-preflash-20260921-065559.tar.gz`，或在 LuCI 的备份/升级页面上传该归档。恢复后重启网络或设备，并核对管理 IP。

### 2. 页面或无线配置不可用

长按 Reset 按键可恢复当前已安装固件的出厂配置。Reset 不会把固件自动降级到旧版本；它会清除/重建当前固件的配置 overlay。

### 3. 需要回刷上一版固件

设备仍能进入 LuCI/SSH 时，使用此前通过验证的 `w1701k-ubi` sysupgrade 镜像。先运行 `sysupgrade -T`，确认板型匹配和退出码为 0，再执行正式升级。回刷时应选择不保留配置，避免新旧版本配置格式冲突，之后再按需恢复旧版配置包。

### 4. 正常系统无法启动

发布包提供 initramfs recovery 和 chainload U-Boot 镜像。当前没有 3.3 V USB-TTL UART，因此只有在设备自身 bootloader/recovery 按键流程仍可进入时才能使用。不要从正常系统直接把原始 NAND dump 写回整片闪存。

## 刷写前检查

1. 保持备用 AP 在线，电脑使用稳定的有线或备用无线连接。
2. 核对板型为 `gemtek,w1701k-ubi`。
3. 核对目标文件 SHA-256。
4. 执行 `sysupgrade -T`，必须返回 0。
5. 确认配置备份和完整恢复目录可读取。
6. 刷写期间不要断电。

## 刷写后检查

确认管理地址可达、radio1/radio2 为 up、pending/retry_failed 为 false、`hostapd.ap-mld0` 为 `ENABLED`，然后检查系统日志中是否存在 RCU stall、mt7996 crash/timeout、Call trace 或 kernel panic。
