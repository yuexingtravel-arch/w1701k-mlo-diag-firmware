# 测试结果

测试对象为已刷入 `MLO-safe-20260921` 的 W1701K 和 Qualcomm FastConnect 7800 / QCNCM865 Windows 客户端。

## 刷写与启动

| 项目 | 结果 |
|---|---|
| 刷前 `sysupgrade -T` | 通过 |
| 正式刷写后重新上线 | 通过，约 21 秒后恢复访问 |
| 最终 1.1.1 重建镜像 `sysupgrade -T` | 通过，退出码 0 |
| radio1/radio2 | `true/false/false`（up/pending/retry_failed） |
| hostapd MLO 对象 | `ap-mld0 = ENABLED` |
| 未提交 wireless UCI 变更 | 0 |
| 关键崩溃日志匹配 | 0 |

## 页面回归

无配置变化执行一次保存/重载，首次状态轮询即达到 ready。两组 radio 正常，hostapd 保持 `ENABLED`，按钮和进度流程正常结束。最终安装包版本为 `1.1.1-r20260921`。

## 射频与 MLO 关联

| 项目 | AP 端结果 |
|---|---|
| 5 GHz | channel 149，160 MHz |
| 6 GHz | channel 37，320 MHz |
| MLO links | hostapd 报告 `num_links=2` |
| 客户端能力 | EHT、6 GHz，`max_simul_links=1`（N-1 编码，代表最多 2 条同时链路） |

Windows 同时显示 Link 1 为 5 GHz、Link 2 为 6 GHz，Radio type 为 802.11be。Windows `netsh` 对 5 GHz 宽度的显示与 AP 的 `iw` 结果不一致，因此射频宽度以 AP 内核状态为准。

## 初始吞吐复测

| 路径 | 结果（约） |
|---|---:|
| Windows → 主路由 TCP | 85–89 Mbit/s |
| 主路由 → Windows TCP | 203–213 Mbit/s |
| Windows → AP TCP | 79–80 Mbit/s |
| AP → Windows TCP（反向模式） | 184–190 Mbit/s |
| Windows → AP UDP，目标 800 Mbit/s | 接收约 75–86 Mbit/s，记录丢包 0% |
| AP 主动连接 Windows iperf3 | 连接超时，Windows 端口不可达 |

这些值属于客户端或测试环境异常，不能视为固件性能上限，也不能据此证明双链聚合。

## 最终分 TID 与逐射频验证

重新连接 `Gemtek_W1701K_MLO` 后，Windows 明确显示 Link 1 为 5 GHz/160 MHz、Link 2 为 6 GHz/320 MHz。

普通 TID 0 的四流下行达到约 1093.8 Mbit/s。测试前后 AP 发送成功 MPDU 增量为：

| 射频 | 增量 |
|---|---:|
| 5 GHz / band 1 | 0 |
| 6 GHz / band 2 | 136,800 |

尝试以 iperf ToS `0x20` 产生另一业务类别时，5 GHz 增量仍为 0，6 GHz 增加 1,205，吞吐约 25.1 Mbit/s。这说明当前 Windows、路由器和 AP 之间没有形成可用的端到端 TID 分类；双链关联成功，但普通业务没有并发使用两条链。

原始结果保存在 `evidence/mlo-safe-20260921/` 下的 `IPERF-MLO-*` 和 `MLO-TID-BAND-COUNTERS.json`。

## 稳定性结论

测试后 AP 仍可访问，MLO hostapd 对象保持 `ENABLED`，未出现 RCU stall、mt7996 crash/timeout、Call trace 或 kernel panic。PS-sync 原始死循环故障在本轮没有复现。

综合结论参见 `GO-NO-GO-EVALUATION-20260921.md`：保留稳定固件，暂停继续开发透明双链吞吐聚合。
