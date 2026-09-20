# TTLM 与多链调度调研结论

## 结论

真正需要继续开发的是 mt7996 的完整 TTLM 和多链发送数据面，而不只是打开 hostapd 的协商位。本版本没有强制启用尚不能被驱动完整消费的能力。

## 当前缺口

- Linux/mac80211 已有 TTLM 框架和相关状态接口。
- 当前使用的 OpenWrt/mt76 源码没有形成 `BSS_CHANGED_MLD_TTLM` 到 mt7996 固件/队列调度的完整闭环。
- 当前 hostapd 源码会在底层能力不足时清除 TID-to-Link Mapping 协商位。
- 只修改 hostapd capability 或配置项，最多改变协商报文，不能自动产生可靠的逐 TID 多链发送调度。

## 可借鉴实现

调研过 `woziwrt/mt7996-wifi7-manager`。它面向 MTK SDK/BPI-R4，并提到 `mlo-steerd` 与 negotiated TTLM，但公开仓库没有提供足以在本树中复现完整闭环的 daemon 与驱动实现，不能直接移植后宣称功能完成。

## 后续实现门槛

1. 回移植 mac80211/cfg80211 的完整 TTLM 状态变化处理。
2. 在 mt76/mt7996 中把协商映射下发到真实的发送路径和固件命令。
3. 明确队列、TID、link ID 的选择与故障回退行为。
4. 驱动能够消费配置后，再启用 hostapd TID-to-Link 协商位。
5. 用可观测的逐链 TX byte/packet 计数和受控射频衰减验证，而不是通过暂停整个 MLD 的软件方法推断链路接管。

## 验收标准

- 客户端和 AP 均显示 5+6 GHz 两条关联链路。
- 协商出的 TTLM 可从 hostapd/mac80211/driver 三层读取并一致。
- 固定业务流下，两条链的 TX/RX 计数都有可重复的增量。
- 单链受控衰减或屏蔽后业务继续，恢复后调度可重新使用该链。
- 长时间压力测试无 RCU stall、固件重启、队列卡死或明显乱序回退。
