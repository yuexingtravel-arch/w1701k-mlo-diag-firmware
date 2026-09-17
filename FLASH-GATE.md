# 诊断固件最终刷写门禁

日期：2026-09-16

## 当前结论

诊断固件已完成本地、镜像内部和 AP 端兼容性核验，并已成功刷入 AP。启动、基础健康、Link 1 标准移除和最终安全恢复均已完成。

## 已通过

- 当前 AP 板型：`gemtek,w1701k-ubi`
- 当前运行版本：`MLO-fix-20260915 r0-94bf0a3-mlofix`
- 当前 Boot ID：`<redacted-boot-id>`
- 候选 sysupgrade SHA-256：`2c812fc8b7822a0adc1de291b7169d836149a61e8ada2571d5a7845adc398871`
- 本地和 AP 端候选镜像哈希一致
- AP 端 `sysupgrade -T` 返回 0
- MLO 保持 `disabled=1`、`mlo=0`
- 2.4 GHz `hidden=1`
- 未提交无线改动为 0
- 关键内核日志计数为 0
- Redmi 备用 AP 管理链路在线，BSSID `<redacted-mac>`
- 完整备份 SHA-256 清单共 37 项，本次复核全部通过
- 当前生产观察版回刷镜像仍在，SHA-256：`da64a4a898a679d0e343067e9cfcf6f4bee51b611aa5debe2909b3bd39ce471a`
- 原 SNAPSHOT 回退镜像仍在，SHA-256：`ec1b345d3f0f04965b610c4655aa8dbf21de78bb92c26685ad0d61143873fb28`
- 用户已确认物理 Reset 可恢复初始状态

## 剩余风险

现场仍没有 3.3 V USB-TTL UART。若设备在内核启动前失去网络且物理 Reset/recovery 也无法进入，就不能立即通过串口手动执行 `run boot_recovery`。本次变更仅在已正常运行的同一源码、同一内核和同一 mt76 修复上增加 hostapd `CONFIG_TESTING_OPTIONS`，但该硬件恢复限制仍然存在。

## 正式刷写步骤

获得最终刷写指令后：

1. 再次校验本地候选镜像 SHA-256。
2. 上传到 AP `/tmp`，再次校验远端 SHA-256 和 `sysupgrade -T`。
3. 使用标准 `sysupgrade -v` 保留现有配置；不使用 `-n`、`-F`、chainloader 或 initramfs 文件。
4. 等待 AP 重启并稳定，禁止中途断电、拔线或按键。
5. 先保持 MLO 关闭，验证版本、板型、2.5G 上联、三频 PHY、2.4 GHz 隐藏设置、overlay、SSH/LuCI、Boot ID 和关键日志。
6. 确认最终镜像的 `hostapd_cli` 可见 `remove_link`。
7. 基础稳定至少 15 分钟后才启用测试 MLO；首次只对 Link 1 执行一次标准 `remove_link 20` 探针。
8. 探针完成后通过 Redmi 管理链路执行 `wifi reload`，确认两条 Link 恢复，最后关闭 MLO并回到 Redmi 备用 AP。

## 立即回退条件

出现启动循环、管理地址超过 15 分钟不可达、任一无线 PHY 消失、2.5G 上联失败、UBI/UBIFS 错误、firmware reset/assert、RCU stall、kernel panic、watchdog 或配置异常时，不进入 MLO 测试。系统仍可管理时，优先刷回当前生产观察版镜像；管理失效时按已确认的物理 Reset 恢复流程处理。
## 实际执行结果

- 刷写成功，运行版本为 `MLO-diag-20260916 r0-94bf0a3-mlodiag1`。
- 启动后 Boot ID 为 `<redacted-boot-id>`。
- 2.5G、三频无线、overlay、SSH/LuCI 和 `remove_link` 命令正常。
- MLO 连续关联约 2 小时 43 分钟，无关键错误。
- Link 1 标准移除后只剩 6 GHz Link，通信零丢包。
- Windows Link 显示存在缓存；真实 Link 数改由 AP 侧判断。
- 普通 `wifi reload` 不能恢复已移除 Link；完整 MLD 拆除/重建可恢复 2 条 Link。
- 最终 MLO 关闭，未提交无线改动为 0，电脑连接 Redmi 备用 AP。

