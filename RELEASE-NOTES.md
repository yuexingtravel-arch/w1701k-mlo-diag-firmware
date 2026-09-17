# MLO-diag-20260916 r0-94bf0a3-mlodiag1

适用设备：Gemtek W1701K，板型 `gemtek,w1701k-ubi`。

## 版本信息

- ImmortalWrt：`r0-94bf0a3`
- Linux：`6.18.38`
- mt76 / mt7996：`6.18.38.2026.07.01~59676919-r2`
- mt7996 PS-sync：完整 TLV 边界检查修复
- 构建用途：MLO Link Removal、MLD 重建和性能诊断

## 镜像用途

- `*-squashfs-sysupgrade.itb`：从兼容的 W1701K ImmortalWrt 系统升级时使用。
- `*-initramfs-recovery.itb`：恢复环境使用，不作为日常 sysupgrade 镜像。
- `*-chainload-uboot.itb`：引导链相关用途，不作为日常 sysupgrade 镜像。

日常刷写只使用 `squashfs-sysupgrade.itb`，并先核对设备板型及 SHA-256。不要把 W1700K、XR1710G 或其他 AN7581 设备的镜像混用。

## 验证结果

- `sysupgrade -T` 兼容性检查通过，实机刷写和启动通过。
- LAN 2.5G、三频无线、overlay、SSH/LuCI 均通过。
- MLO 双 Link 关联、Link 1/Link 2 标准移除、剩余 Link 接管和 MLD 重建均通过。
- 测试期间未出现 RCU stall、PS-sync 卡死、firmware reset/assert、panic 或 watchdog。
- 当前 FastConnect 7800 会话协商为 `max_simul_links=1`，MLO 提供链路接管，但没有形成 5 GHz 与 6 GHz 的并行吞吐叠加。

完整测试结论见 `COMPLETE-MLO-TEST-RESULT.md`，终端判断见 `CLIENT-WIFI-DIAGNOSIS.md`，刷写门槛见 `FLASH-GATE.md`。

## 重要限制

此版本启用了 `CONFIG_TESTING_OPTIONS`，用于暴露 hostapd 的 `remove_link` / `disable_mld` 诊断接口。它是经过实机验证的诊断固件，不建议作为长期生产固件。长期使用应重新构建保留 PS-sync 修复但关闭测试接口的生产版本，并完成短回归测试。

## 固件 SHA-256

```text
36034dfc2a67e2f035d2712cb11c90601a49e80cac422124127418cccdc65d1a  immortalwrt-mlo-diag-20260916-r0-94bf0a3-mlodiag1-airoha-an7581-gemtek_w1701k-ubi-chainload-uboot.itb
5e21aa8fda068721435fd7baea02a54e947e839049843f347882ca574c9c529f  immortalwrt-mlo-diag-20260916-r0-94bf0a3-mlodiag1-airoha-an7581-gemtek_w1701k-ubi-initramfs-recovery.itb
2c812fc8b7822a0adc1de291b7169d836149a61e8ada2571d5a7845adc398871  immortalwrt-mlo-diag-20260916-r0-94bf0a3-mlodiag1-airoha-an7581-gemtek_w1701k-ubi-squashfs-sysupgrade.itb
```



