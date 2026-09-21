# TTLM 与多链调度调研结论

## 结论

真正缺少的是 mt7996 的 negotiated TTLM、动态多链调度和端到端 QoS/TID 映射，而不只是 hostapd 协商位。本版本没有强制启用尚不能被驱动完整消费的能力。

## 当前状态与缺口

- Linux/mac80211 已有 TTLM 框架和相关状态接口。
- 当前 OpenWrt/mt76 没有形成 `BSS_CHANGED_MLD_TTLM` 到 mt7996 固件/队列调度的完整闭环。
- 当前 mt7996 已用 `link_id = (tid % 2) ? seclink : deflink` 固定选链；这能按 TID 分流，但不是 negotiated TTLM，也不会自动聚合普通 TID 0 业务。
- 当前 hostapd 源码会在底层能力不足时清除 TID-to-Link Mapping 协商位。
- 只修改 hostapd capability 或配置项，最多改变协商报文，不能自动产生可靠的动态多链发送调度。

## 最新上游复核

截至 2026-09-21 检查的 openwrt/mt76 主线 HEAD `be5ce7910521492d4a2e4ce7ee3843680a46c047`，仍保留相同的 TID 奇偶选链逻辑，没有找到 mt7996 完整 TTLM 实现。因此升级或简单回移植最新 mt76 不能解决本项目的透明双链聚合目标。

## 可借鉴实现

调研过 `woziwrt/mt7996-wifi7-manager`。它面向 MTK SDK/BPI-R4，并提到 `mlo-steerd` 与 negotiated TTLM，但公开仓库没有提供足以在本树中复现完整闭环的 daemon 与驱动实现，不能直接移植后宣称功能完成。

## 若继续开发所需工作

1. 在入口处可靠地把 DSCP/业务分类映射为 skb priority/TID。
2. 实现 negotiated TTLM 或动态选链，取代固定 TID 奇偶规则。
3. 正确处理每链 BA、重排、队列和故障回退。
4. 驱动能够消费映射后，再启用 hostapd TID-to-Link 协商位。
5. 增加逐客户端逐链 TX/RX 字节和包计数，并用受控射频衰减验证。

这些工作接近 mt76/mac80211/hostapd 与闭源 Windows 客户端驱动的联合研发，当前投入与风险不合理，项目暂时 No-Go。

## 重新验收条件

- 客户端和 AP 均显示 5+6 GHz 两条关联链路。
- 协商出的 TTLM 可从 hostapd/mac80211/driver 三层读取并一致。
- 固定业务流下，两条链的 TX/RX 计数都有可重复增量。
- 单链受控衰减后业务继续，恢复后调度重新使用该链。
- 长时间压力测试无 RCU stall、固件重启、队列卡死或明显乱序回退。
