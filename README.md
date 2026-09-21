# W1701K MLO-safe 2026-09-21

这是面向 `Gemtek W1701K (w1701k-ubi)` 的 ImmortalWrt 预发布固件，基于 `r0-94bf0a3`、Linux `6.18.38`。本版修复 Wi-Fi 7 页面保存后长期卡住的问题，并保留 mt7996 PS-sync 事件的完整边界检查。

## 适用范围

- 设备：Gemtek W1701K
- 镜像布局：`gemtek_w1701k-ubi`
- 版本：`MLO-safe-20260921 / r0-94bf0a3-mlosafe2`
- Wi-Fi 7 页面：`luci-app-wifi7 1.1.1-r20260921`

不要把这些镜像用于 W1700K、XR1710G 或其他 AN7581 设备。刷写前必须核对设备板型和镜像 SHA-256。

## 已实现

- Wi-Fi 7 页面动态发现运行中的 MLO 接口和 hostapd 对象，不再依赖错误的 `hostapd.ap-mld-1`。
- 保存时明确调用 `/sbin/wifi reload`，增加分阶段超时、失败提示和按钮恢复。
- 保存完成条件同时检查 radio 状态、pending/retry 状态、MLO ifname 和 hostapd `ENABLED`。
- 修正 hostapd 带宽枚举：`2 = 160 MHz`，`9 = 320 MHz`。
- 保留完整 PS-sync 修复：TLV 头、单客户端结构、多客户端数组及事件最小长度检查。
- 仅增加 `network.wireless status` 的只读 RPC 权限，没有授予 LuCI 通用 shell 权限。

## 已验证

- 固件已在目标 W1701K 上刷写并启动。
- 页面无变化保存/重载一次完成，radio1/radio2 均为 `up=true`，hostapd `ap-mld0` 为 `ENABLED`。
- AP 报告 5 GHz 160 MHz、6 GHz 320 MHz。
- Windows QCNCM865 报告 802.11be、5 GHz + 6 GHz 两条关联链路。
- 测试期间没有发现 RCU stall、mt7996 crash/timeout、Call trace 或 kernel panic。

## 最终 MLO 评估

此版本没有宣称完成真正的双链数据聚合或 negotiated TTLM。当前 mt7996 已按 TID 奇偶在默认链和第二链之间固定选链，但缺少完整 TTLM 消费、动态负载调度和端到端 QoS 映射；hostapd 也保留了能力保护逻辑。QCNCM865 的双链关联成立，普通 TCP/UDP 流量仍主要使用 6 GHz 默认链。

早期复测约为 80–213 Mbit/s，属于客户端/测试环境异常；后续在稳定双链关联下，普通 TID 0 下行达到约 1093.8 Mbit/s，但 AP 计数证明数据只走 6 GHz。Windows 侧 RSS 和 Throughput Acceleration 均为关闭，修改被系统以“拒绝访问”阻止。

最终 Go/No-Go 结论是暂停继续开发透明 5+6 GHz 带宽聚合，保留当前稳定固件。详见 `GO-NO-GO-EVALUATION-20260921.md`、`RELEASE-NOTES.md`、`TEST-RESULTS.md`、`TTLM-RESEARCH.md`、`RECOVERY-AND-ROLLBACK.md` 和 `BUILD-NOTES.md`。
