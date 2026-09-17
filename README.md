# Gemtek W1701K MLO 诊断固件

日期：2026-09-16

GitHub Release 中提供三个固件镜像；仓库保存构建信息、补丁、测试脚本、经过脱敏的汇总证据和完整报告。下载及校验说明见 `RELEASE-NOTES.md` 与 `FIRMWARE-SHA256SUMS.txt`，恢复边界见 `RECOVERY-AND-ROLLBACK.md`，证据范围见 `EVIDENCE-SCOPE.md`。Qualcomm 客户端驱动回退备份未上传，避免再分发厂商二进制；设备专属完整备份也只离线保存，不上传到 GitHub。

本目录是用于验证标准 MLO Link Removal 的诊断构建。它已刷入 W1701K 并完成 Link 1、Link 2 单次实测；测试结束后 MLO 已关闭，电脑已切回 Redmi 备用 AP。

## 诊断固件

- 目标：`gemtek,w1701k-ubi`
- 版本：`MLO-diag-20260916 r0-94bf0a3-mlodiag1`
- 内核：`6.18.38`
- 源码：`94bf0a31351fdd5a36159c3e41c167954cd05048`
- mt76 / mt7996：`6.18.38.2026.07.01~59676919-r2`
- hostapd-utils / wpad-openssl：`2026.04.02~b004de0b-r3`
- PS-sync 完整修复补丁 SHA-256：`9e387af65d3a0433d3286c9bc2d73688d1b838a947d5ff20e5771d7ee8123722`
- sysupgrade 镜像 SHA-256：`2c812fc8b7822a0adc1de291b7169d836149a61e8ada2571d5a7845adc398871`

刷写候选文件：

`immortalwrt-mlo-diag-20260916-r0-94bf0a3-mlodiag1-airoha-an7581-gemtek_w1701k-ubi-squashfs-sysupgrade.itb`

## 与生产观察版的差异

诊断版只增加 hostapd 测试接口并提高包修订号：

- `CONFIG_TESTING_OPTIONS=y`
- 最终镜像内 `/usr/sbin/hostapd_cli` 包含 `remove_link` 和 `disable_mld`
- 不包含动态 `link_enable`；Link Removal 后需完整拆除并重建测试 MLD，普通 `wifi reload` 不足以恢复被移除的 Link
- mt76 PS-sync 修复、设备目标和其余构建基线保持不变

完成诊断后应回到不带测试接口的生产构建。

## 已通过的离线检查

- 完整固件构建成功，构建状态为 `FIRMWARE_COMPLETED`
- FIT 的默认配置、FDT 和 rootfs 均指向 `gemtek_w1701k-ubi`
- manifest 含 `hostapd-utils r3`、`wpad-openssl r3` 和 `kmod-mt7996e r2`
- 从最终 FIT 的 SquashFS 中提取了 `hostapd_cli`；确认含 `remove_link`
- 镜像内 `hostapd_cli` 与构建根文件系统二进制逐字节一致
- PS-sync 完整补丁及最小 TLV 长度检查已核验
- 标准探针 PowerShell 语法检查通过
- 全部固件和证据已有 SHA-256 清单

详细证据位于 `evidence`，完整校验值见 `SHA256SUMS.txt`。

## AP 兼容性、刷写和启动结果

- 上传后远端 SHA-256 与本地一致；
- `sysupgrade -T` 返回 0；
- 标准保留配置刷写成功；
- 当前运行版本为 `MLO-diag-20260916 r0-94bf0a3-mlodiag1`；
- 启动、overlay、SSH/LuCI、三频无线和 `remove_link` 命令正常；
- `lan1` 为 2500 Mbps 全双工，RX/TX error 为 0；
- 当前 Boot ID 为 `<redacted-boot-id>`，关键日志为 0；
- 测试结束后 MLO 已关闭，未提交无线改动为 0，电脑连接 Redmi 备用 AP。

兼容性检查记录见 `evidence/AP-COMPATIBILITY-CHECK.md`，最终安全状态见 `evidence/post-flash-final-safe-state-20260917.log`。
## 实机 Link Removal 结果

Link 1 与 Link 2 的标准 `remove_link 20` 均已通过 AP 侧验证：两个方向都由剩余 Link 保持通信；每轮 AP 和主路由各 123 个连续样本均零丢包，Boot ID 未变，关键日志为 0。

Windows 在 15 秒观察窗内仍缓存显示两条 Link，因此不再作为硬判据。普通 `wifi reload` 也不能恢复被移除的 Link；完整拆除并重建 MLD 已验证可恢复两条 Link。详细结果见 `STANDARD-LINK-REMOVAL-RESULT.md`。
## 标准 Link Removal 探针

脚本：`g3-mlo-single-link-probe.ps1`

首次仅执行 Link 1：

```powershell
powershell.exe -File .\g3-mlo-single-link-probe.ps1 -LinkId 1 -BeaconCount 20
```

脚本会：

- 要求起始基线为已提交的 MLO 关闭状态；
- 临时启用测试 MLO并确认 AP/Windows 均有两条 Link；
- 调用标准 `remove_link 20` 并保存 100 ms 连通性原始样本；
- 使用 AP 侧 `iw dev ap-mld0 info` 判断实际活动 Link，Windows 列表只作参考；
- 要求剩余 Link 的最长业务中断不超过 3 秒；
- 完整拆除并重建 MLD，确认两条 Link 恢复；
- 无论成功或失败，最终提交 MLO 关闭并切回 Redmi 备用 AP。

Link 1、Link 2 均已完成单次实测。

## 完整测试完成

完整 MLD 重建、Windows 双 Link 恢复、5 GHz/160、6 GHz/320、MLO 160+320、MLO 160+160、逐无线电调度和 2.5G 有线回程测试均已完成。当前会话协商为 `max_simul_links=1`，批量 TCP 流量主要由 6 GHz Link 2 承载，因此 MLO 没有表现出双 Link 吞吐叠加。

完整结果、限制和推荐配置见 `COMPLETE-MLO-TEST-RESULT.md`。用于复现的脚本为 `mlo-association-rebuild-test.ps1` 与 `mlo-performance-matrix.ps1`。





