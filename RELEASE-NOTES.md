# Release notes: mlo-safe-20260921-mlosafe2

## 变更

1. 修复 `/cgi-bin/luci/admin/network/wifi7` 保存进度卡住。
   - 从 `network.wireless status` 动态发现运行时 MLO ifname。
   - 使用真实的 `hostapd.ap-mld0` 状态，不再硬编码错误对象。
   - 保存流程加入超时、错误捕获和按钮恢复。
   - 使用受限的 `/sbin/wifi reload`，避免扩大为通用 shell RPC 权限。
2. 修正 Wi-Fi 7 页面带宽显示。
   - hostapd `eht_oper_chwidth=2` 显示为 160 MHz。
   - hostapd `eht_oper_chwidth=9` 显示为 320 MHz。
3. 完整保留 mt7996 PS-sync 防死循环修复。
   - 检查事件最小长度。
   - 拒绝短于 TLV header 的长度。
   - 校验单客户端结构和多客户端数组边界。
4. 保持 hostapd TTLM 能力保护。
   - 没有在 mt7996 数据面尚不完整时强制公布 TID-to-Link 协商能力。

## 实机结果

- 目标：Gemtek W1701K `gemtek_w1701k-ubi`
- 内核：6.18.38
- 最终页面包：`luci-app-wifi7 1.1.1-r20260921`
- 页面保存/重载：通过
- 5 GHz：160 MHz
- 6 GHz：320 MHz
- QCNCM865：5+6 GHz 双链关联可见
- PS-sync/RCU stall 回归：未复现
- 最终镜像 `sysupgrade -T`：退出码 0

## 已知限制

- 未证明 TTLM 或同一业务的真实双链聚合。
- 当前吞吐复测偏低；Windows 网卡的 RSS 和吞吐加速设置需要管理员权限才能进一步验证。
- AP 到 Windows 的反向 iperf3 测试因 Windows 监听端口不可达而超时。
- 本版本应作为预发布版本使用。
